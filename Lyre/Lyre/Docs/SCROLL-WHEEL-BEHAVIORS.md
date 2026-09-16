# classic scroll-wheel Behaviors Implementation

## Overview
This document describes all the authentic classic scroll-wheel player behaviors that have been implemented in the Lyre project, making it feel like using a real player from the 2000s.

## Implemented Features

### 1. ✅ Navigation Stack with Back Button
**What it is:** The Menu button acts as a true "back" button, remembering your navigation path.

**Original player Behavior:**
- Pressing Menu takes you back through the exact screens you navigated through
- Not a hardcoded "go to main menu" button
- Works at any depth of navigation

**Implementation:**
- `navigationStack` array tracks all visited screens
- Menu button pops from stack and restores previous screen
- Works for complex paths like: Menu → Artists → Artist Detail → Album Detail → Now Playing

**Code Location:**
- `LyreView.swift`: Navigation stack state, `navigateTo()`, `navigateBack()`
- `ScrollWheelView.swift`: `handleMenuButton()` function

---

### 2. ✅ Selection Memory
**What it is:** When you navigate back, your previous selection position is remembered.

**Original player Behavior:**
- If you were on song #50 in a list, went to another screen, and came back, you'd still be on song #50
- Each screen remembers its last selection independently

**Implementation:**
- `selectionMemory` dictionary stores selection states per screen
- Uses `SelectionState` struct to save menu/song/detail selections
- Automatically saves when leaving a screen, restores when returning

**Example:**
```swift
// Going from Albums (selected album #10) → Album Detail
// Coming back to Albums → automatically scrolls to album #10
```

**Code Location:**
- `LyreView.swift`: `selectionMemory` state, `saveCurrentSelectionState()`, `restoreSelectionState(for:)`
- `ScrollWheelView.swift`: triggers save/restore via `navigateTo()` / `navigateBack()`

---

### 3. ✅ Hold Switch (Lock)
**What it is:** Physical switch on original player that prevented accidental button presses.

**Original player Behavior:**
- Orange indicator shows when hold is enabled
- All buttons and wheel become unresponsive
- Screen shows "Hold" indicator
- Prevented accidental playback in pocket

**Implementation:**
- Toggle switch at top-right of device
- Orange visual indicator when enabled
- Large "Hold" overlay appears on screen
- All wheel and button interactions blocked when enabled

**How to Use:**
- Tap the hold switch at the top of the device
- Orange indicator = locked
- White indicator = unlocked

**Code Location:**
- `LyreView.swift`: `HoldSwitchView` component and `isHoldEnabled` state
- `ScrollWheelView.swift`: All handlers check `if isHoldEnabled { return }`

---

### 4. ✅ Backlight Auto-Off (Configurable)
**What it is:** Screen dims after a period of inactivity to save battery.

**Original player Behavior:**
- Backlight stays on for a set duration after last interaction
- Automatically dims when idle
- Any touch brightens it again

**Implementation:**
- Screen brightness fades after the selected duration (5s / 10s / 30s / Always On)
- Background gradient changes from bright to dim
- Content opacity reduces to 60%
- Any button press or wheel rotation resets timer
- Duration is user-configurable via Settings → Backlight

**Visual Effect:**
- **Backlight ON**: Theme's `screenBackgroundLight` gradient
- **Backlight OFF**: Theme's `screenBackgroundDark` gradient
- Smooth 0.5s ease-out animation between states

**Code Location:**
- `LyreView.swift`: `isBacklightOn`, `backlightTimer`, `resetBacklightTimer()`
- `ModelsThemeSettings.swift`: `BacklightDuration` enum and `backlightDuration` property
- `LyreScreenView`: Conditional gradient colors based on backlight state

---

### 5. ✅ Repeat Mode (3 States)
**What it is:** Controls how playback repeats.

**Original player Behavior:**
- **Off**: Songs play through once
- **All**: Entire playlist/album repeats
- **One**: Current song repeats indefinitely

**Implementation:**
- Three modes: `.off`, `.all`, `.one`
- In Now Playing, scroll the wheel to highlight the Repeat row, then press the CENTER button to cycle modes
- Mode label and icon shown inline in the Now Playing screen
- Syncs with MPMusicPlayerController's repeat mode

**How to Use:**
- Navigate to Now Playing screen
- Scroll wheel to highlight the Repeat row
- Press CENTER (Select) to cycle: Off → All → One → Off...

**Visual Indicators:**
- **Off**: "Off" label
- **All**: "All" label with repeat icon
- **One**: "One" label with repeat-1 icon

**Code Location:**
- `MusicService.swift`: `RepeatMode` enum and `toggleRepeatMode()`
- `NowPlayingView.swift`: Row items for Shuffle and Repeat (index 0 and 1)
- `ScrollWheelView.swift`: `case .nowPlaying:` in `handleSelect()` — `menuSelection == 1` toggles repeat

---

### 6. ✅ Shuffle Mode (2 States)
**What it is:** Randomizes playback order.

**Original player Behavior:**
- **Off**: Songs play in list order
- **Songs**: Songs play in random order

**Implementation:**
- Two modes: `.off`, `.songs`
- In Now Playing, scroll the wheel to highlight the Shuffle row, then press the CENTER button to toggle
- Mode label shown inline in the Now Playing screen
- Syncs with MPMusicPlayerController's shuffle mode

**How to Use:**
- Navigate to Now Playing screen
- Scroll wheel to highlight the Shuffle row (top row, index 0)
- Press CENTER (Select) to toggle: Off ↔ Songs

**Visual Indicators:**
- **Off**: "Off" label with shuffle icon
- **Songs**: "Songs" label with shuffle icon

**Code Location:**
- `MusicService.swift`: `ShuffleMode` enum and `toggleShuffleMode()`
- `NowPlayingView.swift`: Row items for Shuffle and Repeat (index 0 and 1)
- `ScrollWheelView.swift`: `case .nowPlaying:` in `handleSelect()` — `menuSelection == 0` toggles shuffle

---

### 7. ✅ Track Scrubbing
**What it is:** On the Now Playing screen, the scroll wheel seeks through the current track.

**Original player Behavior:**
- Rotating the wheel on Now Playing moves the playback position
- Shows current time and remaining time
- Visual scrubber indicator on progress bar

**Implementation:**
- Clockwise rotation scrubs forward 5 seconds per tick
- Counter-clockwise rotation scrubs backward 5 seconds per tick
- "Scrubbing" label appears above the progress bar while seeking
- Scrub position dot appears on progress bar
- `musicService.startScrubbing()` / `stopScrubbing()` called on gesture start/end

**Code Location:**
- `ScrollWheelView.swift`: `scrollUp()` / `scrollDown()` in `.nowPlaying` case call `scrubBackward()` / `scrubForward()`
- `NowPlayingView.swift`: `isScrubbing` state drives the scrubbing indicator display
- `MusicService.swift`: `seek(to:)`, `startScrubbing()`, `stopScrubbing()`

---

### 8. ✅ Click Sounds
**What it is:** Optional audio click feedback when scrolling the wheel.

**Implementation:**
- System sound 1104 plays on each scroll tick when enabled
- Toggle in Settings → Click Sound (On / Off)
- Persisted in UserDefaults

**Code Location:**
- `ScrollWheelView.swift`: `AudioServicesPlaySystemSound(1104)` gated by `themeSettings.clickSoundEnabled`
- `SettingsView.swift`: `ClickSoundSelectionView`
- `ModelsThemeSettings.swift`: `clickSoundEnabled` property

---

### 9. ✅ Shake to Shuffle
**What it is:** Shake the physical device to immediately shuffle all songs.

**Behavior:**
- Only fires when Hold is disabled and songs are loaded
- Shuffles the entire songs library into a random queue
- Navigates directly to Now Playing
- Resets the backlight timer on shake

**How to Use:**
- Make sure Hold is not enabled
- Give the device a firm shake
- Playback starts from a random song

**Code Location:**
- `LyreView.swift`: `ShakeDetector` UIViewControllerRepresentable + `handleShake()`

---

### 10. ✅ Alphabet Scrubber
**What it is:** Side A–Z indicator that appears while scrolling through long lists, showing the current first letter.

**Behavior:**
- Displays a vertical A–Z strip on the right edge of list screens
- Current letter is highlighted in the theme's accent color
- Inactive letters are dimmed

**Code Location:**
- `AlphabetScrubberView.swift`: standalone view, receives `currentLetter` and `themeSettings`

---

## Behavior Details

### Now Playing Controls

On the Now Playing screen, the wheel and center button interact with Shuffle and Repeat:

| Action | Behavior |
|--------|----------|
| Scroll wheel (any screen) | Seeks backward/forward through current track |
| Scroll to Shuffle row + CENTER | Toggle Shuffle Off ↔ Songs |
| Scroll to Repeat row + CENTER | Cycle Repeat Off → All → One → Off |

The Previous and Next buttons skip tracks on **all** screens:

| Button | Behavior |
|--------|----------|
| **Previous** (any screen) | Restart track (if >3s in) or skip to previous |
| **Next** (any screen) | Skip to next track |

### Hold Switch Behavior

When Hold is enabled:
- ✅ Wheel rotation blocked
- ✅ All button presses blocked
- ✅ Shake to Shuffle blocked
- ✅ Visual feedback shows locked state
- ✅ Orange indicator visible
- ✅ Large "Hold" overlay on screen

### Backlight Behavior Timeline

```
User Action → Backlight ON (bright)
    ↓
Selected duration passes (no interaction: 5s / 10s / 30s)
    ↓
Backlight OFF (dim)
    ↓
User touches wheel/button
    ↓
Backlight ON (bright) - timer resets
```

Duration options (Settings → Backlight):
- **5 Seconds** — aggressive battery saver
- **10 Seconds** — default
- **30 Seconds** — comfortable for browsing
- **Always On** — no auto-dim

### Selection Memory Examples

**Example 1: Album Browsing**
```
1. Menu
2. Select "Albums" → Navigate to Albums screen
3. Scroll to album #20
4. Select album #20 → Navigate to Album Detail
5. Press Menu → Back to Albums screen at position #20 ✅
```

**Example 2: Multiple Navigation Levels**
```
1. Menu
2. Select "Artists" → Artists list
3. Scroll to artist #15
4. Select artist → Artist Detail
5. Scroll to album #3
6. Select album → Album Detail
7. Press Menu → Back to Artist Detail at album #3 ✅
8. Press Menu → Back to Artists list at artist #15 ✅
```

## Technical Implementation

### State Management

All player behaviors use SwiftUI's native state management:

```swift
// LyreView.swift
@State private var navigationStack: [LyreScreen] = []
@State private var selectionMemory: [LyreScreen: SelectionState] = [:]
@State private var isHoldEnabled = false
@State private var isBacklightOn = true
@State private var backlightTimer: Timer?
```

### Equatable Conformance

The `LyreScreen` enum conforms to `Equatable` to support:
- Storage in navigation stack array
- Use as dictionary keys for selection memory
- Comparison between screens

```swift
enum LyreScreen: Equatable {
    // ... cases
    
    static func == (lhs: LyreScreen, rhs: LyreScreen) -> Bool {
        // Custom equality based on screen type and IDs
    }
}
```

### Haptic Feedback

Different haptic intensities for different interactions:
- **Light**: Wheel rotation ticks, skip buttons
- **Medium**: Menu button, Play/Pause, selection changes
- **Heavy**: Center button select
- **Rigid**: Scroll boundary hits

## User Experience Enhancements

### Smooth Animations
- Backlight fade: 0.5s ease-out
- Hold switch toggle: Spring animation with 0.3s response
- Screen navigation: Instant (authentic to original player)
- Scroll position: Animated with smooth centering

### Visual Feedback
- Selection highlights: Theme accent color with glass-edge refraction
- Hold indicator: Orange color (authentic player color)
- Backlight dimming: Subtle gradient change driven by theme
- Mode icons: Clear symbols in Now Playing header

### Glass Screen Effect
The screen has a multi-layer glass simulation running at 60 fps:
- **Gyroscope caustics** — primary (top-left) and counter (bottom-right) radial highlights track device tilt
- **AR-tinted specular** — blue-green top band simulates anti-reflective coating
- **Diagonal glare stripe** — gyroscope-driven, mimics overhead light reflection
- **Animated shimmer** — slow NW→SE sweep independent of tilt (8-second loop)
- **Micro-texture grain** — 320 seeded static dots in overlay blend mode
- **Chromatic fringing** — 0.7 px red/cyan offset strokes at glass edges
- **Screen parallax** — content shifts opposite to glass highlights via `ScreenParallaxWrapper`

### Audio Feedback
- Every interaction triggers appropriate haptic
- Haptic strength varies by importance
- Boundary hits have different "feel" than selections

## Testing the Features

### Test Scenarios

**Navigation Stack:**
1. Menu → Artists → Artist Detail → Album Detail → Track
2. Press Menu 4 times, verify each screen appears in reverse order

**Selection Memory:**
1. Go to Songs, scroll to song #25
2. Navigate to Now Playing
3. Press Menu, verify you're back at song #25

**Hold Switch:**
1. Enable hold switch
2. Try rotating wheel → Should do nothing
3. Try pressing buttons → Should do nothing
4. Try shaking device → Should do nothing
5. Disable hold switch → Should work again

**Backlight:**
1. Interact with device
2. Wait for the configured duration without touching
3. Verify screen dims
4. Touch wheel → Verify screen brightens
5. Change duration in Settings → Backlight, verify new timing

**Shake to Shuffle:**
1. Ensure Hold is disabled
2. Shake the device firmly
3. Verify songs shuffle and Now Playing opens

**Repeat/Shuffle:**
1. Navigate to Now Playing
2. Scroll wheel to highlight the Shuffle row → Press CENTER to toggle shuffle
3. Scroll wheel to highlight the Repeat row → Press CENTER to cycle repeat modes
4. Verify mode labels update in the rows

**Track Scrubbing:**
1. Navigate to Now Playing while a song is playing
2. Rotate the wheel clockwise → Verify playback position jumps forward
3. Rotate the wheel counter-clockwise → Verify playback position jumps backward
4. Verify "Scrubbing" indicator appears above the progress bar while scrolling

## Conclusion

These implementations bring authentic classic scroll-wheel player behavior to the modern SwiftUI app, creating a nostalgic and intuitive user experience. Every detail — from the hold switch to the configurable backlight timing — is designed to feel like using a real player from 2006, while adding modern polish like glass reflections, gyroscope parallax, and shake-to-shuffle.

The combination of navigation memory, selection persistence, and context-sensitive controls makes the app feel like a genuine piece of Apple hardware history, modernized for iOS.
