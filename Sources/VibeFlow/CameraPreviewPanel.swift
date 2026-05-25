import SwiftUI
import AppKit
import AVFoundation

// 1. NSViewRepresentable for live camera preview
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Mirror the webcam preview for natural user experience
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        
        view.layer?.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.frame = nsView.bounds
        context.coordinator.previewLayer?.frame = nsView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// 2. SwiftUI View for the floating bubble
struct CameraPreviewBubbleView: View {
    let session: AVCaptureSession
    let shape: CameraShape
    let size: CGFloat
    let hasBorder: Bool
    weak var panel: NSPanel?
    
    // Position callback to update the panel coordinates thread-safely
    let onMove: (CGRect) -> Void
    
    @State private var isHovered = false
    @State private var initialWindowOrigin: CGPoint = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The actual camera preview bubble
                CameraPreviewView(session: session)
                    .frame(width: targetWidth, height: targetHeight)
                    .clipShape(clipShape)
                    // Border if enabled
                    .overlay(
                        clipShape.stroke(Color.white, lineWidth: hasBorder ? 3 : 0)
                    )
                    // Drop Shadow
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
                    // Interactive scaling
                    .scaleEffect(isHovered ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                    .onHover { hovering in
                        isHovered = hovering
                    }
                    // Draggable gesture
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if value.translation == .zero {
                                    // Store initial position of the window when the drag starts
                                    if let currentWindow = panel {
                                        initialWindowOrigin = currentWindow.frame.origin
                                    }
                                }
                                
                                // Drag the window smoothly
                                if let window = panel {
                                    let newX = initialWindowOrigin.x + value.translation.width
                                    let newY = initialWindowOrigin.y - value.translation.height // Y is inverted in macOS screen space
                                    window.setFrameOrigin(CGPoint(x: newX, y: newY))
                                    onMove(window.frame)
                                }
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var targetWidth: CGFloat {
        size
    }
    
    private var targetHeight: CGFloat {
        switch shape {
        case .circle:
            return size
        case .roundedRectangle:
            // Use standard 4:3 ratio for rectangular camera in preview
            return size * 0.75
        }
    }
    
    private var clipShape: AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// SwiftUI AnyShape wrapper to allow dynamic shape switching
struct AnyShape: Shape {
    private let path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        self.path = { @Sendable rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        path(rect)
    }
}

// 3. Custom NSPanel subclass for floating, borderless panel
class CameraPreviewPanel: NSPanel {
    init(session: AVCaptureSession, shape: CameraShape, size: CGFloat, hasBorder: Bool, onMove: @escaping (CGRect) -> Void) {
        // Enlarge window size slightly so scaled-up hover bubble isn't clipped
        let windowSize = size * 1.6
        let initialRect = NSRect(x: 100, y: 100, width: windowSize, height: windowSize)
        
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar // Float above all normal windows
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        
        let contentView = NSHostingView(
            rootView: CameraPreviewBubbleView(
                session: session,
                shape: shape,
                size: size,
                hasBorder: hasBorder,
                panel: self,
                onMove: onMove
            )
        )
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
        
        self.contentView = contentView
    }
    
    // Ensure we can click/drag this borderless panel
    override var canBecomeKey: Bool {
        return true
    }
}
