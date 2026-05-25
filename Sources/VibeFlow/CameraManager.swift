import AVFoundation
import CoreMedia

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.vibeflow.camera", qos: .userInteractive)
    
    private let lock = NSLock()
    private(set) var latestFrame: CVPixelBuffer?
    
    private var activeInput: AVCaptureDeviceInput?
    
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self, granted else { return }
            self.queue.async {
                self.setupSession()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.lock.lock()
            self.latestFrame = nil
            self.lock.unlock()
        }
    }
    
    private func setupSession() {
        guard session.inputs.isEmpty else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Discover default camera
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
            
        guard let camera = device else {
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                self.activeInput = input
            }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
        } catch {
            // Error setting up camera input/output
        }
        
        session.commitConfiguration()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        lock.lock()
        self.latestFrame = pixelBuffer
        lock.unlock()
    }
}
