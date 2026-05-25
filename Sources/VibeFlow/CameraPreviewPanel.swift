import SwiftUI
import AppKit
import AVFoundation

// 1. NSViewRepresentable for live camera preview
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Mirror the webcam preview for natural user experience
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        
        view.previewLayer = previewLayer
        return view
    }
    
    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        // Handled by PreviewNSView's layout()
    }
}

class PreviewNSView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = previewLayer {
                self.layer?.addSublayer(layer)
                layer.frame = self.bounds
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        previewLayer?.frame = self.bounds
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
    @State private var dragStartLocation: CGPoint? = nil
    @State private var mouseStartLocation: CGPoint = .zero
    
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
                    // Draggable gesture using global screen mouse coordinates for maximum drag fluidity
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let currentMouse = NSEvent.mouseLocation
                                if dragStartLocation == nil {
                                    if let currentWindow = panel {
                                        dragStartLocation = currentWindow.frame.origin
                                        mouseStartLocation = currentMouse
                                    }
                                }
                                
                                if let startOrigin = dragStartLocation, let window = panel {
                                    let dx = currentMouse.x - mouseStartLocation.x
                                    let dy = currentMouse.y - mouseStartLocation.y
                                    window.setFrameOrigin(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
                                    onMove(window.frame)
                                }
                            }
                            .onEnded { _ in
                                dragStartLocation = nil
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
