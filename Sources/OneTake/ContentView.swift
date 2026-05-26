import SwiftUI
import ScreenCaptureKit
import AppKit

struct ContentView: View {
    @StateObject private var permissions = PermissionsViewModel()
    @StateObject private var recorder = ScreenRecorder()
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("OneTake")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if permissions.hasScreenRecordingPermission {
                    RecorderView(recorder: recorder)
                } else {
                    PermissionRequestView(permissions: permissions)
                }
            }
            .padding()
            .disabled(recorder.isTranscribing)
            
            if recorder.isTranscribing {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 15) {
                    ProgressView()
                        .controlSize(.large)
                    
                    Text(recorder.transcriptionProgress ?? "Transcribing...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
                .shadow(radius: 15)
                .frame(maxWidth: 300)
            }
        }
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
                    
                    Text(verbatim: recorder.renderConfig.recordingResolution.rawValue)
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
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("Ready to Record")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    if recorder.availableDisplays.isEmpty {
                        Text("Loading displays...")
                            .foregroundStyle(.secondary)
                            .frame(height: 120)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Display")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .gridCellAnchor(.trailing)
                                
                                Menu {
                                    ForEach(recorder.availableDisplays, id: \.displayID) { display in
                                        Button("Display \(display.displayID) (\(display.width)x\(display.height))") {
                                            recorder.selectedDisplay = display
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(recorder.selectedDisplay.map { "Display \($0.displayID) (\($0.width)x\($0.height))" } ?? "Select Display")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .frame(width: 270)
                            }
                            
                            GridRow {
                                Text("Audio Source")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .gridCellAnchor(.trailing)
                                
                                Menu {
                                    ForEach(AudioCaptureMode.allCases) { mode in
                                        Button(mode.rawValue) {
                                            recorder.renderConfig.audioMode = mode
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(recorder.renderConfig.audioMode.rawValue)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .frame(width: 270)
                            }
                            
                            GridRow {
                                Text("Resolution")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .gridCellAnchor(.trailing)
                                
                                Menu {
                                    ForEach(RecordingResolution.allCases) { resolution in
                                        Button(resolution.rawValue) {
                                            recorder.renderConfig.recordingResolution = resolution
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(recorder.renderConfig.recordingResolution.rawValue)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .frame(width: 270)
                            }
                        }
                        .frame(width: 380)
                    }
                    
                    HStack(spacing: 12) {
                        Button(recorder.renderConfig.enableTeleprompter ? "Hide Script" : "Show Script") {
                            recorder.renderConfig.enableTeleprompter.toggle()
                        }
                        .buttonStyle(EqualWidthButtonStyle(tint: recorder.renderConfig.enableTeleprompter ? Color.orange : nil))
                        
                        Button("Layout Settings") {
                            recorder.isPreviewingSettings = true
                            showSettings = true
                        }
                        .buttonStyle(EqualWidthButtonStyle())
                    }
                    .frame(width: 240)
                    .padding(.vertical, 8)
                    
                    Button(action: {
                        Task { await recorder.start() }
                    }) {
                        Text("Start Recording")
                            .fontWeight(.semibold)
                            .frame(width: 240, height: 38)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
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
        .sheet(isPresented: $showSettings, onDismiss: {
            recorder.isPreviewingSettings = false
        }) {
             VStack(spacing: 0) {
                 HStack {
                     Text("Layout Settings")
                         .font(.headline)
                     Spacer()
                     Button("Done") {
                         recorder.isPreviewingSettings = false
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

struct EqualWidthButtonStyle: ButtonStyle {
    var tint: Color? = nil
    
    func makeBody(configuration: Configuration) -> some View {
        EqualWidthButton(configuration: configuration, tint: tint)
    }
    
    struct EqualWidthButton: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color?
        @State private var isHovered = false
        
        var body: some View {
            let bgColor = currentBackgroundColor
            
            configuration.label
                .foregroundColor(.white)
                .font(.body)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bgColor)
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
        
        private var currentBackgroundColor: Color {
            if configuration.isPressed {
                return tint?.opacity(0.25) ?? Color.white.opacity(0.16)
            } else if isHovered {
                return tint?.opacity(0.18) ?? Color.white.opacity(0.12)
            } else {
                return tint?.opacity(0.10) ?? Color.white.opacity(0.08)
            }
        }
    }
}
