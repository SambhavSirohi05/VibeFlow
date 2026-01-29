# Product Requirements Document (PRD)

## Product Name
**VibeFlow** (working name)

## One‑line Description
A lightweight, beautiful macOS screen recorder focused on *clarity*, *cursor‑centric storytelling*, and *aesthetic exports* — built for creators, educators, and developers who want ScreenFlow‑like results without complexity.

---

## 1. Problem Statement

Most screen recording tools fall into two extremes:
- **Powerful but ugly/complex** (OBS)
- **Pretty but expensive or limited** (ScreenFlow, Camtasia)

Key pain points users face:
- Cursor is hard to follow in recordings
- No visual hierarchy (viewer doesn’t know where to look)
- Requires heavy editing after recording
- Overkill features for simple tutorials

**Opportunity:** Build a focused macOS‑native recorder that makes recordings *look good by default*, with minimal editing.

---

## 2. Goals & Non‑Goals

### Goals
- Produce *beautiful screen recordings by default*
- Make cursor actions obvious and pleasant to watch
- Require little to no post‑editing for common use cases
- Be fast, lightweight, and macOS‑native

### Non‑Goals
- Compete with full NLEs (Final Cut, Premiere)
- Multi‑track timeline editing (v1)
- Cloud hosting or social features (v1)

---

## 3. Target Users

### Primary Users
1. **Indie Developers** – demoing apps, walkthroughs
2. **Educators / Students** – explaining concepts
3. **Founders** – product demos, pitches
4. **Content Creators** – tutorials, short‑form clips

### Secondary Users
- Technical writers
- UX designers
- Support teams

---

## 4. Core Use Cases

1. Record a clean tutorial with visible cursor actions
2. Create product demo videos with polished framing
3. Export videos ready for YouTube / X / Reels
4. Explain workflows without manual zooming/editing

---

## 5. Functional Requirements

### 5.1 Recording

**Must Have**
- Record entire screen or single display
- 60 FPS recording
- High‑quality video encoding
- Optional system audio
- Optional microphone audio

**Constraints**
- macOS 13+
- Uses ScreenCaptureKit

---

### 5.2 Cursor Tracking

**Must Have**
- Track cursor position at recording time
- Record timestamps for movement
- Detect left/right clicks

**Nice to Have**
- Detect drag events
- Detect scroll

---

### 5.3 Cursor Visual Effects

**Default Enabled (can be toggled off)**
- Cursor halo (soft circular highlight)
- Smooth interpolation between positions
- Click ripple animation

**Configurable Settings**
- Halo size
- Halo opacity
- Click ripple duration

---

### 5.4 Visual Framing & Background

**Must Have**
- Solid color background
- Gradient background
- Rounded corners on screen capture
- Drop shadow

**Presets**
- Minimal (no background)
- Clean (light gradient)
- Dark (dark gradient)

---

### 5.5 Aspect Ratios

**Supported Ratios**
- Original
- 16:9 (YouTube)
- 1:1 (Instagram)
- 9:16 (Shorts / Reels)

**Behavior**
- Content centered
- Padding added automatically
- No stretching

---

### 5.6 Export

**Formats**
- MP4 (H.264)

**Quality**
- 1080p @ 60fps (default)
- 4K (future)

**Export UX**
- Progress indicator
- Cancel export
- Save dialog

---

## 6. Non‑Functional Requirements

### Performance
- Minimal CPU usage during recording
- No dropped frames under normal usage

### Reliability
- Safe handling of permission denial
- Graceful stop on crash

### Privacy
- All processing is local
- No network calls
- No telemetry (v1)

---

## 7. UX / UI Principles

- Minimal UI
- Few buttons
- Clear recording state
- Friendly animations

### Main UI Components
- Start / Stop button
- Recording indicator
- Settings panel (collapsed by default)
- Export button

---

## 8. User Flow

### Recording Flow
1. Launch app
2. Grant permissions (first run)
3. Click **Start Recording**
4. Perform actions
5. Click **Stop**
6. Preview frame
7. Export

---

## 9. Technical Architecture (High Level)

```
macOS App (SwiftUI)
│
├── Screen Recorder (ScreenCaptureKit)
├── Cursor Tracker (CoreGraphics)
├── Event Store (timestamps)
├── Renderer
│   ├── Background Layer
│   ├── Screen Video Layer
│   └── Cursor Overlay Layer
└── Export Engine (AVFoundation)
```

---

## 10. MVP Scope (v0.1)

**Included**
- Screen recording
- Cursor halo
- Click ripple
- Gradient background
- 16:9 export
- MP4 export

**Excluded**
- Timeline editing
- Keystroke overlay
- Auto zoom
- Presets management

---

## 11. Success Metrics

- Time to first recording < 30 seconds
- Export without manual editing
- Positive feedback on cursor clarity

---

## 12. Future Roadmap (Post‑MVP)

- Auto zoom to cursor
- Keystroke overlay
- Silence removal
- Smart cuts
- Preset sharing
- Paid Pro tier

---

## 13. Risks & Mitigations

| Risk | Mitigation |
|----|----|
| Performance drops | Optimize frame sampling |
| Permission friction | Clear onboarding UI |
| Complex rendering | Incremental MVP |

---

## 14. Open Questions

- Live overlay vs post‑processing rendering?
- Support external displays in v1?
- Preset system complexity?

---

**Status:** Draft v1

