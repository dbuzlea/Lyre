# player Scroll Wheel Button Layout Reference

## Visual Layout Diagram

This document shows the exact button placement on the scroll wheel, matching the classic player design.

```
                    ┌─────────────────────────┐
                    │                         │
                    │    player Screen Area     │
                    │                         │
                    └─────────────────────────┘
                              
                              
                         ╔═══════╗
                         ║ HOME  ║  ← Top Button
                         ║  |||  ║     (y: -105)
                         ╚═══════╝
                              ↑
                              │
                              │
              ╔═════════╗     │     ╔═════════╗
              ║  PREV   ║     │     ║  NEXT   ║
    ← Left    ║   ◄◄    ║     │     ║   ►►    ║    Right →
   (x: -105)  ╚═════════╝     │     ╚═════════╝   (x: +105)
                    ┌─────────┴─────────┐
                   ╱                     ╲
                  ╱    ╭─────────╮       ╲
                 │     │         │        │  ← Metallic Ring
                 │     │ SELECT  │        │     (Touch Sensitive)
                 │     │    ●    │        │
                 │     │         │        │
                  ╲    ╰─────────╯       ╱
                   ╲                     ╱
                    └─────────┬─────────┘
                              │
                              │
                              ↓
                         ╔═══════╗
                         ║   ▶   ║  ← Bottom Button
                         ║  PLAY ║     (y: +105)
                         ╚═══════╝
```

## Button Specifications

### Positioning Coordinates

All positions are relative to the center of the scroll wheel (0, 0):

| Button   | X Offset | Y Offset | Function          |
|----------|----------|----------|-------------------|
| MENU     | 0        | -105     | Navigate back     |
| PLAY     | 0        | +105     | Play/Pause        |
| PREV     | -105     | 0        | Previous track    |
| NEXT     | +105     | 0        | Next track        |
| SELECT   | 0        | 0        | Select/Confirm    |

### Button Dimensions

| Button   | Width | Height | Shape      |
|----------|-------|--------|------------|
| MENU     | auto  | 40pt   | Text + Icon|
| PLAY     | auto  | 40pt   | Icon + Text|
| PREV     | 40pt  | auto   | Icon + Text|
| NEXT     | 40pt  | auto   | Icon + Text|
| SELECT   | 100pt | 100pt  | Circle     |

### Scroll Wheel Geometry

| Element        | Size (Diameter) | Purpose                    |
|----------------|-----------------|----------------------------|
| Outer Ring     | 280pt           | Overall wheel size         |
| Touch Ring     | 260pt           | Interactive gesture area   |
| Center Button  | 120pt           | Visible center circle      |
| Select Target  | 100pt           | Tappable area              |

## Typography Specifications

### Button Labels

| Button | Font Size | Weight    | Tracking | Case  |
|--------|-----------|-----------|----------|-------|
| MENU   | 9pt       | Semibold  | 0.5      | UPPER |
| PLAY   | 8pt       | Semibold  | 0.5      | UPPER |
| PAUSE  | 8pt       | Semibold  | 0.5      | UPPER |
| PREV   | 7pt       | Semibold  | 0.3      | UPPER |
| NEXT   | 7pt       | Semibold  | 0.3      | UPPER |

### Icons

| Button | SF Symbol          | Size | Weight   |
|--------|--------------------|------|----------|
| MENU   | line.horizontal.3  | 11pt | Medium   |
| PLAY   | play.fill          | 14pt | Semibold |
| PAUSE  | pause.fill         | 14pt | Semibold |
| PREV   | backward.fill      | 13pt | Semibold |
| NEXT   | forward.fill       | 13pt | Semibold |

## Color Specifications

### Button States

| State    | Opacity | Color  | Effect      |
|----------|---------|--------|-------------|
| Normal   | 0.7     | Black  | Standard    |
| Pressed  | 0.9     | Black  | Darker      |
| Disabled | 0.3     | Gray   | Faded       |

### Center Button Gradient

**Normal State:**
```swift
RadialGradient(
    colors: [
        Color(white: 0.8),  // Center: Light
        Color(white: 0.65)  // Edge: Medium
    ],
    center: .center,
    startRadius: 0,
    endRadius: 60
)
```

**Pressed State:**
```swift
RadialGradient(
    colors: [
        Color(white: 0.7),  // Center: Medium (darker)
        Color(white: 0.55)  // Edge: Dark (darker)
    ],
    center: .center,
    startRadius: 0,
    endRadius: 60
)
```

## classic scroll-wheel Models Reference

### classic scroll-wheel player (3rd Gen - Most Iconic)

```
     ┌─────────────────┐
     │   ┌─────────┐   │
     │   │ Screen  │   │  ← Monochrome LCD
     │   │  Area   │   │
     │   └─────────┘   │
     │                 │
     │     (Apple)     │  ← Logo
     │                 │
     │     MENU        │  ← Text overlaid
     │       |||       │
     │   ┌───────┐     │
     │  PREV  ●  NEXT  │  ← All on the wheel
     │   ◄◄      ►►    │
     │   └───────┘     │
     │    ▶ PLAY       │
     └─────────────────┘
```

### Button Label Placement Styles

**Option 1: Icons + Text (Current Implementation)**
```
    MENU
     |||
     
 PREV ●  NEXT
  ◄◄      ►►
  
     ▶
   PLAY
```

**Option 2: Text Only (Alternative)**
```
   MENU
   
PREVIOUS ● NEXT
   
  PLAY/PAUSE
```

**Option 3: Icons Only (Minimal)**
```
    |||
     
  ◄◄ ● ►►
  
    ▶
```

## Touch Interaction Zones

### Wheel Ring (Touch-Sensitive for Scrolling)

The outer ring responds to circular drag gestures:

```
         Outer Edge (280pt diameter)
       ╭─────────────────────╮
      ╱  ← Touch Zone →      ╲
     │   (260pt diameter)     │
     │                        │
     │    ╭──────────╮        │
     │    │  Center  │        │
     │    │  Button  │        │
     │    │ (120pt)  │        │
     │    ╰──────────╯        │
     │                        │
      ╲                      ╱
       ╰─────────────────────╯
```

**Touch Zone Properties:**
- Starts at radius: 60pt from center (edge of center button)
- Ends at radius: 140pt from center (outer edge)
- Total touch width: 80pt wide ring

### Button Hit Areas

Minimum touch target size: **40pt × 40pt** (per iOS guidelines)

```
        ┌─────────┐
        │  40pt   │  ← Menu hit area
        │  × 40pt │
        └─────────┘
           
┌───────┐   ┌───────┐
│ 40×40 │   │ 40×40 │  ← Prev/Next hit areas
└───────┘   └───────┘

        ┌─────────┐
        │  40pt   │  ← Play hit area
        │  × 40pt │
        └─────────┘
        
     ┌─────────┐
     │  100pt  │  ← Select hit area (center)
     │  × 100pt│
     └─────────┘
```

## Animation Specifications

### Button Press Animations

**Wheel Buttons (MENU, PLAY, PREV, NEXT):**
```swift
.scaleEffect(configuration.isPressed ? 0.95 : 1.0)
.animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
```

**Center Button (SELECT):**
- No scale animation
- Visual feedback through gradient change
- Shadow reduction on press

### Rotation Gesture

**Continuous Haptic Ticks:**
- Trigger every 20° of rotation
- Style: `.light`
- Intensity: `0.6`

**Scroll Haptic:**
- Trigger when item changes
- Style: `.medium`
- Intensity: `1.0` (default)

**Boundary Haptic:**
- Trigger at list edges
- Style: `.rigid`
- Intensity: `0.4`

## Comparison with Physical player

### Similarities:
✅ Button labels overlaid on wheel  
✅ Four directional buttons + center  
✅ Circular gesture for scrolling  
✅ Click for selection  
✅ Metallic appearance  
✅ Proportional sizing  

### Digital Advantages:
✨ Dynamic button labels (Play/Pause changes)  
✨ Haptic feedback (original had mechanical clicks)  
✨ Customizable sensitivity  
✨ Perfect circular gestures (physical wheel had dead zones)  
✨ Visual press feedback  
✨ Accessibility support (VoiceOver)  

### Physical player Features Not Implemented:
❌ Physical rotation (ours is touch-based)  
❌ Mechanical click sound (we use system sound + haptics)  
❌ Headphone jack (obviously!)  

### Physical player Features Reimplemented Digitally:
✅ Hold switch — toggle at top-right of device, orange = locked  

## Implementation Code Reference

### Button Label Example (MENU):

```swift
Button(action: {}) {
    VStack(spacing: 2) {
        Text("MENU")
            .font(.system(size: 9, weight: .semibold, design: .default))
            .tracking(0.5)
        Image(systemName: "line.horizontal.3")
            .font(.system(size: 11, weight: .medium))
    }
    .foregroundStyle(isMenuPressed ? 
        Color.black.opacity(0.9) : 
        Color.black.opacity(0.7))
    .frame(height: 40)
}
.buttonStyle(WheelButtonStyle(isPressed: $isMenuPressed, action: handleMenuButton))
.offset(y: -105)
```

### Center Button Example:

```swift
Circle()
    .fill(
        RadialGradient(
            colors: [
                Color(white: isSelectPressed ? 0.7 : 0.8),
                Color(white: isSelectPressed ? 0.55 : 0.65)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 60
        )
    )
    .frame(width: 120, height: 120)
```

## Device Size Adaptations

The layout scales proportionally on different devices:

### iPhone SE / Mini (Small)
- Wheel: 250pt diameter (90% scale)
- Buttons: 36pt touch targets
- Text: 8pt / 7pt / 6pt

### iPhone Pro / Plus (Standard)
- Wheel: 280pt diameter (100% scale)
- Buttons: 40pt touch targets
- Text: 9pt / 8pt / 7pt

### iPhone Pro Max (Large)
- Wheel: 300pt diameter (107% scale)
- Buttons: 44pt touch targets
- Text: 10pt / 9pt / 8pt

### iPad (Extra Large)
- Wheel: 350pt diameter (125% scale)
- Buttons: 50pt touch targets
- Text: 12pt / 10pt / 9pt

## Accessibility Considerations

### VoiceOver Labels:

| Element | VoiceOver Label           | Hint                          |
|---------|---------------------------|-------------------------------|
| MENU    | "Menu button"             | "Navigate back"               |
| SELECT  | "Select button"           | "Activate selected item"      |
| PLAY    | "Play button" or "Pause"  | "Toggle playback"             |
| PREV    | "Previous button"         | "Skip to previous track"      |
| NEXT    | "Next button"             | "Skip to next track"          |
| Wheel   | "Scroll wheel"            | "Swipe to scroll through list"|

### Gesture Alternatives:

For users who can't perform circular gestures:
- Standard swipe gestures also work
- VoiceOver rotor for navigation
- External keyboard support (optional enhancement)

---

**Reference**: classic scroll-wheel 3rd Generation (2003)  
**Design Language**: Authentic Apple player aesthetic  
**Platform**: iOS 17+ / SwiftUI  
**Updated**: May 20, 2026
