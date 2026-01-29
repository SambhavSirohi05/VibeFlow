import Foundation
import AVFoundation
import CoreMedia

extension ScreenRecorder {
    // MARK: - Microphone Capture
    
    func startMicrophoneCapture() {
        // Request microphone permission first
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.setupMicrophoneEngine()
                }
            } else {
                print("DEBUG: Microphone permission denied")
            }
        }
    }
    
    private func setupMicrophoneEngine() {
        micAudioQueue = DispatchQueue(label: "com.vibeflow.mic")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Target format matching our video audio (44.1kHz, stereo, AAC)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        ) else {
            print("DEBUG: Failed to create target audio format")
            return
        }
        
        print("DEBUG: Starting microphone - Input: \(inputFormat.sampleRate)Hz, Target: 44100Hz")
        
        // Create converter if sample rates don't match
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self,
                  let micInput = self.storage.micInput,
                  micInput.isReadyForMoreMediaData,
                  let converter = converter,
                  self.storage.sessionStarted else { return }  // Wait for session to start!
            
            // Convert to target format
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (44100.0 / inputFormat.sampleRate))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { packetCount, status in
                status.pointee = .haveData
                return buffer
            }
            
            if error == nil, let sampleBuffer = self.createSampleBuffer(from: convertedBuffer) {
                micInput.append(sampleBuffer)
            }
        }
        
        do {
            try audioEngine.start()
            print("DEBUG: Microphone capture started successfully")
        } catch {
            print("DEBUG: Failed to start microphone: \(error)")
        }
    }
    
    func stopMicrophoneCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            audioEngine.reset()  // Reset the engine to allow restarting
            print("DEBUG: Microphone capture stopped and reset")
        }
    }
    
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let asbd = buffer.format.streamDescription
        var format: CMFormatDescription?
        
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let formatDesc = format else {
            return nil
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(buffer.format.sampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sample = sampleBuffer else {
            return nil
        }
        
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sample,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: buffer.audioBufferList
        ) == noErr else {
            return nil
        }
        
        return sample
    }
}
