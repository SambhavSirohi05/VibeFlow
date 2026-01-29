import Foundation
import CoreImage
import CoreVideo
import SwiftUI
import AppKit

class VideoCompositor {
    private let context = CIContext()
    
    // Configuration
    var config: RendererConfiguration = RendererConfiguration()
    
    // Focus zoom state - CAMERA COMMITMENT MODEL
    private enum ZoomState {
        case wide
        case zoomingIn(startTime: Date, targetTransform: CGAffineTransform, wideTransform: CGAffineTransform)
        case holding(transform: CGAffineTransform, holdStartTime: Date, wideTransform: CGAffineTransform)
        case zoomingOut(startTime: Date, fromTransform: CGAffineTransform, wideTransform: CGAffineTransform)
    }
    
    private var zoomState: ZoomState = .wide
    
    // Timing constants
    private let zoomInDuration: TimeInterval = 0.3  // 300ms
    private let holdDuration: TimeInterval = 2.0    // 2 seconds
    private let zoomOutDuration: TimeInterval = 0.6  // 600ms
    private let maxZoomScale: CGFloat = 1.25
    
    func compose(
        screenFrame: CVPixelBuffer,
        cursorPosition: CGPoint,
        displayFrame: CGRect,
        focusZoomTrigger: CursorManager.FocusZoomTrigger?,
        targetOutputSize: CGSize
    ) -> CVPixelBuffer? {
        
        let screenImage = CIImage(cvPixelBuffer: screenFrame)
        
        // 1. Canvas size is FIXED
        let canvasSize = targetOutputSize
        
        // 2. Create STATIC background
        var backgroundImage: CIImage?
        
        switch config.background {
        case .solid(let color):
            if let ciColor = CIColor(color: color) {
                backgroundImage = CIImage(color: ciColor).cropped(to: CGRect(origin: .zero, size: canvasSize))
            }
        case .gradient(let colors):
            if colors.count >= 2,
               let color1 = CIColor(color: colors[0]),
               let color2 = CIColor(color: colors[1]) {
                
                let gradient = CIFilter(name: "CILinearGradient", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: canvasSize.width, y: canvasSize.height),
                    "inputColor0": color1,
                    "inputColor1": color2
                ])?.outputImage
                
                backgroundImage = gradient?.cropped(to: CGRect(origin: .zero, size: canvasSize))
            }
        case .image(let url):
            if let nsImage = NSImage(contentsOf: url),
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ciImage = CIImage(cgImage: cgImage)
                
                // Scale and crop to fill canvas
                let scaleX = canvasSize.width / ciImage.extent.width
                let scaleY = canvasSize.height / ciImage.extent.height
                let scale = max(scaleX, scaleY)
                
                let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                
                // Center crop
                let cropX = (scaledImage.extent.width - canvasSize.width) / 2
                let cropY = (scaledImage.extent.height - canvasSize.height) / 2
                let cropRect = CGRect(x: cropX, y: cropY, width: canvasSize.width, height: canvasSize.height)
                
                backgroundImage = scaledImage.cropped(to: cropRect)
                    .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
            }
        }
        
        if backgroundImage == nil {
            backgroundImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvasSize))
        }
        
        // 3. Calculate base content placement (no zoom)
        let paddedWidth = max(1, canvasSize.width - (config.padding * 2))
        let paddedHeight = max(1, canvasSize.height - (config.padding * 2))
        
        let baseWidthRatio = paddedWidth / screenImage.extent.width
        let baseHeightRatio = paddedHeight / screenImage.extent.height
        
        // Use MAX to fill the space (aspect-fill behavior, no letterboxing)
        let baseScale = max(baseWidthRatio, baseHeightRatio)
        
        let contentWidth = screenImage.extent.width * baseScale
        let contentHeight = screenImage.extent.height * baseScale
        let contentX = (canvasSize.width - contentWidth) / 2
        let contentY = (canvasSize.height - contentHeight) / 2
        let contentRect = CGRect(x: contentX, y: contentY, width: contentWidth, height: contentHeight)
        
        let wideTransform = CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY)
            .scaledBy(x: baseScale, y: baseScale)
        
        // 4. Handle focus zoom triggers - COMMIT to transform ONCE
        if config.enableCursorZoom, let trigger = focusZoomTrigger {
            handleFocusZoomTrigger(trigger, screenSize: screenImage.extent.size, displayFrame: displayFrame, baseScale: baseScale, contentRect: contentRect, wideTransform: wideTransform)
        }
        
        // 5. Update zoom state machine
        updateZoomState()
        
        // 6. Get FROZEN camera transform (no recalculation)
        let cameraTransform = getFrozenCameraTransform(wideTransform: wideTransform)
        
        // 7. Apply rounded corners (in source space)
        var styledScreen = screenImage
        if config.cornerRadius > 0 {
            let sourceRadius = config.cornerRadius / baseScale
            
            let roundedMask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(x: 0, y: 0, z: screenImage.extent.width, w: screenImage.extent.height),
                "inputRadius": sourceRadius,
                "inputColor": CIColor.white
            ])?.outputImage
            
            if let mask = roundedMask {
                styledScreen = CIFilter(name: "CISourceInCompositing", parameters: [
                    "inputImage": screenImage,
                    "inputBackgroundImage": mask
                ])?.outputImage ?? screenImage
            }
        }
        
        // 8. Create shadow (in source space)
        var shadowImage: CIImage?
        if config.shadowRadius > 0 {
            let sourceRadius = (config.cornerRadius > 0 ? config.cornerRadius : 0) / baseScale
            
            let shadowGenerator = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(x: 0, y: 0, z: screenImage.extent.width, w: screenImage.extent.height),
                "inputRadius": sourceRadius,
                "inputColor": CIColor.black
            ])?.outputImage
            
            if let shadowBase = shadowGenerator {
                shadowImage = CIFilter(name: "CIGaussianBlur", parameters: [
                    "inputImage": shadowBase,
                    "inputRadius": config.shadowRadius / baseScale
                ])?.outputImage
            }
        }
        
        // 9. Apply FROZEN camera transform
        let transformedContent = styledScreen.transformed(by: cameraTransform)
        let transformedShadow = shadowImage?.transformed(by: cameraTransform)
        
        // 10. Composite layers
        var composited = backgroundImage!
        
        if let shadow = transformedShadow {
            let shadowOffset = CGAffineTransform(translationX: 0, y: -5)
            let offsetShadow = shadow.transformed(by: shadowOffset)
            composited = offsetShadow.composited(over: composited)
        }
        
        composited = transformedContent.composited(over: composited)
        
        // 11. Cursor overlay (optional, in screen space - NOT zoomed)
        if config.showCursorHighlight {
            let baseTransform = CGAffineTransform(translationX: contentX, y: contentY)
                .scaledBy(x: baseScale, y: baseScale)
            
            let displayLocalX = cursorPosition.x - displayFrame.minX
            let displayLocalY = displayFrame.height - (cursorPosition.y - displayFrame.minY)
            let cursorPoint = CGPoint(x: displayLocalX, y: displayLocalY).applying(baseTransform)
            
            let cursorHalo = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: cursorPoint.x, y: cursorPoint.y),
                "inputRadius0": 0,
                "inputRadius1": 20.0,
                "inputColor0": CIColor(red: 1, green: 1, blue: 0, alpha: 0.6),
                "inputColor1": CIColor(red: 1, green: 1, blue: 0, alpha: 0.0)
            ])?.outputImage?.cropped(to: composited.extent)
            
            if let halo = cursorHalo {
                composited = halo.composited(over: composited)
            }
        }
        
        return renderToBuffer(composited, size: canvasSize)
    }
    
    private func handleFocusZoomTrigger(_ trigger: CursorManager.FocusZoomTrigger, screenSize: CGSize, displayFrame: CGRect, baseScale: CGFloat, contentRect: CGRect, wideTransform: CGAffineTransform) {
        // CRITICAL: Only trigger if we're in wide state
        // This prevents re-triggering and camera drift during active zoom
        guard case .wide = zoomState else { 
            // Already zooming/holding/zooming out - ignore new triggers
            return 
        }
        
        // Convert cursor position to screen-local coordinates
        let localX = trigger.position.x - displayFrame.minX
        let localY = trigger.position.y - displayFrame.minY
        
        // Calculate focus rect (35-45% of screen width)
        let focusWidth = screenSize.width * 0.4
        let focusHeight = screenSize.height * 0.4
        
        var focusX = localX - focusWidth / 2
        var focusY = localY - focusHeight / 2
        
        // Clamp to screen bounds
        focusX = max(0, min(focusX, screenSize.width - focusWidth))
        focusY = max(0, min(focusY, screenSize.height - focusHeight))
        
        let focusRect = CGRect(x: focusX, y: focusY, width: focusWidth, height: focusHeight)
        
        // COMMIT: Calculate target transform ONCE and freeze it
        let targetTransform = calculateFocusTransform(focusRect: focusRect, baseScale: baseScale, contentRect: contentRect, screenSize: screenSize)
        
        print("ZOOM COMMIT: Locking camera at focus rect: \(focusRect)")
        
        // Start zoom in with FROZEN transform
        zoomState = .zoomingIn(startTime: Date(), targetTransform: targetTransform, wideTransform: wideTransform)
    }
    
    private func updateZoomState() {
        let now = Date()
        
        switch zoomState {
        case .wide:
            break
            
        case .zoomingIn(let startTime, let targetTransform, let wideTransform):
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= zoomInDuration {
                // Transition to holding with FROZEN transform
                print("ZOOM: Entering HOLD state - camera LOCKED")
                zoomState = .holding(transform: targetTransform, holdStartTime: now, wideTransform: wideTransform)
            }
            
        case .holding(let transform, let holdStartTime, let wideTransform):
            let elapsed = now.timeIntervalSince(holdStartTime)
            if elapsed >= holdDuration {
                // Transition to zooming out with FROZEN transform
                print("ZOOM: Starting zoom out")
                zoomState = .zoomingOut(startTime: now, fromTransform: transform, wideTransform: wideTransform)
            }
            
        case .zoomingOut(let startTime, _, _):
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= zoomOutDuration {
                // Return to wide
                print("ZOOM: Returned to WIDE - ready for new trigger")
                zoomState = .wide
            }
        }
    }
    
    private func getFrozenCameraTransform(wideTransform: CGAffineTransform) -> CGAffineTransform {
        let now = Date()
        
        switch zoomState {
        case .wide:
            return wideTransform
            
        case .zoomingIn(let startTime, let targetTransform, let wideTransform):
            // Interpolate from wide to target
            let elapsed = now.timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / zoomInDuration)
            let easedProgress = easeInOut(progress)
            return interpolate(from: wideTransform, to: targetTransform, progress: easedProgress)
            
        case .holding(let transform, _, _):
            // LOCKED - return frozen transform
            return transform
            
        case .zoomingOut(let startTime, let fromTransform, let wideTransform):
            // Interpolate from frozen transform back to wide
            let elapsed = now.timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / zoomOutDuration)
            let easedProgress = easeInOut(progress)
            return interpolate(from: fromTransform, to: wideTransform, progress: easedProgress)
        }
    }
    
    private func calculateFocusTransform(focusRect: CGRect, baseScale: CGFloat, contentRect: CGRect, screenSize: CGSize) -> CGAffineTransform {
        // Calculate scale to fit focus rect into content rect
        let scaleX = contentRect.width / focusRect.width
        let scaleY = contentRect.height / focusRect.height
        let focusScale = min(scaleX, scaleY, maxZoomScale)  // Cap at max zoom
        
        let finalScale = baseScale * focusScale
        
        // Calculate translation to center focus rect
        let focusCenterX = focusRect.midX * baseScale * focusScale
        let focusCenterY = focusRect.midY * baseScale * focusScale
        
        let translateX = contentRect.midX - focusCenterX
        let translateY = contentRect.midY - focusCenterY
        
        return CGAffineTransform(translationX: translateX, y: translateY)
            .scaledBy(x: finalScale, y: finalScale)
    }
    
    private func interpolateTransform(from: CGRect?, to: CGRect?, progress: CGFloat, baseScale: CGFloat, contentRect: CGRect, screenSize: CGSize) -> CGAffineTransform {
        let wideTransform = CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY).scaledBy(x: baseScale, y: baseScale)
        
        if let fromRect = from, to == nil {
            // Zooming out to wide
            let fromTransform = calculateFocusTransform(focusRect: fromRect, baseScale: baseScale, contentRect: contentRect, screenSize: screenSize)
            return interpolate(from: fromTransform, to: wideTransform, progress: progress)
        } else if from == nil, let toRect = to {
            // Zooming in from wide
            let toTransform = calculateFocusTransform(focusRect: toRect, baseScale: baseScale, contentRect: contentRect, screenSize: screenSize)
            return interpolate(from: wideTransform, to: toTransform, progress: progress)
        }
        
        // Fallback
        return wideTransform
    }
    
    private func interpolate(from: CGAffineTransform, to: CGAffineTransform, progress: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(
            a: from.a + (to.a - from.a) * progress,
            b: from.b + (to.b - from.b) * progress,
            c: from.c + (to.c - from.c) * progress,
            d: from.d + (to.d - from.d) * progress,
            tx: from.tx + (to.tx - from.tx) * progress,
            ty: from.ty + (to.ty - from.ty) * progress
        )
    }
    
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }
    
    private func renderToBuffer(_ image: CIImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        
        if let buffer = pixelBuffer {
            context.render(image, to: buffer)
            return buffer
        }
        return nil
    }
}

// Helper for Color -> CIColor
extension CIColor {
    convenience init?(color: Color) {
        let uiColor = NSColor(color)
        self.init(cgColor: uiColor.cgColor)
    }
}
