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

### 11. ✅ Queue (Swipe Right on Center)
**What it is:** Adding songs to a play queue without leaving the list you are browsing, plus a screen for rearranging them.

**Behavior:**
- Swiping right on the center button queues **whatever the highlighted row stands for** —
  a song on a song list, a whole album on the Albums list, a whole playlist on the
  Playlists list
- New tracks always land at the *bottom* of the queue, so repeated swipes build a running order
- A collection keeps its own order, and goes in as one queue edit
- With nothing playing, what was added starts playing rather than waiting
- A banner confirms the action on the screen for ~1.6 s (the wheel gives only a haptic)
- Works on Songs, Recently Added, Recently Played, Albums, Playlists, album track lists,
  playlist track lists, and podcast episode lists; anywhere else the wheel just gives
  the boundary "bump"

**From the Artwork Carousel.** The gatefold liner is touch, not wheel, but the gesture
is the same: tap a row to play it, swipe it right to queue it. The row's number turns
into a tick for a moment, and a toast confirms the add — the carousel is a
`fullScreenCover`, so the screen banner the wheel uses is not on top of it.

One trade-off worth knowing: a horizontal drag started *on a liner row* now queues
instead of scrubbing the gatefold hinge. Drags anywhere else on the spread still scrub.
The swipe is a plain `.gesture` rather than a high-priority one specifically so vertical
drags still reach the enclosing ScrollView and a long tracklist keeps scrolling.

**Collections that go in partly.** An album or playlist can contain tracks with nothing
playable behind them (Apple Music catalogue content, undownloaded cloud items). Those
are skipped rather than failing the whole add, and the banner says so — "Queued 9 of 12:
Abbey Road" — because a silently half-queued album looks like lost songs. A single add
is also capped at `maxTracksPerAdd` (200): every item in a queue transaction is carried
across to the media server, and an unbounded add would repeat the hang that queueing a
whole library caused.

**Reordering (Menu → Queue):**
| Action | Behavior |
|--------|----------|
| Scroll wheel | Move the cursor through Up Next |
| CENTER on a row | Pick the song up (dashed outline + up/down glyph) |
| Scroll wheel while carrying | Carry the song through the list |
| CENTER / MENU while carrying | Put the song down and republish the order |
| Swipe right on CENTER | Remove the highlighted song from the queue |
| Scroll up past the first song → CENTER | Clear the whole queue |

**Clear Queue** is a row that sits one step *above* the first song rather than taking
index 0, so every other cursor position still maps straight onto an Up Next offset
(`QueueView.clearRowOffset == -1`) and the cursor never opens the screen sitting on a
destructive action. Clearing empties Up Next, leaves the current track playing, and
also forgets `queueSourceTracks` — otherwise the refill would put the rest of the
library straight back.

**Which player, and why it matters:**
Playback runs through `MPMusicPlayerController.applicationQueuePlayer`, not the system
player. The system player drives the Music app on the app's behalf, and that made a
queue impossible to keep: an appended item went into the Music app's queue, which could
be superseded, and when it ran out the Music app continued with its own autoplay pick —
so a queued song never played and an unrelated one did. It also inherited the Music
app's shuffle setting, which made the player choose its own next track.

The application queue player owns its queue outright and is the only player that can
edit one **in place**, through `perform(queueTransaction:)`. Add, remove and reorder are
therefore single atomic edits — `insert(_:after:)` / `remove(_:)` — and never interrupt
playback. `setQueue` is now only used to start fresh playback.

What this costs, all of it deliberate:
- Playback stops when the app is terminated, and no longer continues the Music app's
  session or appears in it.
- The `audio` background mode (Info.plist `UIBackgroundModes`) is required, or playback
  stops when the app is backgrounded.
- Remote control events need no code: MediaPlayer routes lock screen, headset and
  CarPlay commands to the player itself for application players.

**The queue is a window, not the whole list.**
An application queue player serialises every item of its queue across to the media
server. Handing it a whole library (~6,400 songs) timed the XPC connection out
(`_establishConnectionIfNeeded timeout [ping did not pong]`) and blocked the main
thread for ~25 s on each queue call, which froze the app after selecting a song. So:

- `play(tracks:startingAt:)` queues `queueHistorySize` (25) tracks behind the chosen
  one and `queueWindowSize` (150) ahead of it, and remembers the full list as
  `queueSourceTracks`.
- `refillQueueIfNeeded()` adds the next 150 once Up Next drops to
  `queueRefillThreshold` (25), and the same transaction drops tracks more than 25
  behind the current one — otherwise the queue would grow back to library size.
- Media items are resolved per window rather than up front, which also stops the
  per-track `MPMediaQuery` fallback from running thousands of times before playback
  starts.

One consequence worth knowing: "bottom of the queue" means the bottom of the loaded
window, so a song added while playing a large library lands ~150 tracks away rather
than ~6,400. Refills are inserted after it, so it keeps its place.

Three rules keep the model and the player agreeing:
- Every transaction reports the resulting queue, and `syncQueueModel(with:)` rebuilds
  the model from it rather than trusting the edit landed as asked. Existing `AppTrack`s
  are matched by persistent ID so MusicKit artwork is not downgraded.
- Only the **last** in-flight transaction rewrites the model
  (`pendingQueueTransactions`), so queueing several songs quickly doesn't let an earlier
  stale snapshot drop the later ones.
- Setting a whole new queue makes the player briefly report a missing or stale
  now-playing item. Those reports are ignored for a few seconds
  (`queueSettlingUntil`), otherwise applying a queue immediately destroys the model
  that produced it. A nil now-playing item never clears the queue.

Shuffle is still read back off the player (`syncPlaybackModesFromPlayer`) because the
framework can change it from the lock screen or CarPlay, and both modes are pinned at
startup so an untouched player's `.default` ("whatever the user prefers") cannot start
the first queue off shuffled. With shuffle on the player picks its own next track, and
the Queue screen says so rather than looking broken.

**Code Location:**
- `ModelsPlaybackQueue.swift`: `PlaybackQueue` — Up Next, `moveUpNext`, `removeUpNext`, `advanceCurrent`
- `MusicService.swift`: `addToQueue()`, `reorderUpNext()`, `removeFromQueue()`, `applyQueueOrder()`
- `ScrollWheelView.swift`: `handleCenterDragChanged/Ended()` split tap from swipe; `handleCenterSwipeRight()`, `moveCarriedQueueRow()`, `dropCarriedQueueRow()`
- `QueueView.swift`: the Queue screen
- `LyreView.swift`: `queueMoveOffset` (carried row) and `showQueueBanner()`

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
