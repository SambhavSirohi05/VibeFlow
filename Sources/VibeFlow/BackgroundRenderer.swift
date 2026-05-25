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
        guard displaySize.height > 0 else { return displaySize }
        
        switch self {
        case .native:
            return displaySize  // Use actual display resolution
        case .hd1080:
            let targetHeight: CGFloat = 1080
            let scale = targetHeight / displaySize.height
            let targetWidth = Int((displaySize.width * scale).rounded())
            let evenWidth = targetWidth + (targetWidth % 2 == 0 ? 0 : 1)
            return CGSize(width: CGFloat(evenWidth), height: targetHeight)
        case .qhd1440:
            let targetHeight: CGFloat = 1440
            let scale = targetHeight / displaySize.height
            let targetWidth = Int((displaySize.width * scale).rounded())
            let evenWidth = targetWidth + (targetWidth % 2 == 0 ? 0 : 1)
            return CGSize(width: CGFloat(evenWidth), height: targetHeight)
        case .uhd4k:
            let targetHeight: CGFloat = 2160
            let scale = targetHeight / displaySize.height
            let targetWidth = Int((displaySize.width * scale).rounded())
            let evenWidth = targetWidth + (targetWidth % 2 == 0 ? 0 : 1)
            return CGSize(width: CGFloat(evenWidth), height: targetHeight)
        }
    }
}

enum AudioCaptureMode: String, CaseIterable, Identifiable {
    case screenOnly = "Screen Only"
    case micOnly = "Mic Only"
    case both = "Both"
    case none = "None"
    
    var id: String { rawValue }
}

enum CameraPosition: String, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    
    var id: String { rawValue }
}

enum CameraShape: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case roundedRectangle = "Rounded Rectangle"
    
    var id: String { rawValue }
}

struct RendererConfiguration {
    var background: BackgroundType = .gradient([.blue, .purple])
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 10
    var padding: CGFloat = 50
    var recordingResolution: RecordingResolution = .native
    var outputDirectory: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    
    // Cursor zoom settings
    var enableCursorZoom: Bool = true // Re-enabled for testing camera commitment fix
    var zoomStrength: CGFloat = 1.5  // 1.0 = no zoom, 2.0 = 2x zoom
    var zoomIdleDelay: TimeInterval = 0.5  // Seconds before zoom triggers
    
    // Audio settings
    var audioMode: AudioCaptureMode = .both
    
    // Camera settings
    var enableCamera: Bool = false
    var cameraPosition: CameraPosition = .bottomLeft
    var cameraShape: CameraShape = .circle
    var cameraSize: CGFloat = 200.0
    var enableCameraBorder: Bool = false
    
    // For convenience in UI
    var solidColor: Color = .blue
    var gradientColors: [Color] = [Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]
    
    // Recommended defaults
    static let recommendedDefaults = RendererConfiguration(
        background: .gradient([Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]),
        cornerRadius: 16,
        shadowRadius: 10,
        padding: 50,
        recordingResolution: .native,
        enableCursorZoom: true,
        zoomStrength: 1.5,
        zoomIdleDelay: 0.5,
        audioMode: .both,
        enableCamera: false,
        cameraPosition: .bottomLeft,
        cameraShape: .circle,
        cameraSize: 200.0,
        enableCameraBorder: false,
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
            
            GroupBox(label: Text("Resolution")) {
                Picker("Resolution", selection: $config.recordingResolution) {
                    ForEach(RecordingResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
            }
            
            GroupBox(label: Text("Storage")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save Recordings to:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(config.outputDirectory?.path ?? "Temporary Folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                        
                        Button("Change...") {
                            selectOutputDirectory()
                        }
                    }
                }
            }
            
            GroupBox(label: Text("Layout")) {
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
                    HStack {
                        Text("Idle Delay")
                        Slider(value: $config.zoomIdleDelay, in: 0.1...2.0, step: 0.1)
                        Text(String(format: "%.1fs", config.zoomIdleDelay))
                            .frame(width: 40)
                    }
                }
            }
            
            GroupBox(label: Text("Audio")) {
                Picker("Audio Source", selection: $config.audioMode) {
                    ForEach(AudioCaptureMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
            
            GroupBox(label: Text("Camera")) {
                Toggle("Enable Camera", isOn: $config.enableCamera)
                
                if config.enableCamera {
                    Picker("Position", selection: $config.cameraPosition) {
                        ForEach(CameraPosition.allCases) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    
                    Picker("Shape", selection: $config.cameraShape) {
                        ForEach(CameraShape.allCases) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    
                    HStack {
                        Text("Size")
                        Slider(value: $config.cameraSize, in: 100...300, step: 10)
                        Text(String(format: "%.0fpx", config.cameraSize))
                            .frame(width: 45)
                    }
                    
                    Toggle("Show Border", isOn: $config.enableCameraBorder)
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
    
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Where should VibeFlow save your recordings?"
        panel.prompt = "Select Folder"
        
        if panel.runModal() == .OK {
            config.outputDirectory = panel.url
        }
    }
}
