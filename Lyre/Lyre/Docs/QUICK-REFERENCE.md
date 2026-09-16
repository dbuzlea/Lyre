# Quick Reference: player Controls & Behaviors

## 📱 Device Layout

```
┌─────────────────────────────────┐
│         [HOLD SWITCH]           │  ← Toggle lock (orange = locked)
├─────────────────────────────────┤
│                                 │
│   ┌─────────────────────────┐   │
│   │                         │   │
│   │      player Screen        │   │  ← Auto-dims after configured duration
│   │   [Glass Overlay]       │   │    (5s / 10s / 30s / Always On)
│   │                         │   │
│   │  ┌──────────────────┐   │   │
│   │  │  Content Area    │   │   │
│   │  │  (Lists, Album   │   │   │
│   │  │   Art, Menus)    │   │   │
│   │  └──────────────────┘   │   │
│   └─────────────────────────┘   │
│                                 │
│          ┌────────┐             │
│         ╱  MENU    ╲            │  ← MENU button
│        │     ▲     │            │    (Back navigation)
│   ◄───┼──┼─────┼──┼───►        │
│  PREV │    │ ● │    │ NEXT     │  ← Context-sensitive
│        │     ▼     │            │
│         ╲  PLAY   ╱             │  ← PLAY/PAUSE
│          └────────┘              │
│     (Scroll Wheel)               │
└─────────────────────────────────┘
```

---

## 🎮 Button Functions

### MENU Button (Top)
- **Press once**: Go back to previous screen
- **Keeps pressing**: Navigate back through history
- **On Main Menu**: Does nothing (already at root)

### CENTER Button (Select)
- **On Menu Items**: Select and navigate forward
- **On Songs**: Play selected song
- **On Albums/Artists**: Open detail view
- **On Now Playing (Shuffle row)**: Toggle Shuffle Off ↔ Songs
- **On Now Playing (Repeat row)**: Cycle Repeat Off → All → One

### PLAY/PAUSE Button (Bottom)
- **Anywhere**: Toggle playback
- **Works globally**: Don't need to be on Now Playing screen

### PREVIOUS Button (Left)
| Screen | Action |
|--------|--------|
| **All Screens** | ⏮️ Restart track (if >3s in) or skip to previous |

### NEXT Button (Right)
| Screen | Action |
|--------|--------|
| **All Screens** | ⏭️ Skip to Next Track |

### CLICK WHEEL (Circular Gesture)
- **Clockwise**: Scroll down / Next item
- **Counter-clockwise**: Scroll up / Previous item
- **On Now Playing — Clockwise**: Seek forward 5s per tick
- **On Now Playing — Counter-clockwise**: Seek backward 5s per tick
- **Haptic feedback**: Light ticks as you scroll

### SHAKE (Device Gesture)
- **Anywhere (Hold off)**: Shuffle all songs → jump to Now Playing

---

## 🔒 Hold Switch Behavior

```
┌──────────────┐         ┌──────────────┐
│              │         │   LOCKED     │
│   UNLOCKED   │  Tap    │              │
│   ⚪ White   │  ────►  │  🟠 Orange   │
│              │         │              │
│  All Controls│         │   Buttons    │
│    Active    │         │   Disabled   │
└──────────────┘         └──────────────┘
                              │
                         Shows "Hold"
                         overlay on
                         screen
```

**When Locked:**
- ❌ Wheel doesn't scroll
- ❌ Buttons don't respond
- ❌ Shake to Shuffle blocked
- ✅ Prevents pocket dialing
- ✅ Orange indicator visible

---

## 💡 Backlight Behavior

```
User Interaction
      │
      ▼
┌─────────────┐
│ BACKLIGHT   │
│    ON       │  ← Bright screen (glass glare active)
│  (Bright)   │
└─────────────┘
      │
      │ Configured duration (5s / 10s / 30s)
      │ (no touch)        or Never if Always On
      ▼
┌─────────────┐
│ BACKLIGHT   │
│    OFF      │  ← Dimmed screen (60% opacity)
│   (Dim)     │
└─────────────┘
      │
      │ Any touch
      ▼
┌─────────────┐
│ BACKLIGHT   │
│    ON       │  ← Bright again!
│  (Bright)   │
└─────────────┘
```

**Configurable Duration** — Settings → Backlight:
| Option | Behavior |
|--------|----------|
| 5 Seconds | Dims quickly — aggressive battery saver |
| 10 Seconds | Default |
| 30 Seconds | Comfortable for browsing |
| Always On | Never auto-dims |

---

## 🔁 Repeat Mode (3 States)

Press **CENTER** on the Repeat row in Now Playing to cycle:

```
   ┌──────────┐
   │   OFF    │
   │ (no icon)│
   └────┬─────┘
        │
   Press Center on Repeat row
        │
        ▼
   ┌──────────┐
   │   ALL    │
   │    ↻     │
   └────┬─────┘
        │
   Press Center on Repeat row
        │
        ▼
   ┌──────────┐
   │   ONE    │
   │   ↻₁     │
   └────┬─────┘
        │
   Press Center on Repeat row
        │
        └──────► (back to OFF)
```

---

## 🔀 Shuffle Mode (2 States)

Press **CENTER** on the Shuffle row in Now Playing to toggle:

```
   ┌──────────┐         ┌──────────┐
   │   OFF    │  Center │  SONGS   │
   │ (no icon)│  ──────►│    🔀    │
   └──────────┘         └──────────┘
        ▲                     │
        │                     │
        └──────── Center ─────┘
```

---

## 📚 Navigation Stack Example

```
User Journey:
Menu → Artists → Artist Detail → Album Detail → Now Playing

Navigation Stack Visualization:

Step 1: At Menu
┌──────┐
│ Menu │ ← Current
└──────┘
Stack: []

Step 2: Select "Artists"
┌──────────┐
│ Artists  │ ← Current
└──────────┘
┌──────┐
│ Menu │
└──────┘
Stack: [Menu]

Step 3: Select an Artist
┌───────────────┐
│ Artist Detail │ ← Current
└───────────────┘
┌──────────┐
│ Artists  │
└──────────┘
┌──────┐
│ Menu │
└──────┘
Stack: [Menu, Artists]

Step 4: Select an Album
┌───────────────┐
│ Album Detail  │ ← Current
└───────────────┘
┌───────────────┐
│ Artist Detail │
└───────────────┘
┌──────────┐
│ Artists  │
└──────────┘
┌──────┐
│ Menu │
└──────┘
Stack: [Menu, Artists, Artist Detail]

Step 5: Select a Track
┌──────────────┐
│ Now Playing  │ ← Current
└──────────────┘
┌───────────────┐
│ Album Detail  │
└───────────────┘
┌───────────────┐
│ Artist Detail │
└───────────────┘
┌──────────┐
│ Artists  │
└──────────┘
┌──────┐
│ Menu │
└──────┘
Stack: [Menu, Artists, Artist Detail, Album Detail]

Pressing MENU 4 Times:
Press 1 → Album Detail
Press 2 → Artist Detail  
Press 3 → Artists
Press 4 → Menu
```

---

## 💾 Selection Memory Example

```
Scenario: Browsing Songs

1. Go to Songs
2. Scroll to Song #42 ← Position saved!
   ┌────────────────┐
   │ Song #40       │
   │ Song #41       │
   │ ▶ Song #42 ◀   │ ← You are here
   │ Song #43       │
   │ Song #44       │
   └────────────────┘

3. Select Song #42 → Navigate to Now Playing
   
4. Press MENU to go back

5. You return to Songs list:
   ┌────────────────┐
   │ Song #40       │
   │ Song #41       │
   │ ▶ Song #42 ◀   │ ← Still here! ✓
   │ Song #43       │
   │ Song #44       │
   └────────────────┘
```

**Works for every screen independently!**

---

## 🎵 Now Playing Screen Special Features

```
┌───────────────────────────────────┐
│ ◄ Now Playing                     │
├───────────────────────────────────┤
│        ┌──────────────┐           │
│        │  Album Art   │           │
│        └──────────────┘           │
│       "Song Title"                │
│       Artist Name                 │
│  ▶ Playing                        │
│  ━━━━━━━━━━━━━━━━━━  0:45 / 3:12  │ ← Progress bar
│                                   │
│  🔀 Shuffle    Off                │ ← Row 0 (scroll here)
│  ↻  Repeat     Off                │ ← Row 1 (scroll here)
└───────────────────────────────────┘

Controls:
• WHEEL = Seek forward/backward through track
• CENTER on Shuffle row = Toggle Shuffle Off ↔ Songs
• CENTER on Repeat row = Cycle Repeat Off → All → One
• PLAY/PAUSE = Pause/Play
• PREVIOUS = Restart or skip to previous track
• NEXT = Skip to next track
• MENU = Go back
```

---

## 🎯 Quick Tips

### Tip 1: Deep Navigation
Navigate as deep as you want! The Menu button will always take you back through your exact path.

### Tip 2: Position Memory
Your scroll position is saved for every screen. Navigate freely without losing your place!

### Tip 3: Lock It Up
Enable Hold before putting the device in your pocket to prevent accidental playback.

### Tip 4: Backlight Duration
Adjust the auto-dim timer in Settings → Backlight (5s / 10s / 30s / Always On) to match your preference.

### Tip 5: Modes on the Go
You don't need to go to settings to change repeat/shuffle. On Now Playing, scroll to the Shuffle or Repeat row and press the center button.

### Tip 6: Scrub Through Tracks
On the Now Playing screen, rotate the wheel to seek backward or forward through the current track. A "Scrubbing" label appears on the progress bar while you're seeking.

### Tip 7: Shake to Shuffle
Give the device a firm shake (Hold must be off) to instantly shuffle your entire library and jump to Now Playing.

### Tip 8: cover browser
Rotate to landscape while on Albums, Playlists, or Podcasts screens to enter cover browser. Rotate back to portrait to dismiss.

---

## 🎨 Visual Indicators

| Indicator | Meaning |
|-----------|---------| 
| 🔵 Blue highlight | Selected item |
| 🟠 Orange switch | Hold enabled |
| ↻ Repeat icon | Repeat all |
| ↻₁ Repeat-1 icon | Repeat one |
| 🔀 Shuffle icon | Shuffle on |
| 🔋 Battery icon | (Always shown) |
| ◄ Back chevron | Can go back |
| ► Play/Pause | Playback state |
| Glass glare | Screen glass overlay (gyroscope-driven) |

---

## ⚡ Haptic Feedback Guide

Different vibrations for different actions:

| Action | Haptic Type | Intensity |
|--------|-------------|-----------|
| Wheel rotation | Light | Subtle ticks |
| Item selection | Medium | Noticeable |
| Center button | Heavy | Strong |
| Boundary hit | Rigid | Sharp, weak |
| Mode change | Medium | Clear |

---

## 🎓 Learning Curve

**Easy to Learn:**
1. Wheel scrolls
2. Center selects
3. Menu goes back
4. Play/Pause works

**Advanced Features:**
5. Hold switch locks everything
6. Wheel seeks through track on Now Playing
7. Center button toggles shuffle/repeat on Now Playing rows
8. Selection memory keeps your place
9. Configurable backlight duration
10. Shake to shuffle all songs

**Just like the real player - intuitive but powerful! 🎧**
