# OneTake

OneTake is a native macOS screen recording application built to produce polished, high-quality tutorials, presentations, and product demos without requiring post-production editing. It combines high-performance screen capture with a focus-free teleprompter, smart cursor spotlight, and automated AI subtitles.

## Core Features

- **High-Performance Capture**: Built on Apple's modern ScreenCaptureKit framework for low CPU usage. Captures displays natively or scales dynamically to 1080p, 1440p, or 4K.
- **Unified Audio Engine**: Records system audio and microphone input simultaneously, blending them into a single stereo track.
- **Smart Camera Overlay**: A floating camera bubble (Circle or Rounded Rectangle) with custom corner radius and borders. It renders at a compact $0.5\times$ size on-screen during recording to save workspace, but exports at full $1.0\times$ size in the output video.
- **Focus-Free Teleprompter**: A translucent, glassmorphic overlay for reading scripts. Bypasses Finder's window focus (First Mouse Integration), allowing you to scroll, drag, and adjust teleprompter settings instantly without clicking to focus the window first.
- **Automated Cursor Spotlight**: Follows the mouse cursor and applies a smooth zoom (up to $2.0\times$) when the cursor clicks or stops moving. Includes a 4-second delay buffer at recording start to prevent accidental zooms.
- **AI-Powered Subtitles**: Auto-generates styled word-by-word or segment subtitles using the Sarvam AI transcription API, complete with customizable font size, background opacity, and color palettes.

## System Requirements

- **OS**: macOS 13.0 (Ventura) or newer
- **Developer Tools**: Xcode 15+ / Swift 5.9+ (if compiling from source)
- **APIs**: ScreenCaptureKit, AVFoundation

## Installation & Setup

### Method 1: Pre-built Release (Recommended)
1. Download the latest installer from the official [OneTake Website](https://onetakeweb.vercel.app/).
2. Open the downloaded `OneTake.dmg`.
3. Drag the **OneTake** icon into your **Applications** folder.

> [!IMPORTANT]
> **Ad-Hoc Signing Notice (First-Run)**
> Since this application is self-signed/ad-hoc signed, macOS Gatekeeper may show a warning when opening it for the first time.
> 
> To bypass this restriction:
> 1. Open the Terminal app.
> 2. Run the following command:
>    ```bash
>    xattr -cr /Applications/OneTake.app
>    ```
> 3. Right-click **OneTake.app** in Finder and select **Open**. You will only need to do this once.

### Method 2: Build from Source
To compile and run the application locally using the Swift Package Manager:

```bash
git clone https://github.com/SambhavSirohi05/OneTake.git
cd OneTake
swift run
```

---

Developer: [Sambhav Sirohi](https://github.com/SambhavSirohi05)
