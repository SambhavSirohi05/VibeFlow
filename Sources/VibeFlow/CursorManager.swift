import Foundation
import AppKit
import Combine

class CursorManager: ObservableObject {
    @Published var currentPosition: CGPoint = .zero
    @Published var isClicking: Bool = false
    
    // Focus zoom state
    @Published var focusZoomTrigger: FocusZoomTrigger?
    
    // Config
    var zoomTriggerMode: ZoomTriggerMode = .auto
    var triggerKey: Int = 6
    
    private var timer: Timer?
    private var lastPosition: CGPoint = .zero
    private var isKeyPressed: Bool = false
    private var dwellTimer: Timer?
    private var dwellDelay: TimeInterval = 0.7  // 700ms for dwell trigger
    private var dwellRadius: CGFloat = 20.0  // Small radius for dwell detection
    private var dwellStartPosition: CGPoint = .zero
    
    struct FocusZoomTrigger {
        let position: CGPoint
        let timestamp: Date
        let type: TriggerType
        
        enum TriggerType {
            case click
            case dwell
            case key
        }
    }
    
    init() {
        startTracking()
    }
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    // ... init ...
    
    func startTracking() {
        // Position Tracking
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateCursor()
        }
        
        // Key Tracking (Global)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Key Tracking (Local - when app is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        dwellTimer?.invalidate()
        dwellTimer = nil
        
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard zoomTriggerMode == .manual else { return }
        
        // Check if event matches trigger key
        if Int(event.keyCode) == triggerKey {
            if event.type == .keyDown {
                if !isKeyPressed {
                    isKeyPressed = true
                    // Trigger zoom immediately on key down
                    DispatchQueue.main.async {
                        self.triggerFocusZoom(at: self.currentPosition, type: .key)
                    }
                }
            } else if event.type == .keyUp {
                isKeyPressed = false
            }
        }
    }
    
    private func updateCursor() {
        guard let event = CGEvent(source: nil) else { return }
        let location = event.location
        
        DispatchQueue.main.async {
            self.currentPosition = location
            
            if self.zoomTriggerMode == .manual {
                // Manual Key Logic handled by event monitors
                // Just clear dwell timer here
                self.dwellTimer?.invalidate()
                self.dwellTimer = nil
                
            } else {
                // Auto (Click/Dwell) Logic
                let leftMouseDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(0x00))
                
                if leftMouseDown && !self.isClicking {
                    // Click started - trigger focus zoom
                    self.isClicking = true
                    self.triggerFocusZoom(at: location, type: .click)
                } else if !leftMouseDown && self.isClicking {
                    self.isClicking = false
                }
                
                // Detect dwell (cursor staying in small radius)
                let distance = hypot(location.x - self.lastPosition.x, location.y - self.lastPosition.y)
                
                if distance > 1.0 {
                    // Cursor moved significantly
                    self.lastPosition = location
                    self.resetDwellTimer(at: location)
                }
            }
        }
    }
    
    private func resetDwellTimer(at position: CGPoint) {
        dwellTimer?.invalidate()
        dwellStartPosition = position
        
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwellDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Check if cursor is still within dwell radius
                let currentDist = hypot(self.currentPosition.x - self.dwellStartPosition.x,
                                       self.currentPosition.y - self.dwellStartPosition.y)
                
                if currentDist <= self.dwellRadius {
                    // Trigger focus zoom on dwell
                    self.triggerFocusZoom(at: self.currentPosition, type: .dwell)
                }
            }
        }
    }
    
    private func triggerFocusZoom(at position: CGPoint, type: FocusZoomTrigger.TriggerType) {
        focusZoomTrigger = FocusZoomTrigger(position: position, timestamp: Date(), type: type)
    }
    
    func clearFocusZoomTrigger() {
        focusZoomTrigger = nil
    }
}
