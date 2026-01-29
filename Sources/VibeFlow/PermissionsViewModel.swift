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
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        
        if !hasScreenRecordingPermission {
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
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
