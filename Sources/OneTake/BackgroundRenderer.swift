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

enum SubtitleStyle: String, CaseIterable, Identifiable {
    case wordByWord = "Word by Word"
    case grouped = "Segment / Line"
    
    var id: String { rawValue }
}

enum SubtitleFontSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    var id: String { rawValue }
    
    func size(for canvasHeight: CGFloat) -> CGFloat {
        switch self {
        case .small: return max(18.0, canvasHeight * 0.028)
        case .medium: return max(26.0, canvasHeight * 0.038)
        case .large: return max(34.0, canvasHeight * 0.05)
        }
    }
}

enum SubtitleTextColor: String, CaseIterable, Identifiable {
    case white = "White"
    case yellow = "Yellow"
    case cyan = "Cyan"
    case green = "Green"
    
    var id: String { rawValue }
    
    var color: NSColor {
        switch self {
        case .white: return .white
        case .yellow: return NSColor(red: 0.98, green: 0.9, blue: 0.15, alpha: 1.0)
        case .cyan: return NSColor(red: 0.15, green: 0.85, blue: 0.98, alpha: 1.0)
        case .green: return NSColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
        }
    }
    
    var swiftUIColor: Color {
        switch self {
        case .white: return .white
        case .yellow: return Color(red: 0.98, green: 0.9, blue: 0.15)
        case .cyan: return Color(red: 0.15, green: 0.85, blue: 0.98)
        case .green: return Color(red: 0.2, green: 0.9, blue: 0.4)
        }
    }
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
    var cameraPosition: CameraPosition = .bottomRight
    var cameraShape: CameraShape = .roundedRectangle
    var cameraSize: CGFloat = 400.0
    var enableCameraBorder: Bool = false
    
    // Subtitle settings
    var enableAutoSubtitles: Bool = false
    var sarvamAPIKey: String = UserDefaults.standard.string(forKey: "sarvamAPIKey") ?? "" {
        didSet {
            UserDefaults.standard.set(sarvamAPIKey, forKey: "sarvamAPIKey")
        }
    }
    var subtitleStyle: SubtitleStyle = .grouped
    var subtitleFontSize: SubtitleFontSize = .medium
    var subtitleTextColor: SubtitleTextColor = .white
    var subtitleBgOpacity: Double = 0.6
    
    // Teleprompter settings
    var enableTeleprompter: Bool = false
    var teleprompterText: String = "Type or paste your script here..."
    var teleprompterFontSize: CGFloat = 24.0
    var teleprompterOpacity: Double = 0.7
    var teleprompterScrollSpeed: Double = 30.0
    var isTeleprompterScrolling: Bool = false
    
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
        cameraPosition: .bottomRight,
        cameraShape: .roundedRectangle,
        cameraSize: 400.0,
        enableCameraBorder: false,
        enableAutoSubtitles: false,
        sarvamAPIKey: "",
        subtitleStyle: .grouped,
        subtitleFontSize: .medium,
        subtitleTextColor: .white,
        subtitleBgOpacity: 0.6,
        enableTeleprompter: false,
        teleprompterText: "Type or paste your script here...",
        teleprompterFontSize: 24.0,
        teleprompterOpacity: 0.7,
        teleprompterScrollSpeed: 30.0,
        isTeleprompterScrolling: false,
        solidColor: .blue,
        gradientColors: [Color(red: 0.2, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.2, blue: 0.4)]
    )
    
    mutating func resetToDefaults() {
        let currentKey = self.sarvamAPIKey
        self = RendererConfiguration.recommendedDefaults
        self.sarvamAPIKey = currentKey
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
                
                // Camera bubble preview (inside ZStack, positioned appropriately)
                if config.enableCamera {
                    cameraPreviewBubble
                }
                
                // Subtitle capsule preview
                if config.enableAutoSubtitles {
                    subtitlePreviewPill
                }
            }
        }
        .frame(height: 120)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var cameraPreviewBubble: some View {
        let bubbleSize: CGFloat = config.cameraSize / 5.0
        let margin = max(6.0, config.padding / 4.0)
        
        return Group {
            if config.cameraShape == .circle {
                Circle()
                    .fill(Color.gray.opacity(0.8))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: bubbleSize * 0.4))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: config.enableCameraBorder ? 1.0 : 0.0)
                    )
                    .frame(width: bubbleSize, height: bubbleSize)
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.8))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: bubbleSize * 0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white, lineWidth: config.enableCameraBorder ? 1.0 : 0.0)
                    )
                    .frame(width: bubbleSize, height: bubbleSize * 0.75)
                    .shadow(radius: 2)
            }
        }
        .padding(margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: previewAlignment(for: config.cameraPosition))
    }
    
    private func previewAlignment(for position: CameraPosition) -> Alignment {
        switch position {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
    
    private var subtitlePreviewPill: some View {
        let fontSize: CGFloat = {
            switch config.subtitleFontSize {
            case .small: return 7
            case .medium: return 9
            case .large: return 11
            }
        }()
        
        let text = config.subtitleStyle == .wordByWord ? "Subtitles" : "Aesthetic Captions Active"
        
        return Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(config.subtitleTextColor.swiftUIColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(config.subtitleBgOpacity))
            )
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
        VStack(alignment: .leading, spacing: 16) {
            // Live Preview
            GroupBox(label: Text("Preview")) {
                LayoutPreview(config: config)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Background")) {
                VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.bottom, 4)
                    
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
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: image)
                                       .resizable()
                                       .aspectRatio(contentMode: .fill)
                                       .frame(height: 80)
                                       .frame(maxWidth: .infinity)
                                       .cornerRadius(8)
                                       .clipped()
                                    
                                    Button(action: {
                                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("placeholder.png")
                                        config.background = .image(tempURL)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                            .shadow(radius: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .help("Remove image")
                                }
                            } else {
                                Text("No image selected")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Resolution")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Resolution", selection: $config.recordingResolution) {
                        ForEach(RecordingResolution.allCases) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Layout")) {
                VStack(alignment: .leading, spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Cursor Zoom")) {
                VStack(alignment: .leading, spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Audio")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Audio Source", selection: $config.audioMode) {
                        ForEach(AudioCaptureMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Camera")) {
                VStack(alignment: .leading, spacing: 8) {
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
                            Slider(value: $config.cameraSize, in: 100...600, step: 10)
                            Text(String(format: "%.0fpx", config.cameraSize))
                                .frame(width: 45)
                        }
                        
                        Toggle("Show Border", isOn: $config.enableCameraBorder)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Subtitles")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-Generate Subtitles", isOn: $config.enableAutoSubtitles)
                    
                    if config.enableAutoSubtitles {
                        SecureField("Sarvam API Key", text: $config.sarvamAPIKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Style Mode", selection: $config.subtitleStyle) {
                            ForEach(SubtitleStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        
                        Picker("Font Size", selection: $config.subtitleFontSize) {
                            ForEach(SubtitleFontSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        
                        Picker("Text Color", selection: $config.subtitleTextColor) {
                            ForEach(SubtitleTextColor.allCases) { color in
                                Text(color.rawValue).tag(color)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Background Opacity")
                                Spacer()
                                Text(String(format: "%.0f%%", config.subtitleBgOpacity * 100))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $config.subtitleBgOpacity, in: 0.0...1.0, step: 0.1)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            GroupBox(label: Text("Teleprompter / Script")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Teleprompter Overlay", isOn: $config.enableTeleprompter)
                    
                    if config.enableTeleprompter {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Script Text:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $config.teleprompterText)
                                .font(.system(size: 11))
                                .frame(height: 100)
                                .border(Color.secondary.opacity(0.2), width: 1)
                                .cornerRadius(4)
                            
                            HStack {
                                Text("Font Size")
                                Slider(value: $config.teleprompterFontSize, in: 16...48, step: 2)
                                Text("\(Int(config.teleprompterFontSize))pt")
                                    .frame(width: 45)
                            }
                            
                            HStack {
                                Text("Opacity")
                                Slider(value: $config.teleprompterOpacity, in: 0.2...1.0, step: 0.05)
                                Text(String(format: "%.0f%%", config.teleprompterOpacity * 100))
                                    .frame(width: 45)
                            }
                            
                            HStack {
                                Text("Scroll Speed")
                                Slider(value: $config.teleprompterScrollSpeed, in: 10...120, step: 5)
                                Text("\(Int(config.teleprompterScrollSpeed))px")
                                    .frame(width: 45)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            // Footer Links
            HStack(spacing: 24) {
                IconButtonLink(
                    imageName: "github",
                    isCustomImage: true,
                    urlString: "https://github.com/SambhavSirohi05/OneTake",
                    tooltip: "Visit GitHub Repository"
                )
                
                IconButtonLink(
                    imageName: "globe",
                    isCustomImage: false,
                    urlString: "https://onetakeweb.vercel.app/",
                    tooltip: "Visit Website"
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            
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
        .frame(width: 360)
    }
    
    private func selectImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]
        panel.message = "Choose a background image"
        
        let window = NSApp.keyWindow
        if let window = window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async {
                        self.config.background = .image(url)
                    }
                }
            }
        } else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async {
                        self.config.background = .image(url)
                    }
                }
            }
        }
    }
    
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Where should OneTake save your recordings?"
        panel.prompt = "Select Folder"
        
        let window = NSApp.keyWindow
        if let window = window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async {
                        self.config.outputDirectory = url
                    }
                }
            }
        } else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async {
                        self.config.outputDirectory = url
                    }
                }
            }
        }
    }
}

// MARK: - Footer Helpers

struct IconButtonLink: View {
    let imageName: String
    let isCustomImage: Bool
    let urlString: String
    let tooltip: String
    
    @State private var isHovered = false
    
    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                Group {
                    if isCustomImage {
                        let nsImage: NSImage? = {
                            if let path = Bundle.module.path(forResource: imageName, ofType: "svg") {
                                return NSImage(contentsOfFile: path)
                            }
                            if let path = Bundle.module.path(forResource: imageName, ofType: "png") {
                                return NSImage(contentsOfFile: path)
                            }
                            return nil
                        }()
                        
                        if let image = nsImage {
                            let templateImage: NSImage = {
                                image.isTemplate = true
                                return image
                            }()
                            Image(nsImage: templateImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 20))
                        }
                    } else {
                        Image(systemName: imageName)
                            .font(.system(size: 20))
                    }
                }
                .foregroundColor(isHovered ? .blue : .secondary)
                .padding(8)
                .background(
                    Circle()
                        .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
    }
}
