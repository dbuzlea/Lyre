# Lyre

A SwiftUI iOS app for listening to your Apple Music library through a touch-based scroll wheel — navigation stack with selection memory, 30 finishes, and a retro LCD aesthetic.

## Features

### Core Experience
- **Touch-Based Scroll Wheel** — Circular drag gesture for scrolling; tap zones for Menu, Play/Pause, Previous, Next, and center Select
- **Navigation Stack** — The Menu zone acts as a true back button, tracking full navigation history
- **Selection Memory** — Every screen remembers your scroll position when you return to it
- **Hold Switch** — Toggle at top-right of the device body; orange indicator locks all input
- **Configurable Backlight** — Auto-off timer selectable: 5s / 10s / 30s / Always On; any touch wakes it
- **Haptic Feedback** — Light ticks on scroll, medium on selection, heavy on center press, rigid on boundary hits
- **Shake to Shuffle** — Shake the device to instantly shuffle all songs and jump to Now Playing

### Visual Polish
- **Glass Screen Overlay** — Gyroscope-driven tinted caustics, animated shimmer, micro-texture grain, and chromatic fringing simulate real glass
- **Screen Parallax** — Content shifts counter to device tilt via CoreMotion, reinforcing the depth gap between display and glass
- **Selection Bar Refraction** — Highlighted rows show glass-edge light refraction for a physical feel

### Playback
- **Apple Music Library** — Browse and play Songs, Albums, Artists, Playlists, and Podcasts via MusicKit + MediaPlayer
- **Track Scrubbing** — Rotate the wheel on Now Playing to seek ±5 seconds per tick; scrubbing indicator shown on the progress bar
- **Repeat Mode** — Off / All / One, toggled via Center button on the Repeat row in Now Playing
- **Shuffle Mode** — Off / Songs, toggled via Center button on the Shuffle row in Now Playing
- **Global Play/Pause** — Works from any screen, not just Now Playing
- **Cover Browser** — Rotate to landscape to browse Albums, Playlists, or Podcasts by cover art

### Finishes — 30 Built-In
| Family | Finishes |
|--------|----------|
| Signature | Porcelain, Onyx, Sterling, Crimson, Monochrome |
| Pebble | Silver, Gold, Blue, Pink, Green |
| Slim | Slim, Silver, Black, Graphite, Blue, Pink, Purple, Green, Yellow, Orange, Red |
| Clip | Silver, Blue, Pink, Green, Orange, Purple, Gold |
| Retro | Phosphor, Spectrum |

Each finish styles the body gradient, screen background, text colors, highlight color, and scroll wheel.

### Settings
| Setting | Options |
|---------|---------|
| Theme | 30 built-in finishes |
| Screen Size | Auto (match finish) + 6 manual presets (Tiny → Extra Large) |
| Highlight Color | Default or 26 finish colors |
| Scroll Sensitivity | Low / Medium / High |
| Click Sound | On / Off |
| Backlight | 5 Seconds / 10 Seconds / 30 Seconds / Always On |
| About | App version info |

---

## Requirements

- iOS 17.6+
- Xcode 27.0+
- Apple Developer account (for the MusicKit capability)
- Physical iOS device (MusicKit requires a real device for full library access)
- An Apple Music subscription with a non-empty library

---

## Setup

### 1. Enable MusicKit

1. Open `Lyre.xcodeproj` in Xcode
2. Select the **Lyre** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability** and add **MusicKit**
5. Set your Team in Signing

The App ID `com.pinkhatcreations.lyreapp` must also have the MusicKit service enabled in the Apple Developer portal, or library requests fail at runtime.

### 2. Usage Description

`NSAppleMusicUsageDescription` is supplied via the `INFOPLIST_KEY_NSAppleMusicUsageDescription` build setting — not the `Info.plist` file. No microphone or other permissions are used.

### 3. Build and Run

1. Select a physical iOS device as the run destination
2. Build and run (`⌘R`)
3. Grant Apple Music permission when prompted
4. Navigate with the scroll wheel

---

## How to Use

### Scroll Wheel

| Gesture / Zone | Action |
|------------------|--------|
| Circular drag — clockwise | Scroll down |
| Circular drag — counter-clockwise | Scroll up |
| Tap top zone | Go back |
| Tap bottom zone | Toggle Play/Pause |
| Tap left zone | Restart track or skip to previous |
| Tap right zone | Skip to next track |
| Center circle | Select / confirm |

### Now Playing Screen

| Action | How |
|--------|-----|
| Seek forward | Clockwise wheel rotation |
| Seek backward | Counter-clockwise wheel rotation |
| Toggle Shuffle | Scroll to Shuffle row → press Center |
| Cycle Repeat | Scroll to Repeat row → press Center |

### Main Menu Structure

```
Menu
├── Now Playing
├── Songs
├── Recently Added
├── Recently Played
├── Albums
├── Artists
├── Playlists
├── Podcasts
└── Settings
    ├── Theme
    ├── Screen Size
    ├── Highlight Color
    ├── Scroll Sensitivity
    ├── Click Sound
    ├── Backlight
    └── About
```

### Cover Browser

Rotate the device to landscape while browsing Albums, Playlists, or Podcasts to enter the cover browser. Swipe left/right to browse covers, tap to select.

### Shake to Shuffle

Shake the device from any screen (with Hold disabled) to immediately shuffle all songs and navigate to Now Playing.

---

## Architecture

```
Lyre/
├── Models/
│   ├── AppMusicModels.swift       # AppTrack, AppAlbum, AppArtist wrappers
│   ├── ModelsLyreScreen.swift     # LyreScreen enum (all navigation states)
│   ├── ModelsSelectionState.swift # SelectionState struct for memory
│   ├── ModelsRepeatMode.swift     # RepeatMode enum
│   ├── ModelsShuffleMode.swift    # ShuffleMode enum
│   ├── LyreTheme.swift            # Theme colors + factory
│   ├── ThemeLyreThemeStyle.swift  # 30 finish cases + defaultScreenSize
│   ├── ThemeScreenSize.swift      # 6 screen size presets
│   └── LyreColors.swift           # Finish color palette
├── Services/
│   ├── MusicService.swift         # MusicKit + MediaPlayer integration
│   ├── AppHelpers.swift           # Shared utilities (time formatting, etc.)
│   └── AppMetrics.swift           # MetricKit crash/hang/performance monitoring
└── ViewModels/
    ├── LyreView.swift             # Root view — state, layout, orientation, shake
    ├── ScrollWheelView.swift       # Wheel gestures, button handlers, navigation logic
    ├── LyreScreenView.swift       # Screen content router
    ├── ModelsThemeSettings.swift  # ThemeSettings + BacklightDuration + ScrollSensitivity
    ├── SelectionHighlightModifier.swift  # Glass-edge refraction on selection bars
    ├── NowPlayingView.swift       # Now Playing screen
    ├── MainMenuView.swift         # Main menu
    ├── SongListView.swift         # Songs list
    ├── AlbumListView.swift        # Albums list
    ├── AlbumDetailView.swift      # Album track list
    ├── ArtistListView.swift       # Artists list
    ├── ArtistDetailView.swift     # Artist album list
    ├── PlaylistListView.swift     # Playlists list
    ├── PlaylistDetailView.swift   # Playlist track list
    ├── PodcastListView.swift      # Podcasts list
    ├── PodcastDetailView.swift    # Podcast episode list
    ├── SettingsView.swift         # All settings sub-screens
    ├── AlphabetScrubberView.swift # A–Z side scrubber for long lists
    ├── ArtworkCarouselView.swift        # Landscape cover browser
    └── HoldSwitchView.swift       # Hold switch toggle
```

> **Note on naming:** several internal types still carry an `Lyre`-prefixed name
> (`LyreView`, `LyreTheme`, `LyreThemeStyle`, `LyreScreen`, `LyreColors`), and the
> Xcode target and directory are still `Lyre`. These are internal identifiers only
> — they appear nowhere in the UI or in the shipped bundle metadata. The user-facing
> brand is **Lyre** throughout. Renaming them is safe but purely cosmetic.

### Key Design Decisions

- **No Combine** — All async work uses Swift async/await
- **MusicKit for the catalogue**, **MediaPlayer (`MPMusicPlayerController.systemMusicPlayer`) for playback** — both handled in `MusicService`. Because playback runs in the system music process, the app declares no `audio` background mode
- **Navigation is a stack** (`[LyreScreen]`) managed in `LyreView`, operated by `ScrollWheelView` via bindings
- **Selection memory** is a `[LyreScreen: SelectionState]` dictionary — O(1) save/restore on every screen transition
- **ThemeSettings** is an `@Observable` class held in `LyreView` and passed down as a reference — changes propagate immediately
- **Glass overlay** (`ScreenGlassView`) is isolated to its own view so only it re-renders at 60 fps on gyroscope updates
- **MetricKit** (`AppMetrics`) is registered on launch and logs crash/hang diagnostics to the unified log

---

## Adding a New Finish

See [`Docs/ADD-NEW-THEME-GUIDE.md`](Docs/ADD-NEW-THEME-GUIDE.md) for a step-by-step guide. The short version:

1. Add a case to `LyreThemeStyle` in `Models/ThemeLyreThemeStyle.swift`
2. Add a `case` in `LyreTheme.theme(for:)` in `Models/LyreTheme.swift`
3. Build — your finish appears in Settings → Theme automatically

Renaming an existing finish's raw value requires a matching entry in
`ThemeSettings.migratedStyle(from:)` so existing installs keep their selection.

---

## Troubleshooting

**"No songs in library"**
- Grant Apple Music permission in Settings → Privacy & Security → Media & Apple Music
- Make sure your Apple Music library has songs (local files or iCloud Music Library)

**Scroll wheel not responding**
- Swipe in a circular arc around the outer ring, not the center button
- Adjust sensitivity in Settings → Scroll Sensitivity

**Playback doesn't start**
- MusicKit requires an active internet connection for streamed content
- Verify you're signed in to Apple Music in Settings

**Hold switch stuck**
- Tap the orange toggle at the top of the device body to unlock

**Screen stays dim**
- Go to Settings → Backlight and increase the duration or set it to Always On

---

## Documentation

All feature docs are in [`Docs/`](Docs/):

| File | Contents |
|------|----------|
| `CLICK-WHEEL-BEHAVIORS.md` | Complete reference for all wheel and navigation behaviors |
| `QUICK-REFERENCE.md` | Controls cheat sheet |
| `ADD-NEW-THEME-GUIDE.md` | How to add a custom finish |
| `BUTTON-LAYOUT-REFERENCE.md` | Scroll wheel geometry and specs |
| `SELECTION-MEMORY-ARCHITECTURE.md` | How navigation memory works |

---

## License

This project is for educational and personal use. Apple Music and MusicKit are
trademarks of Apple Inc. Lyre is not affiliated with or endorsed by Apple.

## Credits

Built with SwiftUI, MusicKit, MediaPlayer, CoreMotion, and MetricKit.
