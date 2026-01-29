import Foundation
import ScreenCaptureKit
import AppKit

@MainActor
class PermissionsViewModel: ObservableObject {
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false // Kept but unused for now
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        checkScreenRecordingPermission()
        // Accessibility check disabled
        // checkAccessibilityPermission() 
    }
    
    func checkScreenRecordingPermission() {
        // CGPreflightScreenCaptureAccess checks current status
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        print("DEBUG: Screen Recording Preflight status: \(hasScreenRecordingPermission)")
        
        // If not granted, try requesting via SCShareableContent to be sure
        if !hasScreenRecordingPermission {
            print("DEBUG: Preflight failed, attempting deeper check via SCShareableContent...")
            Task {
                do {
                    // This will trigger the OS prompt if not already denied
                    _ = try await SCShareableContent.current
                    self.hasScreenRecordingPermission = true
                    print("DEBUG: SCShareableContent check succeeded - permission granted!")
                } catch {
                    print("DEBUG: SCShareableContent check failed: \(error.localizedDescription)")
                    self.hasScreenRecordingPermission = false
                }
            }
        }
    }
    
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
