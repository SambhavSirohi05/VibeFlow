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
        case zoomingIn(startTime: Date, targetTransform: CGAffineTransform, wideTransform: CGAffineTransform, triggerPosition: CGPoint)
        case holding(transform: CGAffineTransform, holdStartTime: Date, wideTransform: CGAffineTransform, triggerPosition: CGPoint)
        case zoomingOut(startTime: Date, fromTransform: CGAffineTransform, wideTransform: CGAffineTransform)
    }
    
    private var zoomState: ZoomState = .wide
    private var currentCameraScale: CGFloat = 1.0
    
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
        cameraFrame: CVPixelBuffer? = nil,
        cameraCenterPercent: CGPoint? = nil,
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
        
        // Use MIN to fit the screen inside the padded canvas (aspect-fit behavior)
        let baseScale = min(baseWidthRatio, baseHeightRatio)
        
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
        updateZoomState(currentCursorPos: cursorPosition, screenSize: screenImage.extent.size)
        
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
        
        // 11. Render camera presenter bubble
        if config.enableCamera, let camera = cameraFrame {
            let cameraImage = CIImage(cvPixelBuffer: camera)
            let cameraWidth = cameraImage.extent.width
            let cameraHeight = cameraImage.extent.height
            
            if cameraWidth > 0 && cameraHeight > 0 {
                let scaleFactor = displayFrame.width > 0 ? (contentWidth / displayFrame.width) : 1.0
                let baseCameraSize = config.cameraSize * scaleFactor
                
                let targetWidth: CGFloat
                let targetHeight: CGFloat
                let scaledImage: CIImage
                let radius: CGFloat
                
                switch config.cameraShape {
                case .circle:
                    targetWidth = baseCameraSize
                    targetHeight = baseCameraSize
                    radius = targetWidth / 2
                    
                    let cropSide = min(cameraWidth, cameraHeight)
                    let cropX = (cameraWidth - cropSide) / 2
                    let cropY = (cameraHeight - cropSide) / 2
                    let cropRect = CGRect(x: cropX, y: cropY, width: cropSide, height: cropSide)
                    
                    let croppedImage = cameraImage.cropped(to: cropRect)
                    let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
                    let scale = targetWidth / cropSide
                    scaledImage = translatedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    
                case .roundedRectangle:
                    targetWidth = baseCameraSize
                    targetHeight = baseCameraSize * (cameraHeight / cameraWidth)
                    radius = 16.0 * scaleFactor
                    
                    let scaleX = targetWidth / cameraWidth
                    let scaleY = targetHeight / cameraHeight
                    scaledImage = cameraImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                }
                
                // Create mask
                let maskExtent = CIVector(x: 0, y: 0, z: targetWidth, w: targetHeight)
                if let maskImage = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                    "inputExtent": maskExtent,
                    "inputRadius": radius,
                    "inputColor": CIColor.white
                ])?.outputImage {
                    
                    if let maskedCamera = CIFilter(name: "CISourceInCompositing", parameters: [
                        "inputImage": scaledImage,
                        "inputBackgroundImage": maskImage
                    ])?.outputImage {
                        
                        // Add border (optional)
                        let scaleFactor = displayFrame.width > 0 ? (contentWidth / displayFrame.width) : 1.0
                        let borderWidth = config.enableCameraBorder ? CGFloat(3.0) * scaleFactor : CGFloat(0.0)
                        let borderSize = CGSize(width: targetWidth + 2 * borderWidth, height: targetHeight + 2 * borderWidth)
                        let borderRadius = radius + borderWidth
                        
                        var borderedCamera: CIImage = maskedCamera
                        let borderExtent = CIVector(x: 0, y: 0, z: borderSize.width, w: borderSize.height)
                        if config.enableCameraBorder,
                           let borderImage = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                               "inputExtent": borderExtent,
                               "inputRadius": borderRadius,
                               "inputColor": CIColor.white
                           ])?.outputImage {
                            let translatedCamera = maskedCamera.transformed(by: CGAffineTransform(translationX: borderWidth, y: borderWidth))
                            borderedCamera = translatedCamera.composited(over: borderImage)
                        }
                        
                        // Calculate positioning
                        let bubbleX: CGFloat
                        let bubbleY: CGFloat
                        
                        if let centerPct = cameraCenterPercent {
                            let videoCenterX = contentRect.minX + centerPct.x * contentRect.width
                            let videoCenterY = contentRect.minY + centerPct.y * contentRect.height
                            
                            bubbleX = videoCenterX - borderSize.width / 2
                            bubbleY = videoCenterY - borderSize.height / 2
                        } else {
                            let marginX = max(20.0, config.padding)
                            let marginY = max(20.0, config.padding)
                            
                            switch config.cameraPosition {
                            case .topLeft:
                                bubbleX = marginX
                                bubbleY = canvasSize.height - marginY - borderSize.height
                            case .topRight:
                                bubbleX = canvasSize.width - marginX - borderSize.width
                                bubbleY = canvasSize.height - marginY - borderSize.height
                            case .bottomLeft:
                                bubbleX = marginX
                                bubbleY = marginY
                            case .bottomRight:
                                bubbleX = canvasSize.width - marginX - borderSize.width
                                bubbleY = marginY
                            }
                        }
                        
                        // Generate shadow
                        let shadowExtent = CIVector(x: 0, y: 0, z: borderSize.width, w: borderSize.height)
                        if let shadowBase = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                            "inputExtent": shadowExtent,
                            "inputRadius": borderRadius,
                            "inputColor": CIColor.black
                        ])?.outputImage {
                            
                            let scaleFactor = displayFrame.width > 0 ? (contentWidth / displayFrame.width) : 1.0
                            if let shadowImage = CIFilter(name: "CIGaussianBlur", parameters: [
                                "inputImage": shadowBase,
                                "inputRadius": CGFloat(10.0) * scaleFactor
                            ])?.outputImage {
                                
                                let shadowOffset = CGAffineTransform(translationX: 0, y: -4)
                                let offsetShadow = shadowImage.transformed(by: shadowOffset)
                                
                                let cameraBubbleWithShadow = borderedCamera.composited(over: offsetShadow)
                                
                                // Cursor Hover Scaling detection
                                let bubbleRect = CGRect(x: bubbleX, y: bubbleY, width: borderSize.width, height: borderSize.height)
                                let isCursorOverCamera = bubbleRect.contains(cursorPosition)
                                let targetScale: CGFloat = isCursorOverCamera ? 1.3 : 1.0
                                
                                // Smooth spring-like ease towards target scale
                                currentCameraScale += (targetScale - currentCameraScale) * 0.15
                                
                                let localCenterX = borderSize.width / 2
                                let localCenterY = borderSize.height / 2
                                let scaleTransform = CGAffineTransform(translationX: localCenterX, y: localCenterY)
                                    .scaledBy(x: currentCameraScale, y: currentCameraScale)
                                    .translatedBy(x: -localCenterX, y: -localCenterY)
                                let scaledBubble = cameraBubbleWithShadow.transformed(by: scaleTransform)
                                
                                let positionedBubble = scaledBubble.transformed(by: CGAffineTransform(translationX: bubbleX, y: bubbleY))
                                composited = positionedBubble.composited(over: composited)
                            }
                        }
                    }
                }
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
        
        // Calculate focus rect dynamically based on zoomStrength (e.g. 1.5x zoom means viewport is screenSize / 1.5)
        let focusWidth = screenSize.width / config.zoomStrength
        let focusHeight = screenSize.height / config.zoomStrength
        
        var focusX = localX - focusWidth / 2
        var focusY = localY - focusHeight / 2
        
        // Clamp to screen bounds
        focusX = max(0, min(focusX, screenSize.width - focusWidth))
        focusY = max(0, min(focusY, screenSize.height - focusHeight))
        
        let focusRect = CGRect(x: focusX, y: focusY, width: focusWidth, height: focusHeight)
        
        // COMMIT: Calculate target transform ONCE and freeze it
        let targetTransform = calculateFocusTransform(focusRect: focusRect, baseScale: baseScale, contentRect: contentRect, screenSize: screenSize)
        
        // Start zoom in with FROZEN transform
        zoomState = .zoomingIn(startTime: Date(), targetTransform: targetTransform, wideTransform: wideTransform, triggerPosition: trigger.position)
    }
    
    private func updateZoomState(currentCursorPos: CGPoint, screenSize: CGSize) {
        let now = Date()
        
        switch zoomState {
        case .wide:
            break
            
        case .zoomingIn(let startTime, let targetTransform, let wideTransform, let triggerPosition):
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= zoomInDuration {
                zoomState = .holding(transform: targetTransform, holdStartTime: now, wideTransform: wideTransform, triggerPosition: triggerPosition)
            }
            
        case .holding(let transform, let holdStartTime, let wideTransform, let triggerPosition):
            let elapsed = now.timeIntervalSince(holdStartTime)
            
            // Check if cursor has moved far from the initial trigger position
            let distance = hypot(currentCursorPos.x - triggerPosition.x, currentCursorPos.y - triggerPosition.y)
            let threshold = screenSize.width * 0.25 // Let user move cursor within 25% of screen width before zooming out
            let movedAway = distance > threshold
            
            // Stay zoomed in if cursor is close. If cursor moves away, zoom out after minimum hold of 1.0 second.
            if elapsed >= 1.0 && movedAway {
                zoomState = .zoomingOut(startTime: now, fromTransform: transform, wideTransform: wideTransform)
            }
            
        case .zoomingOut(let startTime, _, _):
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= zoomOutDuration {
                zoomState = .wide
            }
        }
    }
    
    private func getFrozenCameraTransform(wideTransform: CGAffineTransform) -> CGAffineTransform {
        let now = Date()
        
        switch zoomState {
        case .wide:
            return wideTransform
            
        case .zoomingIn(let startTime, let targetTransform, let wideTransform, _):
            // Interpolate from wide to target
            let elapsed = now.timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / zoomInDuration)
            let easedProgress = easeInOut(progress)
            return interpolate(from: wideTransform, to: targetTransform, progress: easedProgress)
            
        case .holding(let transform, _, _, _):
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
        // Calculate scale to fit focus rect into content rect using raw screen dimensions to prevent base-scale pollution
        let scaleX = screenSize.width / focusRect.width
        let scaleY = screenSize.height / focusRect.height
        let focusScale = min(scaleX, scaleY, config.zoomStrength)  // Cap at config zoom strength
        
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
    
    func resetZoomState() {
        zoomState = .wide
    }
}

// Helper for Color -> CIColor
extension CIColor {
    convenience init?(color: Color) {
        let uiColor = NSColor(color)
        self.init(cgColor: uiColor.cgColor)
    }
}
