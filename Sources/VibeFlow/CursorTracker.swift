import Foundation
import CoreGraphics
import Combine
import AppKit

struct CursorEvent {
    let id: UUID
    let timestamp: Date
    let position: CGPoint
    let eventType: EventType
    
    enum EventType {
        case move
        case leftClick
        case rightClick
    }
}

class CursorTracker {
    private var timer: Timer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    let cursorEvents = PassthroughSubject<CursorEvent, Never>()
    
    init() {}
    
    deinit {
        stopTracking()
    }
    
    func startTracking() {
        startPositionTracking()
        startClickTracking()
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }
    
    private func startPositionTracking() {
        // 60Hz = ~0.0167 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let position = self.getCurrentCursorPosition()
            let event = CursorEvent(
                id: UUID(),
                timestamp: Date(),
                position: position,
                eventType: .move
            )
            self.cursorEvents.send(event)
        }
    }
    
    private func startClickTracking() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let tracker = Unmanaged<CursorTracker>.fromOpaque(refcon).takeUnretainedValue()
                tracker.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handleEvent(type: CGEventType, event: CGEvent) {
        let position = event.location
        let eventType: CursorEvent.EventType
        
        switch type {
        case .leftMouseDown:
            eventType = .leftClick
        case .rightMouseDown:
            eventType = .rightClick
        default:
            return
        }
        
        let cursorEvent = CursorEvent(
            id: UUID(),
            timestamp: Date(),
            position: position,
            eventType: eventType
        )
        cursorEvents.send(cursorEvent)
    }
    
    private func getCurrentCursorPosition() -> CGPoint {
        // CGEvent(source: nil) returns an event with the current mouse position
        return CGEvent(source: nil)?.location ?? .zero
    }
}
