import Foundation
import ScreenCaptureKit
import OSLog
import AppKit
import AVFoundation
import SwiftUI

@MainActor
class ScreenRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var availableDisplays: [SCDisplay] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var error: Error?
    @Published var renderConfig = RendererConfiguration()
    
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
    }
    nonisolated let storage = Storage()
    
    // Microphone audio engine
    let audioEngine = AVAudioEngine()
    var micAudioQueue: DispatchQueue?
    
    // Components
    private let cursorManager = CursorManager()
    private let compositor = VideoCompositor()
    
    override init() {
        super.init()
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
        print("DEBUG: startRecording() called")
        guard let display = selectedDisplay else {
            print("DEBUG: No display selected!")
            return
        }
        print("DEBUG: Selected display: \(display.width)x\(display.height)")
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("VibeFlow-\(Date().timeIntervalSince1970).mov")
        print("Recording to: \(fileURL.path)")
        print("DEBUG: File URL created: \(fileURL)")
        
        do {
            let assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
            storage.assetWriter = assetWriter
            
            // Use Recording Resolution from config
            let displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            let outputSize = renderConfig.recordingResolution.size(for: displaySize)
            storage.outputSize = outputSize  // Store for use in compositor
            
            print("Output Size: \(outputSize)")
            
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
            
            // Audio Input (System Audio)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            storage.audioInput = audioInput
            
            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            }
            
            // Microphone Input
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            micInput.expectsMediaDataInRealTime = true
            storage.micInput = micInput
            
            if assetWriter.canAdd(micInput) {
                assetWriter.add(micInput)
            }
            
            // Start microphone capture (if enabled)
            if renderConfig.enableMicrophone {
                startMicrophoneCapture()
            }
            
            assetWriter.startWriting()
            storage.sessionLock.lock()
            storage.sessionStarted = false
            storage.sessionLock.unlock()
            
        } catch {
            self.error = error
            return
        }
        
        // SCStream Configuration - use recording resolution
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        let displaySize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
        let recordingSize = renderConfig.recordingResolution.size(for: displaySize)
        config.width = Int(recordingSize.width)
        config.height = Int(recordingSize.height)
        config.showsCursor = true // Show native system cursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        
        // Enable Audio Capture
        config.capturesAudio = true
        config.sampleRate = 44100
        config.channelCount = 2
        
        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Add Video Output
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.vibeflow.recorder.video"))
            
            // Add Audio Output
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.vibeflow.recorder.audio"))
            
            try await stream.startCapture()
            self.stream = stream
            isRecording = true
            error = nil
        } catch {
            self.error = error
            isRecording = false
        }
    }
    
    func stopRecording() async {
        do {
            try await stream?.stopCapture()
            stream = nil
            isRecording = false
            
            // Stop microphone
            stopMicrophoneCapture()
            
            storage.videoInput?.markAsFinished()
            storage.audioInput?.markAsFinished()
            storage.micInput?.markAsFinished()
            await storage.assetWriter?.finishWriting()
            print("Finished writing to file")
            
            if let url = storage.assetWriter?.outputURL {
               NSWorkspace.shared.activateFileViewerSelecting([url])
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
        cursorManager.zoomTriggerMode = renderConfig.zoomTriggerMode
        cursorManager.triggerKey = renderConfig.triggerKey
        
        let cursorPos = cursorManager.currentPosition
        let focusTrigger = cursorManager.focusZoomTrigger
        
        // Clear trigger after reading to prevent repeated triggers
        if focusTrigger != nil {
            cursorManager.clearFocusZoomTrigger()
        }
        
        let displayWidth = CVPixelBufferGetWidth(pixelBuffer)
        let displayHeight = CVPixelBufferGetHeight(pixelBuffer)
        let displayRect = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        
        // Get output size from storage
        guard let outputSize = storage.outputSize else { return }
        
        if let composedBuffer = compositor.compose(
            screenFrame: pixelBuffer,
            cursorPosition: cursorPos,
            displayFrame: displayRect,
            focusZoomTrigger: focusTrigger,
            targetOutputSize: outputSize
        ) {
             let success = adaptor.append(composedBuffer, withPresentationTime: currentTime)
             if !success {
                 // print("Failed...")
             }
        }
    }
}
