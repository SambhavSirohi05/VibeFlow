import SwiftUI
import AppKit
import Combine

// MARK: - Premium Click-Through Views for Background Interaction

/// A custom NSHostingView that overrides acceptsFirstMouse to allow controls (buttons, sliders)
/// to receive click and drag events immediately on the first click, even when OneTake is inactive.
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// A custom NSTextView that accepts the first mouse click to focus and edit without an activating click.
class ClickThroughTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - Native macOS Glassmorphism (Visual Effect View)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Teleprompter Custom Text View (NSViewRepresentable)

struct TeleprompterTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    @Binding var isScrolling: Bool
    let scrollSpeed: Double
    @Binding var resetOffset: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        
        let textView = ClickThroughTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.textColor = .white
        textView.insertionPointColor = .white
        
        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        
        // Listen to manual scroll bounds changes to keep scrollOffset in sync
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        // Initial setup
        textView.string = text
        context.coordinator.updateFont(size: fontSize)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = context.coordinator.textView {
            if textView.string != text {
                // Prevent cursor resetting to the end during active editing
                if !(textView.window?.firstResponder == textView) {
                    textView.string = text
                }
            }
            textView.isEditable = !isScrolling
        }
        
        context.coordinator.updateFont(size: fontSize)
        context.coordinator.updateScrollingState(isScrolling: isScrolling, speed: scrollSpeed)
        
        if resetOffset {
            context.coordinator.resetScroll()
            DispatchQueue.main.async {
                self.resetOffset = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TeleprompterTextView
        var scrollView: NSScrollView?
        var textView: NSTextView?
        var timer: Timer?
        var scrollOffset: CGFloat = 0
        var currentSpeed: Double = 0
        
        init(_ parent: TeleprompterTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            let string = textView.string
            DispatchQueue.main.async {
                self.parent.text = string
            }
        }
        
        @objc func boundsDidChange(_ notification: Notification) {
            // Keep scrollOffset synchronized with manual user scrolling (trackpad/scroll bar)
            if let contentView = scrollView?.contentView {
                scrollOffset = contentView.bounds.origin.y
            }
        }
        
        func updateFont(size: CGFloat) {
            let font = NSFont.systemFont(ofSize: size, weight: .medium)
            if textView?.font != font {
                textView?.font = font
            }
        }
        
        func updateScrollingState(isScrolling: Bool, speed: Double) {
            if isScrolling {
                if timer == nil || currentSpeed != speed {
                    startTimer(speed: speed)
                }
            } else {
                stopTimer()
            }
        }
        
        func startTimer(speed: Double) {
            stopTimer()
            currentSpeed = speed
            
            let interval = 0.02 // 50 FPS
            let delta = CGFloat(speed * interval)
            
            // Sync with current scroll view offset
            if let contentView = scrollView?.contentView {
                scrollOffset = contentView.bounds.origin.y
            }
            
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self = self, let scrollView = self.scrollView, let documentView = scrollView.documentView else { return }
                
                let contentView = scrollView.contentView
                let maxScrollY = documentView.frame.height - contentView.bounds.height
                
                if self.scrollOffset < maxScrollY {
                    self.scrollOffset += delta
                    contentView.setBoundsOrigin(NSPoint(x: 0, y: self.scrollOffset))
                    scrollView.reflectScrolledClipView(contentView)
                } else {
                    self.stopTimer()
                    DispatchQueue.main.async {
                        self.parent.isScrolling = false
                    }
                }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        
        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }
        
        func resetScroll() {
            stopTimer()
            scrollOffset = 0
            let contentView = scrollView?.contentView
            contentView?.setBoundsOrigin(NSPoint(x: 0, y: 0))
            if let scrollView = scrollView, let contentView = contentView {
                scrollView.reflectScrolledClipView(contentView)
            }
        }
        
        deinit {
            stopTimer()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - SwiftUI HUD Bubble View

struct TeleprompterBubbleView: View {
    @Binding var config: RendererConfiguration
    @Binding var resetOffset: Bool
    weak var panel: NSPanel?
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Eye Contact Guide
            HStack {
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                Text("LOOK HERE (CAMERA DIRECTLY ABOVE)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
                    .tracking(1)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.12))
            
            // Text Area
            TeleprompterTextView(
                text: $config.teleprompterText,
                fontSize: config.teleprompterFontSize,
                isScrolling: $config.isTeleprompterScrolling,
                scrollSpeed: config.teleprompterScrollSpeed,
                resetOffset: $resetOffset
            )
            .padding(10)
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            // Premium Bottom Toolbar
            HStack(spacing: 12) {
                // Play / Pause Button
                Button(action: {
                    config.isTeleprompterScrolling.toggle()
                }) {
                    Image(systemName: config.isTeleprompterScrolling ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(config.isTeleprompterScrolling ? Color.orange : Color.green))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(config.isTeleprompterScrolling ? "Pause Auto-Scroll" : "Play Auto-Scroll")
                
                // Font Size Control
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Slider(value: $config.teleprompterFontSize, in: 16...48, step: 2)
                        .frame(width: 60)
                    
                    Text("\(Int(config.teleprompterFontSize))pt")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                
                // Speed Control
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Slider(value: $config.teleprompterScrollSpeed, in: 10...120, step: 5)
                        .frame(width: 60)
                    
                    Text("\(Int(config.teleprompterScrollSpeed))px")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                
                Spacer()
                
                // Reset Button
                Button(action: {
                    resetOffset = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Reset to Top")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(config.teleprompterOpacity)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Teleprompter Panel NSPanel Implementation

class TeleprompterPanel: NSPanel {
    private var cancellables = Set<AnyCancellable>()
    
    init(config: Binding<RendererConfiguration>, resetOffset: Binding<Bool>, onClose: @escaping () -> Void) {
        let initialRect = NSRect(x: 350, y: 500, width: 440, height: 280)
        
        super.init(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.title = "OneTake Script Teleprompter"
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .statusBar
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        
        // Use our custom ClickThroughHostingView to bypass First Mouse activation delays
        let hostingView = ClickThroughHostingView(
            rootView: TeleprompterBubbleView(config: config, resetOffset: resetOffset, panel: self, onClose: onClose)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.contentView = hostingView
        
        // Listen for willCloseNotification to synchronize settings
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: self)
            .sink { _ in
                onClose()
            }
            .store(in: &cancellables)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}
