import Foundation
import ScreenCaptureKit
import OSLog
import AppKit
import AVFoundation
import SwiftUI
import Combine

@MainActor
class ScreenRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var availableDisplays: [SCDisplay] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var error: Error?
    @Published var renderConfig = RendererConfiguration()
    @Published var isPreviewingSettings = false
    @Published var isTranscribing = false
    @Published var transcriptionProgress: String? = nil
    
    // Internal State
    private var stream: SCStream?
    
    // Storage for non-isolated access (AVAssetWriter is thread-safe for appending)
    class Storage {
        var assetWriter: AVAssetWriter?
        var videoInput: AVAssetWriterInput?
        var audioInput: AVAssetWriterInput?  // System audio
        var micInput: AVAssetWriterInput?    // Microphone audio
        var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        var sessionStarted = false
        let sessionLock = NSLock()
        var firstSampleTime: CMTime = .zero
        var outputSize: CGSize?  // Store the output resolution
        var cameraPanel: CameraPreviewPanel?
        var cameraPanelFrame: CGRect?
        let cameraFrameLock = NSLock()
        var teleprompterPanel: NSPanel?
        var micWavWriter: AVAudioFile?
        var micWavURL: URL?
    }
    nonisolated let storage = Storage()
    
    // Microphone audio engine
    let audioEngine = AVAudioEngine()
    var micAudioQueue: DispatchQueue?
    
    // Components
    private let cursorManager = CursorManager()
    private let cameraManager = CameraManager()
    private let compositor = VideoCompositor()
    private var cancellables = Set<AnyCancellable>()
    
    private var lastCameraPosition: CameraPosition?

    @Published var teleprompterResetOffset = false

    override init() {
        super.init()
        
        Publishers.CombineLatest3($renderConfig, $isRecording, $isPreviewingSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] newConfig, isRecording, isPreviewing in
                guard let self = self else { return }
                self.updateCameraState(newConfig: newConfig, isRecording: isRecording, isPreviewing: isPreviewing)
            }
            .store(in: &cancellables)
            
        $renderConfig
            .receive(on: RunLoop.main)
            .sink { [weak self] newConfig in
                guard let self = self else { return }
                self.updateTeleprompterState(newConfig: newConfig)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        let panel = storage.cameraPanel
        let teleprompter = storage.teleprompterPanel
        DispatchQueue.main.async {
            panel?.orderOut(nil)
            teleprompter?.orderOut(nil)
        }
    }
    
    private func positionCameraPanel(panel: CameraPreviewPanel, config: RendererConfiguration) {
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = mainScreen.visibleFrame
        let size = config.cameraSize * 1.6
        
        let x: CGFloat
        let y: CGFloat
        
        switch config.cameraPosition {
        case .topLeft:
            x = screenFrame.minX + 20
            y = screenFrame.maxY - size - 20
        case .topRight:
            x = screenFrame.maxX - size - 20
            y = screenFrame.maxY - size - 20
        case .bottomLeft:
            x = screenFrame.minX + 20
            y = screenFrame.minY + 20
        case .bottomRight:
            x = screenFrame.maxX - size - 20
            y = screenFrame.minY + 20
        }
        
        panel.setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
    }
    
    private func updateCameraState(newConfig: RendererConfiguration, isRecording: Bool, isPreviewing: Bool) {
        let shouldShowCamera = (isRecording || isPreviewing) && newConfig.enableCamera
        
        if shouldShowCamera {
            cameraManager.start()
            
            let positionChanged = (lastCameraPosition != newConfig.cameraPosition)
            
            if storage.cameraPanel == nil {
                let panel = CameraPreviewPanel(
                    session: cameraManager.session,
                    shape: newConfig.cameraShape,
                    size: newConfig.cameraSize,
                    hasBorder: newConfig.enableCameraBorder,
                    onMove: { [weak self] rect in
                        guard let self = self else { return }
                        self.storage.cameraFrameLock.lock()
                        self.storage.cameraPanelFrame = rect
                        self.storage.cameraFrameLock.unlock()
                    }
                )
                storage.cameraPanel = panel
                
                positionCameraPanel(panel: panel, config: newConfig)
                self.lastCameraPosition = newConfig.cameraPosition
                
                panel.orderFront(nil)
                excludePanelsFromCapture()
            } else if let panel = storage.cameraPanel {
                if positionChanged {
                    positionCameraPanel(panel: panel, config: newConfig)
                    self.lastCameraPosition = newConfig.cameraPosition
                } else {
                    let size = newConfig.cameraSize * 1.6
                    let oldFrame = panel.frame
                    let newFrame = NSRect(
                        x: oldFrame.midX - size/2,
                        y: oldFrame.midY - size/2,
                        width: size,
                        height: size
                    )
                    panel.setFrame(newFrame, display: true)
                }
                
                let contentView = NSHostingView(
                    rootView: CameraPreviewBubbleView(
                        session: cameraManager.session,
                        shape: newConfig.cameraShape,
                        size: newConfig.cameraSize,
                        hasBorder: newConfig.enableCameraBorder,
                        panel: panel,
                        onMove: { [weak self] rect in
                            guard let self = self else { return }
                            self.storage.cameraFrameLock.lock()
                            self.storage.cameraPanelFrame = rect
                            self.storage.cameraFrameLock.unlock()
                        }
                    )
                )
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = .clear
                panel.contentView = contentView
                
                storage.cameraFrameLock.lock()
                storage.cameraPanelFrame = panel.frame
                storage.cameraFrameLock.unlock()
                
                excludePanelsFromCapture()
            }
        } else {
            if storage.cameraPanel != nil {
                storage.cameraPanel?.orderOut(nil)
                storage.cameraPanel = nil
                cameraManager.stop()
                
                storage.cameraFrameLock.lock()
                storage.cameraPanelFrame = nil
                storage.cameraFrameLock.unlock()
            }
            self.lastCameraPosition = nil
        }
    }
    
    private func updateTeleprompterState(newConfig: RendererConfiguration) {
        let shouldShow = newConfig.enableTeleprompter
        
        if shouldShow {
            if storage.teleprompterPanel == nil {
                let configBinding = Binding<RendererConfiguration>(
                    get: { [weak self] in self?.renderConfig ?? RendererConfiguration() },
                    set: { [weak self] in self?.renderConfig = $0 }
                )
                
                let resetBinding = Binding<Bool>(
                    get: { [weak self] in self?.teleprompterResetOffset ?? false },
                    set: { [weak self] in self?.teleprompterResetOffset = $0 }
                )
                
                let panel = TeleprompterPanel(
                    config: configBinding,
                    resetOffset: resetBinding,
                    onClose: { [weak self] in
                        guard let self = self else { return }
                        self.renderConfig.enableTeleprompter = false
                    }
                )
                storage.teleprompterPanel = panel
                panel.orderFront(nil)
                excludePanelsFromCapture()
            }
        } else {
            if let panel = storage.teleprompterPanel {
                panel.orderOut(nil)
                storage.teleprompterPanel = nil
                excludePanelsFromCapture()
            }
        }
    }
    
    private func excludePanelsFromCapture() {
        guard let stream = stream else { return }
        Task {
            do {
                let content = try await SCShareableContent.current
                var excludedWindows: [SCWindow] = []
                
                if let cameraPanel = storage.cameraPanel, cameraPanel.windowNumber > 0 {
                    let matching = content.windows.filter { $0.windowID == CGWindowID(cameraPanel.windowNumber) }
                    excludedWindows.append(contentsOf: matching)
                }
                
                if let teleprompterPanel = storage.teleprompterPanel, teleprompterPanel.windowNumber > 0 {
                    let matching = content.windows.filter { $0.windowID == CGWindowID(teleprompterPanel.windowNumber) }
                    excludedWindows.append(contentsOf: matching)
                }
                
                if let display = self.selectedDisplay {
                    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: excludedWindows)
                    try await stream.updateContentFilter(filter)
                }
            } catch {
                // Ignore
            }
        }
    }
    
    func fetchAvailableContent() async {
        do {
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
        } catch {
            self.error = error
        }
    }
    
    func startRecording() async {
        guard let display = selectedDisplay else {
            return
        }
        
        if renderConfig.enableTeleprompter {
            renderConfig.isTeleprompterScrolling = false
            teleprompterResetOffset = true
        }
        
        let saveDir = renderConfig.outputDirectory ?? FileManager.default.temporaryDirectory
        let fileURL = saveDir.appendingPathComponent("OneTake-\(Date().timeIntervalSince1970).mov")
        
        do {
            let assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
            storage.assetWriter = assetWriter
            
            // Reset zoom manager and compositor zoom state before starting capture
            cursorManager.reset()
            compositor.resetZoomState()
            
            // Use Recording Resolution size (ensuring even dimensions for H.264/HEVC encoding)
            let displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            let baseResolutionSize = renderConfig.recordingResolution.size(for: displaySize)
            let evenWidth = (Int(baseResolutionSize.width) / 2) * 2
            let evenHeight = (Int(baseResolutionSize.height) / 2) * 2
            let outputSize = CGSize(width: CGFloat(evenWidth), height: CGFloat(evenHeight))
            storage.outputSize = outputSize  // Store for use in compositor
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputSize.width,
                AVVideoHeightKey: outputSize.height
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            storage.videoInput = videoInput
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height
            ]
            
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            storage.pixelBufferAdaptor = pixelBufferAdaptor
            
            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            }
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128000
            ]
            let capturesSystemAudio = (renderConfig.audioMode == .screenOnly || renderConfig.audioMode == .both)
            let capturesMic = (renderConfig.audioMode == .micOnly || renderConfig.audioMode == .both || renderConfig.enableAutoSubtitles)
            let writeMicToVideo = (renderConfig.audioMode == .micOnly || renderConfig.audioMode == .both)
            
            // Audio Input (System Audio)
            if capturesSystemAudio {
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                storage.audioInput = audioInput
                
                if assetWriter.canAdd(audioInput) {
                    assetWriter.add(audioInput)
                }
            } else {
                storage.audioInput = nil
            }
            
            // Microphone Input
            if writeMicToVideo {
                let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                micInput.expectsMediaDataInRealTime = true
                storage.micInput = micInput
                
                if assetWriter.canAdd(micInput) {
                    assetWriter.add(micInput)
                }
            } else {
                storage.micInput = nil
            }
            
            // Initialize WAV file for subtitles if enabled
            if renderConfig.enableAutoSubtitles {
                let tempDir = FileManager.default.temporaryDirectory
                let wavURL = tempDir.appendingPathComponent("OneTake-mic-\(UUID().uuidString).wav")
                
                if let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 44100,
                    channels: 2,
                    interleaved: false
                ) {
                    let diskSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 44100.0,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    do {
                        let wavWriter = try AVAudioFile(
                            forWriting: wavURL,
                            settings: diskSettings,
                            commonFormat: targetFormat.commonFormat,
                            interleaved: targetFormat.isInterleaved
                        )
                        storage.micWavWriter = wavWriter
                        storage.micWavURL = wavURL
                    } catch {
                        // Ignore
                    }
                }
            } else {
                storage.micWavWriter = nil
                storage.micWavURL = nil
            }
            
            // Start microphone capture (if enabled)
            if capturesMic {
                startMicrophoneCapture()
            }
            
            // Start camera capture (if enabled)
            if renderConfig.enableCamera {
                cameraManager.start()
                storage.cameraPanel?.orderFront(nil)
            }
            
            assetWriter.startWriting()
            storage.sessionLock.lock()
            storage.sessionStarted = false
            storage.sessionLock.unlock()
            
        } catch {
            self.error = error
            return
        }
        
        // Exclude camera and teleprompter panels from the recording
        var excludedWindows: [SCWindow] = []
        do {
            let content = try await SCShareableContent.current
            if let cameraPanel = storage.cameraPanel, cameraPanel.windowNumber > 0 {
                let matching = content.windows.filter { $0.windowID == CGWindowID(cameraPanel.windowNumber) }
                excludedWindows.append(contentsOf: matching)
            }
            if let teleprompterPanel = storage.teleprompterPanel, teleprompterPanel.windowNumber > 0 {
                let matching = content.windows.filter { $0.windowID == CGWindowID(teleprompterPanel.windowNumber) }
                excludedWindows.append(contentsOf: matching)
            }
        } catch {
            // Ignore
        }
        
        // SCStream Configuration - use recording resolution
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: excludedWindows)
        
        let config = SCStreamConfiguration()
        let displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
        let recordingSize = renderConfig.recordingResolution.size(for: displaySize)
        config.width = Int(recordingSize.width)
        config.height = Int(recordingSize.height)
        config.showsCursor = true // Show native system cursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        
        // Enable Audio Capture based on audioMode
        let capturesSystemAudio = (renderConfig.audioMode == .screenOnly || renderConfig.audioMode == .both)
        config.capturesAudio = capturesSystemAudio
        if capturesSystemAudio {
            config.sampleRate = 44100
            config.channelCount = 2
        }
        
        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Add Video Output
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.onetake.recorder.video"))
            
            // Add Audio Output
            if capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.onetake.recorder.audio"))
            }
            
            try await stream.startCapture()
            self.stream = stream
            isRecording = true
            error = nil
            
            // Teleprompter 3-second auto-start delay
            if renderConfig.enableTeleprompter {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        if self.isRecording && self.renderConfig.enableTeleprompter {
                            self.renderConfig.isTeleprompterScrolling = true
                        }
                    }
                }
            }
        } catch {
            self.error = error
            isRecording = false
        }
    }
    
    func stopRecording() async {
        if renderConfig.enableTeleprompter {
            renderConfig.isTeleprompterScrolling = false
        }
        
        do {
            try await stream?.stopCapture()
            stream = nil
            isRecording = false
            
            // Stop microphone
            stopMicrophoneCapture()
            
            storage.videoInput?.markAsFinished()
            storage.audioInput?.markAsFinished()
            storage.micInput?.markAsFinished()
            
            let videoURL = storage.assetWriter?.outputURL
            let micWavURL = storage.micWavURL
            let enableSubtitles = renderConfig.enableAutoSubtitles
            let apiKey = renderConfig.sarvamAPIKey
            let subtitleStyle = renderConfig.subtitleStyle
            let subtitleFontSize = renderConfig.subtitleFontSize
            let subtitleTextColor = renderConfig.subtitleTextColor
            let subtitleBgOpacity = renderConfig.subtitleBgOpacity
            
            storage.micWavWriter = nil // Closes the file handle
            storage.micWavURL = nil
            
            await storage.assetWriter?.finishWriting()
            
            if enableSubtitles, let wavURL = micWavURL, !apiKey.isEmpty {
                isTranscribing = true
                transcriptionProgress = "Uploading voice audio..."
                
                Task {
                    do {
                        let response = try await SubtitleGenerator.transcribeAudio(fileURL: wavURL, apiKey: apiKey)
                        
                        await MainActor.run {
                            self.transcriptionProgress = "Writing subtitles..."
                        }
                        
                        var videoDuration: Double? = nil
                        if let vURL = videoURL {
                            let asset = AVAsset(url: vURL)
                            if let duration = try? await asset.load(.duration) {
                                videoDuration = duration.seconds
                            }
                        }
                        
                        let srtContent = SubtitleGenerator.generateSRT(from: response, style: subtitleStyle, duration: videoDuration)
                        let segments = SubtitleGenerator.generateSRTSegments(from: response, style: subtitleStyle, duration: videoDuration)
                        
                        if let vURL = videoURL {
                            let srtURL = vURL.deletingPathExtension().appendingPathExtension("srt")
                            try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
                            
                            if !segments.isEmpty {
                                await MainActor.run {
                                    self.transcriptionProgress = "Burning captions into video..."
                                }
                                _ = try await SubtitleGenerator.burnSubtitles(
                                    videoURL: vURL,
                                    segments: segments,
                                    style: subtitleStyle,
                                    fontSize: subtitleFontSize,
                                    textColor: subtitleTextColor,
                                    bgOpacity: subtitleBgOpacity
                                )
                            }
                        }
                        
                        try? FileManager.default.removeItem(at: wavURL)
                        
                        await MainActor.run {
                            self.isTranscribing = false
                            self.transcriptionProgress = nil
                            if let vURL = videoURL {
                                NSWorkspace.shared.activateFileViewerSelecting([vURL])
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.isTranscribing = false
                            self.transcriptionProgress = nil
                            self.error = error
                            try? FileManager.default.removeItem(at: wavURL)
                            if let vURL = videoURL {
                                NSWorkspace.shared.activateFileViewerSelecting([vURL])
                            }
                        }
                    }
                }
            } else {
                if let wavURL = micWavURL {
                    try? FileManager.default.removeItem(at: wavURL)
                }
                if let url = videoURL {
                   NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            
            storage.assetWriter = nil
            storage.videoInput = nil
            storage.audioInput = nil
            storage.micInput = nil
            storage.pixelBufferAdaptor = nil
            error = nil
        } catch {
            self.error = error
        }
    }
    
    func start() async { await startRecording() }
    func stop() async { await stopRecording() }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.isRecording = false
            self.error = error
        }
    }
}

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        
        // Audio Handling
        if type == .audio {
            // Safe access via storage class
            storage.sessionLock.lock()
            let isStarted = storage.sessionStarted
            storage.sessionLock.unlock()
            
            if let audioInput = storage.audioInput, 
               audioInput.isReadyForMoreMediaData,
               isStarted {  // Wait for session to start!
                if audioInput.append(sampleBuffer) {
                    // success
                }
            }
            return
        }
        
        // Video Handling
        guard type == .screen, sampleBuffer.imageBuffer != nil else { return }
        
        Task { @MainActor in
             self.processVideoFrame(sampleBuffer: sampleBuffer)
        }
    }
    
    // MainActor because it accesses `renderConfig`, `cursorManager`
    func processVideoFrame(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        guard let input = storage.videoInput, input.isReadyForMoreMediaData, let adaptor = storage.pixelBufferAdaptor else { return }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        storage.sessionLock.lock()
        if !storage.sessionStarted {
            storage.firstSampleTime = currentTime
            storage.assetWriter?.startSession(atSourceTime: storage.firstSampleTime)
            storage.sessionStarted = true // Set AFTER starting session
        }
        storage.sessionLock.unlock()
        
        // Sync Config
        compositor.config = renderConfig
        
        // Sync CursorManager config
        cursorManager.zoomIdleDelay = renderConfig.zoomIdleDelay
        
        let displayWidth = CVPixelBufferGetWidth(pixelBuffer)
        let displayHeight = CVPixelBufferGetHeight(pixelBuffer)
        let displayRect = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        
        let rawCursorPos = cursorManager.currentPosition
        let translatedCursorPos: CGPoint
        if let display = selectedDisplay {
            translatedCursorPos = translateCursorPosition(rawCursorPos, for: display, frameWidth: displayWidth, frameHeight: displayHeight)
        } else {
            translatedCursorPos = rawCursorPos
        }
        let focusTrigger = cursorManager.focusZoomTrigger
        
        let translatedTrigger: CursorManager.FocusZoomTrigger?
        if let trigger = focusTrigger, let display = selectedDisplay {
            let translatedPos = translateCursorPosition(trigger.position, for: display, frameWidth: displayWidth, frameHeight: displayHeight)
            translatedTrigger = CursorManager.FocusZoomTrigger(position: translatedPos, timestamp: trigger.timestamp, type: trigger.type)
        } else {
            translatedTrigger = nil
        }
        
        // Clear trigger after reading to prevent repeated triggers
        if focusTrigger != nil {
            cursorManager.clearFocusZoomTrigger()
        }
        
        // Get output size from storage
        guard let outputSize = storage.outputSize else { return }
        
        storage.cameraFrameLock.lock()
        let panelFrame = storage.cameraPanelFrame
        storage.cameraFrameLock.unlock()
        
        var cameraCenterPct: CGPoint? = nil
        if let panelFrame = panelFrame, let display = selectedDisplay {
            let bounds = CGDisplayBounds(display.displayID)
            if bounds.width > 0 && bounds.height > 0, let mainScreen = NSScreen.screens.first {
                let centerX = panelFrame.midX
                let centerY = mainScreen.frame.height - panelFrame.midY
                
                let relativeX = centerX - bounds.origin.x
                let relativeY = centerY - bounds.origin.y
                
                let pctX = relativeX / bounds.width
                let pctY = (bounds.height - relativeY) / bounds.height
                cameraCenterPct = CGPoint(x: pctX, y: pctY)
            }
        }
        
        if let composedBuffer = compositor.compose(
            screenFrame: pixelBuffer,
            cursorPosition: translatedCursorPos,
            displayFrame: displayRect,
            focusZoomTrigger: translatedTrigger,
            cameraFrame: cameraManager.latestFrame,
            cameraCenterPercent: cameraCenterPct,
            targetOutputSize: outputSize
        ) {
             let success = adaptor.append(composedBuffer, withPresentationTime: currentTime)
             if !success {
                 // print("Failed...")
             }
        }
    }
    
    private func translateCursorPosition(_ globalPoint: CGPoint, for display: SCDisplay, frameWidth: Int, frameHeight: Int) -> CGPoint {
        let bounds = CGDisplayBounds(display.displayID)
        guard bounds.width > 0 && bounds.height > 0 else { return .zero }
        
        let relativeX = globalPoint.x - bounds.origin.x
        let relativeY = globalPoint.y - bounds.origin.y
        
        let pixelX = relativeX * (CGFloat(frameWidth) / bounds.width)
        let pixelY = (bounds.height - relativeY) * (CGFloat(frameHeight) / bounds.height)
        
        return CGPoint(x: pixelX, y: pixelY)
    }
}
