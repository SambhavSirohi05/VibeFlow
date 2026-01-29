import SwiftUI

// MARK: - Configuration Models

enum BackgroundType: Equatable {
    case solid(Color)
    case gradient([Color])
    case image(URL)
}

// Recording resolution (what we capture at)
enum RecordingResolution: String, CaseIterable, Identifiable {
    case native = "Native (Display Resolution)"
    case hd1080 = "1080p (1920x1080)"
    case qhd1440 = "1440p (2560x1440)"
    case uhd4k = "4K (3840x2160)"
    
    var id: String { rawValue }
    
    func size(for displaySize: CGSize) -> CGSize {
        switch self {
        case .native:
            return displaySize  // Use actual display resolution
        case .hd1080:
            return CGSize(width: 1920, height: 1080)
        case .qhd1440:
            return CGSize(width: 2560, height: 1440)
        case .uhd4k:
            return CGSize(width: 3840, height: 2160)
        }
    }
}

enum ExportPreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case landscape16_9 = "16:9 Landscape"
    case square = "1:1 Square"
    case portrait9_16 = "9:16 Portrait"
    
    var id: String { rawValue }
    
    func size(for sourceSize: CGSize) -> CGSize {
        switch self {
        case .original:
            return sourceSize
        case .landscape16_9:
            let maxDim = max(sourceSize.width, sourceSize.height)
            return CGSize(width: maxDim, height: maxDim * 9 / 16)
        case .square:
            let maxDim = max(sourceSize.width, sourceSize.height)
            return CGSize(width: maxDim, height: maxDim)
        case .portrait9_16:
            let maxDim = max(sourceSize.width, sourceSize.height)
            return CGSize(width: maxDim * 9 / 16, height: maxDim)
        }
    }
}

enum ZoomTriggerMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case manual = "Manual Key"
    
    var id: String { rawValue }
}

struct RendererConfiguration {
    var background: BackgroundType = .gradient([.blue, .purple])
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 10
    var padding: CGFloat = 50
    var preset: ExportPreset = .original
    var recordingResolution: RecordingResolution = .native
    
    // Cursor zoom settings
    var enableCursorZoom: Bool = true // Re-enabled for testing camera commitment fix
    var zoomTriggerMode: ZoomTriggerMode = .auto
    var triggerKey: Int = 6 // Default to 'Z' (0x06)
    var zoomStrength: CGFloat = 1.5  // 1.0 = no zoom, 2.0 = 2x zoom
    var zoomIdleDelay: TimeInterval = 0.5  // Seconds before zoom triggers
    var showCursorHighlight: Bool = false  // Disable yellow halo
    
    // For convenience in UI
    var solidColor: Color = .blue
    var gradientColors: [Color] = [Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]
    
    // Recommended defaults
    static let recommendedDefaults = RendererConfiguration(
        background: .gradient([Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]),
        cornerRadius: 16,
        shadowRadius: 10,
        padding: 50,
        preset: .original,
        recordingResolution: .native,
        enableCursorZoom: true,
        zoomTriggerMode: .auto,
        triggerKey: 6,
        zoomStrength: 1.5,
        zoomIdleDelay: 0.5,
        showCursorHighlight: false,
        solidColor: .blue,
        gradientColors: [Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]
    )
    
    mutating func resetToDefaults() {
        self = RendererConfiguration.recommendedDefaults
    }
}



// MARK: - Layout Preview Component

struct LayoutPreview: View {
    let config: RendererConfiguration
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Content rectangle with padding, corners, and shadow
                RoundedRectangle(cornerRadius: config.cornerRadius / 4) // Scale down for preview
                    .fill(Color.white.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: config.cornerRadius / 4)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: config.shadowRadius / 4, x: 0, y: 2)
                    .padding(config.padding / 4) // Scale down padding for preview
            }
        }
        .frame(height: 120)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch config.background {
        case .solid(let color):
            color
        case .gradient(let colors):
            if colors.count >= 2 {
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.blue
            }
        case .image(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray
            }
        }
    }
}

// MARK: - BackgroundRenderer View

struct BackgroundRenderer: View {
    @Binding var config: RendererConfiguration
    
    var body: some View {
        VStack(spacing: 20) {
            // Live Preview
            GroupBox(label: Text("Preview")) {
                LayoutPreview(config: config)
                    .padding(.vertical, 8)
            }
            
            GroupBox(label: Text("Background")) {
                Picker("Type", selection: Binding(
                    get: {
                        switch config.background {
                        case .solid: return 0
                        case .gradient: return 1
                        case .image: return 2
                        }
                    },
                    set: { (index: Int) in
                        switch index {
                        case 0: config.background = .solid(config.solidColor)
                        case 1: config.background = .gradient(config.gradientColors)
                        case 2: 
                            // Initialize with a placeholder URL
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("placeholder.png")
                            config.background = .image(tempURL)
                        default: break 
                        }
                    }
                )) {
                    Text("Solid").tag(0)
                    Text("Gradient").tag(1)
                    Text("Image").tag(2)
                }
                .pickerStyle(.segmented)
                
                if case .solid = config.background {
                    ColorPicker("Color", selection: $config.solidColor)
                        .onChange(of: config.solidColor) { newValue in
                            config.background = .solid(newValue)
                        }
                } else if case .gradient = config.background {
                    HStack {
                        ColorPicker("Start", selection: $config.gradientColors[0])
                        ColorPicker("End", selection: $config.gradientColors[1])
                    }
                    .onChange(of: config.gradientColors) { newValue in
                        config.background = .gradient(newValue)
                    }
                } else if case .image(let url) = config.background {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Choose Image...") {
                            selectImageFile()
                        }
                        .buttonStyle(.bordered)
                        
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 80)
                                .cornerRadius(8)
                                .clipped()
                        } else {
                            Text("No image selected")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            
            GroupBox(label: Text("Recording")) {
                Picker("Resolution", selection: $config.recordingResolution) {
                    ForEach(RecordingResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
            }
            
            GroupBox(label: Text("Layout")) {
                Picker("Preset", selection: $config.preset) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                
                HStack {
                    Text("Padding")
                    Slider(value: $config.padding, in: 0...200)
                }
                
                HStack {
                    Text("Corners")
                    Slider(value: $config.cornerRadius, in: 0...50)
                }
                
                HStack {
                    Text("Shadow")
                    Slider(value: $config.shadowRadius, in: 0...50)
                }
            }
            
            GroupBox(label: Text("Cursor Zoom")) {
                Toggle("Enable Zoom", isOn: $config.enableCursorZoom)
                
                if config.enableCursorZoom {
                    Picker("Trigger Mode", selection: $config.zoomTriggerMode) {
                        ForEach(ZoomTriggerMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if config.zoomTriggerMode == .manual {
                        HStack {
                            Text("Trigger Key")
                            Spacer()
                            KeyRecorder(keyCode: $config.triggerKey)
                        }
                    } else {
                        HStack {
                            Text("Idle Delay")
                            Slider(value: $config.zoomIdleDelay, in: 0.1...2.0, step: 0.1)
                            Text(String(format: "%.1fs", config.zoomIdleDelay))
                                .frame(width: 40)
                        }
                    }
                    
                    HStack {
                        Text("Zoom Strength")
                        Slider(value: $config.zoomStrength, in: 1.0...3.0, step: 0.1)
                        Text(String(format: "%.1fx", config.zoomStrength))
                            .frame(width: 40)
                    }
                }
            }
            
            // Reset Button
            Button(action: {
                config.resetToDefaults()
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Recommended")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .frame(width: 300)
    }
    
    // ... (rest of the file)
    private func selectImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]
        panel.message = "Choose a background image"
        
        if panel.runModal() == .OK, let url = panel.url {
            config.background = .image(url)
        }
    }
}

struct KeyRecorder: View {
    @Binding var keyCode: Int
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
            if isRecording {
                startRecording()
            } else {
                stopRecording()
            }
        }) {
            Text(isRecording ? "Press any key..." : (keyName(for: keyCode) ?? "Key \(keyCode)"))
                .frame(minWidth: 80)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .red : .primary)
    }
    
    private func startRecording() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyCode = Int(event.keyCode)
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
    
    private func keyName(for code: Int) -> String? {
        // Simple mapping for common keys
        switch code {
        case 53: return "Esc"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        default:
            // Try to convert to character
            // This is a naive implementation, but sufficient for now
            return "Code: \(code)"
        }
    }
}
