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
        // CGPreflightScreenCaptureAccess is available in macOS 11+
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        
        // Fallback or additional check if needed (e.g. SCShareableContent)
        if !hasScreenRecordingPermission {
            // Sometimes preflight returns false but we might have it? Use SCShareableContent to trigger prompt if needed
            Task {
                do {
                    _ = try await SCShareableContent.current
                    self.hasScreenRecordingPermission = true
                } catch {
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
