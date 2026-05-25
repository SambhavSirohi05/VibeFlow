import Foundation
import ScreenCaptureKit
import AppKit

@MainActor
class PermissionsViewModel: ObservableObject {
    @Published var hasScreenRecordingPermission = false
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        checkScreenRecordingPermission()
    }
    
    func checkScreenRecordingPermission() {
        // Preflight check
        let preflight = CGPreflightScreenCaptureAccess()
        
        // If preflight is false, request access to trigger the native macOS dialog prompt
        if !preflight {
            _ = CGRequestScreenCaptureAccess()
        }
        
        // Verify by attempting to fetch shareable content to avoid false positives (e.g. terminal inheritance)
        Task {
            do {
                _ = try await SCShareableContent.current
                self.hasScreenRecordingPermission = true
            } catch {
                self.hasScreenRecordingPermission = false
            }
        }
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
