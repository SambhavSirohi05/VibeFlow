import SwiftUI
import ScreenCaptureKit
import AppKit

struct ContentView: View {
    @StateObject private var permissions = PermissionsViewModel()
    @StateObject private var recorder = ScreenRecorder()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("VibeFlow")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if permissions.hasScreenRecordingPermission {
                RecorderView(recorder: recorder)
            } else {
                PermissionRequestView(permissions: permissions)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            permissions.checkPermissions()
            // Bring window to front
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}



struct PermissionRequestView: View {
    @ObservedObject var permissions: PermissionsViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 50))
                .foregroundStyle(.red)
            
            Text("Permissions Required")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: permissions.hasScreenRecordingPermission ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(permissions.hasScreenRecordingPermission ? .green : .red)
                    Text("Screen Recording Permission")
                    Spacer()
                    if !permissions.hasScreenRecordingPermission {
                        Button("Open Settings") {
                            permissions.openScreenRecordingSettings()
                        }
                    }
                }
                
                /*
                HStack {
                    Image(systemName: permissions.hasAccessibilityPermission ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(permissions.hasAccessibilityPermission ? .green : .red)
                    Text("Accessibility Permission (for Key Detection)")
                    Spacer()
                    if !permissions.hasAccessibilityPermission {
                        Button("Open Settings") {
                            permissions.openAccessibilitySettings()
                        }
                    }
                }
                */
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)
            .frame(maxWidth: 400)
            
            Button("Check Again") {
                permissions.checkPermissions()
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
        }
        .padding()
    }
}

struct RecorderView: View {
    @ObservedObject var recorder: ScreenRecorder
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            if let error = recorder.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            if recorder.isRecording {
                VStack {
                    Text("Recording in progress...")
                        .font(.title2)
                        .foregroundStyle(.green)
                    
                    Text(verbatim: recorder.renderConfig.preset.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                    
                    Button("Stop Recording") {
                        Task { await recorder.stop() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
            } else {
                VStack(spacing: 15) {
                    Text("Ready to Record")
                        .font(.title2)
                    
                    if recorder.availableDisplays.isEmpty {
                        Text("Loading displays...")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Display", selection: $recorder.selectedDisplay) {
                            ForEach(recorder.availableDisplays, id: \.displayID) { display in
                                Text("Display \(display.displayID) (\(display.width)x\(display.height))")
                                    .tag(Optional(display))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    
                    Button("Layout Settings") {
                        showSettings = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Start Recording") {
                        Task { await recorder.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(recorder.selectedDisplay == nil)
                }
            }
        }
        .padding()
        .task {
            // Re-check permissions when view appears
             // But actually this view is only shown if permissions are good?
             // It's fine.
            await recorder.fetchAvailableContent()
        }
        .sheet(isPresented: $showSettings) {
             VStack(spacing: 0) {
                 HStack {
                     Text("Layout Settings")
                         .font(.headline)
                     Spacer()
                     Button("Done") {
                         showSettings = false
                     }
                 }
                 .padding()
                 
                 Divider()
                 
                 ScrollView {
                     BackgroundRenderer(config: $recorder.renderConfig)
                         .padding(.bottom, 20)
                 }
             }
             .frame(width: 400, height: 650)
        }
    }
}
