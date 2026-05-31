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
        .frame(minWidth: 720, minHeight: 560)
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

struct WindowGridItem: View {
    let target: CaptureWindowTarget
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let thumbnail = target.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 170, height: 110)
                            .clipped()
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 170, height: 110)
                            .overlay(
                                Image(systemName: "window.template")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 3)
                    }
                }
                .frame(width: 170, height: 110)
                
                HStack(spacing: 6) {
                    if let icon = getAppIcon(for: target.window.owningApplication) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .frame(width: 14, height: 14)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(target.appName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Text(target.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 170)
            .padding(6)
            .background(Color.white.opacity(isSelected ? 0.05 : 0.0))
            .cornerRadius(8)
            .contentShape(Rectangle()) // Ensures the whole card area is clickable
        }
        .buttonStyle(.plain)
    }
    
    private func getAppIcon(for app: SCRunningApplication?) -> NSImage? {
        guard let bundleId = app?.bundleIdentifier else { return nil }
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
}

struct DisplayGridItem: View {
    let display: SCDisplay
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 170, height: 110)
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 28))
                                    .foregroundColor(.blue)
                                Text("Display \(display.displayID)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        )
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 3)
                    }
                }
                .frame(width: 170, height: 110)
                
                Text("Screen \(display.displayID)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(display.width) x \(display.height)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 170)
            .padding(6)
            .background(Color.white.opacity(isSelected ? 0.05 : 0.0))
            .cornerRadius(8)
            .contentShape(Rectangle()) // Ensures the whole card area is clickable
        }
        .buttonStyle(.plain)
    }
}

struct RecorderView: View {
    @ObservedObject var recorder: ScreenRecorder
    @State private var showSettings = false
    @State private var showSharingPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let error = recorder.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            
            if recorder.isRecording {
                VStack(spacing: 20) {
                    Spacer()
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
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 25) {
                    Spacer()
                    
                    // Simple Settings Grid (Matching the clean original aesthetic)
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 16) {
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
                    
                    Spacer()
                    
                    // Main Start Recording Button - triggers sheet
                    Button(action: {
                        showSharingPicker = true
                    }) {
                        HStack {
                            Image(systemName: "record.circle")
                            Text("Start Recording")
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(width: 240, height: 38)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showSharingPicker) {
            SharingPickerView(recorder: recorder, isPresented: $showSharingPicker)
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

struct SharingPickerView: View {
    @ObservedObject var recorder: ScreenRecorder
    @Binding var isPresented: Bool
    
    // Grid of cards inside the picker
    let gridColumns = [
        GridItem(.adaptive(minimum: 170, maximum: 180), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack {
                Text("Select what to record")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // Discord-style Selector
            HStack(spacing: 0) {
                ForEach(CaptureTargetType.allCases) { type in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            recorder.selectedTargetType = type
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: type == .window ? "window.template" : "desktopcomputer")
                            Text(type.rawValue)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(recorder.selectedTargetType == type ? .white : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(recorder.selectedTargetType == type ? Color.white.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle()) // Entire selector segment is clickable
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.25))
            .cornerRadius(8)
            .padding(.horizontal)
            
            // Previews Area
            ScrollView {
                if recorder.selectedTargetType == .window {
                    if recorder.availableWindows.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning for open windows...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(recorder.availableWindows) { target in
                                WindowGridItem(
                                    target: target,
                                    isSelected: recorder.selectedWindow?.id == target.id,
                                    action: {
                                        recorder.selectedWindow = target
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    if recorder.availableDisplays.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning for displays...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(recorder.availableDisplays, id: \.displayID) { display in
                                DisplayGridItem(
                                    display: display,
                                    isSelected: recorder.selectedDisplay?.displayID == display.displayID,
                                    action: {
                                        recorder.selectedDisplay = display
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.15)))
            .padding(.horizontal)
            
            // Bottom Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(EqualWidthButtonStyle())
                .frame(width: 90)
                
                Button(action: {
                    isPresented = false
                    Task {
                        await recorder.start()
                    }
                }) {
                    Text("Start Capture")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            (recorder.selectedTargetType == .display && recorder.selectedDisplay == nil) ||
                            (recorder.selectedTargetType == .window && recorder.selectedWindow == nil)
                            ? Color.gray.opacity(0.3) : Color.blue
                        )
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(
                    (recorder.selectedTargetType == .display && recorder.selectedDisplay == nil) ||
                    (recorder.selectedTargetType == .window && recorder.selectedWindow == nil)
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 580, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await recorder.fetchAvailableContent()
        }
        .onChange(of: recorder.selectedTargetType) { _ in
            Task {
                await recorder.fetchAvailableContent()
            }
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
