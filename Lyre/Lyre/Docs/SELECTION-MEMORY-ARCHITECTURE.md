# Selection Memory Architecture

## Visual Flow Diagram

### Forward Navigation (Center Button)

```
┌─────────────────────────────────────────────────────────┐
│                    USER PRESSES CENTER                   │
│                   (handleSelect called)                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 1: Save Current Screen's Selection State          │
│  ─────────────────────────────────────────────          │
│  saveSelectionState()                                    │
│                                                          │
│  selectionMemory[.songs] = SelectionState(              │
│      menuSelection: 0,                                   │
│      songSelection: 25,  ← Current scroll position      │
│      detailSelection: 0                                  │
│  )                                                       │
│                                                          │
│  Console: 💾 Saved selection for songs: song=25         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 2: Push Current Screen to Navigation Stack        │
│  ───────────────────────────────────────────────        │
│  navigationStack.append(.songs)                          │
│                                                          │
│  Stack now: [.menu, .songs]                             │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 3: Change to New Screen                           │
│  ────────────────────────────                           │
│  currentScreen = .nowPlaying                             │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 4: Restore Selection for New Screen               │
│  ────────────────────────────────────────               │
│  restoreSelectionState(for: .nowPlaying)                 │
│                                                          │
│  if let saved = selectionMemory[.nowPlaying] {           │
│      Use saved position                                  │
│  } else {                                                │
│      Start at default (0)                                │
│  }                                                       │
│                                                          │
│  Console: 📂 Restored selection for nowPlaying          │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌──────────────────────┐
              │   USER SEES SCREEN   │
              │  At saved position   │
              └──────────────────────┘
```

---

### Backward Navigation (Menu Button)

```
┌─────────────────────────────────────────────────────────┐
│                    USER PRESSES MENU                     │
│                  (handleMenuButton called)               │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 1: Save Current Screen's Selection State          │
│  ─────────────────────────────────────────────          │
│  saveSelectionState()                                    │
│                                                          │
│  selectionMemory[.nowPlaying] = SelectionState(          │
│      menuSelection: 0,                                   │
│      songSelection: 25,                                  │
│      detailSelection: 0                                  │
│  )                                                       │
│                                                          │
│  Console: 💾 Saved selection for nowPlaying             │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 2: Pop Previous Screen from Stack                 │
│  ──────────────────────────────────────                 │
│  let previousScreen = navigationStack.removeLast()       │
│                                                          │
│  previousScreen = .songs                                 │
│  Stack now: [.menu]                                      │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 3: Change to Previous Screen                      │
│  ─────────────────────────────                          │
│  currentScreen = .songs                                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  STEP 4: Restore Selection for Previous Screen          │
│  ─────────────────────────────────────────────          │
│  restoreSelectionState(for: .songs)                      │
│                                                          │
│  if let saved = selectionMemory[.songs] {                │
│      songSelection = 25  ← Restore saved position       │
│  }                                                       │
│                                                          │
│  Console: 📂 Restored selection for songs: song=25      │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌──────────────────────┐
              │   USER SEES SCREEN   │
              │  At song #25 again!  │
              └──────────────────────┘
```

---

## Memory Structure Over Time

### Scenario: Menu → Songs → Now Playing → Back → Back

```
INITIAL STATE
─────────────
currentScreen: .menu
navigationStack: []
selectionMemory: {}

           ┌─────────────────┐
           │  SELECT "SONGS" │
           └─────────────────┘
                    │
                    ▼

AFTER SELECTING SONGS
─────────────────────
currentScreen: .songs
navigationStack: [.menu]
selectionMemory: {
    .menu: SelectionState(menuSelection: 1, ...)
}

           ┌─────────────────┐
           │ SCROLL TO #25   │
           └─────────────────┘
                    │
                    ▼

AFTER SCROLLING (no state change until navigation)
──────────────────────────────────────────────────
currentScreen: .songs
navigationStack: [.menu]
selectionMemory: {
    .menu: SelectionState(menuSelection: 1, ...)
}
songSelection: 25  (in UI state, not saved yet)

           ┌─────────────────┐
           │  SELECT SONG    │
           └─────────────────┘
                    │
                    ▼

AFTER PLAYING SONG (NOW PLAYING)
────────────────────────────────
currentScreen: .nowPlaying
navigationStack: [.menu, .songs]
selectionMemory: {
    .menu: SelectionState(menuSelection: 1, ...),
    .songs: SelectionState(songSelection: 25, ...)  ← NOW SAVED!
}

           ┌─────────────────┐
           │   PRESS MENU    │
           └─────────────────┘
                    │
                    ▼

AFTER MENU (BACK TO SONGS)
──────────────────────────
currentScreen: .songs
navigationStack: [.menu]
selectionMemory: {
    .menu: SelectionState(menuSelection: 1, ...),
    .songs: SelectionState(songSelection: 25, ...),
    .nowPlaying: SelectionState(songSelection: 25, ...)
}
songSelection: 25  ← RESTORED!

           ┌─────────────────┐
           │   PRESS MENU    │
           └─────────────────┘
                    │
                    ▼

AFTER MENU (BACK TO MENU)
─────────────────────────
currentScreen: .menu
navigationStack: []
selectionMemory: {
    .menu: SelectionState(menuSelection: 1, ...),
    .songs: SelectionState(songSelection: 25, ...),
    .nowPlaying: SelectionState(songSelection: 25, ...)
}
menuSelection: 1  ← RESTORED!
```

---

## Code Flow

### saveSelectionState() Function

```swift
private func saveSelectionState() {
    // Create snapshot of current selections
    let state = SelectionState(
        menuSelection: menuSelection,      // Main menu or list items
        songSelection: songSelection,       // Songs list
        detailSelection: detailSelection    // Detail views (tracks, albums)
    )
    
    // Store in dictionary using current screen as key
    selectionMemory[currentScreen] = state
    
    // Log for debugging
    print("💾 Saved selection for \(currentScreen): menu=\(menuSelection), song=\(songSelection), detail=\(detailSelection)")
}
```

**When Called:**
- ✅ Before navigating forward (in `handleSelect()`)
- ✅ Before navigating backward (in `handleMenuButton()`)

---

### restoreSelectionState(for:) Function

```swift
private func restoreSelectionState(for screen: LyreScreen) {
    if let savedState = selectionMemory[screen] {
        // Found saved state - restore it
        menuSelection = savedState.menuSelection
        songSelection = savedState.songSelection
        detailSelection = savedState.detailSelection
        
        print("📂 Restored selection for \(screen): ...")
    } else {
        // No saved state - use smart defaults
        switch screen {
        case .menu:
            menuSelection = 0
            songSelection = 0
            detailSelection = 0
        case .songs, .nowPlaying:
            menuSelection = 0
            detailSelection = 0
            // Keep songSelection
        // ... more cases
        }
        
        print("🆕 No saved state for \(screen), using defaults")
    }
}
```

**When Called:**
- ✅ After navigating forward (in `handleSelect()`)
- ✅ After navigating backward (in `handleMenuButton()`)

---

## State Variables Explained

### menuSelection
**Used For:** 
- Main menu items (Now Playing, Songs, Albums, etc.)
- Album list position
- Artist list position  
- Playlist list position

**Example:**
```swift
// Menu screen
menuSelection = 2  // User selected "Albums"

// Albums screen
menuSelection = 15  // User is on album #15
```

### songSelection
**Used For:**
- Songs list position

**Example:**
```swift
// Songs screen
songSelection = 42  // User is on song #42
```

### detailSelection
**Used For:**
- Album detail track position
- Playlist detail track position
- Artist detail album position

**Example:**
```swift
// Album detail screen
detailSelection = 8  // User is on track #8

// Artist detail screen
detailSelection = 3  // User is on album #3 of this artist
```

---

## Dictionary Key Design

The `selectionMemory` dictionary uses `LyreScreen` as the key, which is `Hashable`:

```swift
// Different screen types create different keys
selectionMemory[.menu]                    // Unique key
selectionMemory[.songs]                   // Unique key
selectionMemory[.albums]                  // Unique key
selectionMemory[.albumDetail(album1)]     // Key based on album1.id
selectionMemory[.albumDetail(album2)]     // DIFFERENT key (album2.id)
```

### Why This Works:
1. **Simple screens** (menu, songs, etc.) - Each has one instance
2. **Detail screens** - Keyed by the associated item's ID
3. **Same album** opened multiple times - Restores to same track
4. **Different albums** - Each has independent memory

---

## Example Walkthrough

### User Journey: Browse Albums

```
Step 1: At Menu
───────────────
Screen: .menu
menuSelection: 0
Memory: {}

User scrolls down to "Albums" (position 2)
menuSelection: 2

        ↓ Press Center

Step 2: Save Menu State, Open Albums
────────────────────────────────────
SAVE: selectionMemory[.menu] = {menuSelection: 2, ...}
NAVIGATE: currentScreen = .albums
RESTORE: No saved state for .albums, start at 0
menuSelection: 0

User scrolls to Album #10
menuSelection: 10

        ↓ Press Center on Album #10

Step 3: Save Albums State, Open Album Detail
────────────────────────────────────────────
SAVE: selectionMemory[.albums] = {menuSelection: 10, ...}
NAVIGATE: currentScreen = .albumDetail(album10)
RESTORE: No saved state for this album, start at 0
detailSelection: 0

User scrolls to Track #5
detailSelection: 5

        ↓ Press Menu

Step 4: Save Album Detail State, Back to Albums
───────────────────────────────────────────────
SAVE: selectionMemory[.albumDetail(album10)] = {detailSelection: 5, ...}
POP STACK: Get .albums from navigationStack
NAVIGATE: currentScreen = .albums
RESTORE: Found saved state for .albums
menuSelection: 10  ✓ Back to Album #10!

        ↓ Press Menu

Step 5: Save Albums State, Back to Menu
───────────────────────────────────────
SAVE: selectionMemory[.albums] = {menuSelection: 10, ...}
POP STACK: Get .menu from navigationStack
NAVIGATE: currentScreen = .menu
RESTORE: Found saved state for .menu
menuSelection: 2  ✓ Back to "Albums" menu item!
```

**Result:** Every screen remembers exactly where you were!

---

## Debug Console Example

```
User: Scroll to menu item "Songs" (position 1)
User: Press Center

🎯 SELECT BUTTON PRESSED!
   Current screen: menu
   Menu selection: 1
💾 Saved selection for menu: menu=1, song=0, detail=0
   → Opening Songs
📂 Restored selection for songs: menu=0, song=0, detail=0

User: Scroll to Song #42
User: Press Center

🎯 SELECT BUTTON PRESSED!
   Current screen: songs
   Menu selection: 0
💾 Saved selection for songs: menu=0, song=42, detail=0
🎵 Playing song: [Song Title]
📂 Restored selection for nowPlaying: menu=0, song=42, detail=0

User: Press Menu

📱 MENU BUTTON PRESSED!
💾 Saved selection for nowPlaying: menu=0, song=42, detail=0
   → Going back to: songs
📂 Restored selection for songs: menu=0, song=42, detail=0
   ✓ User sees Song #42 selected!

User: Press Menu

📱 MENU BUTTON PRESSED!
💾 Saved selection for songs: menu=0, song=42, detail=0
   → Going back to: menu
📂 Restored selection for menu: menu=1, song=0, detail=0
   ✓ User sees "Songs" menu item selected!
```

---

## Memory Persistence

### Current Implementation: In-Memory Only
- State stored in `@State var selectionMemory`
- Lost when app terminates
- No disk I/O overhead
- Fast and efficient

### Lifetime:
```
App Launch → selectionMemory = {} (empty)
    ↓
User Navigates → selectionMemory fills up
    ↓
App Terminates → selectionMemory discarded
```

### Future Enhancement: Persistent Storage
```swift
// Could add UserDefaults persistence
func saveToDefaults() {
    // Convert selectionMemory to JSON
    // Save to UserDefaults
}

func loadFromDefaults() {
    // Load from UserDefaults
    // Populate selectionMemory
}
```

---

## Benefits

1. **Natural User Experience**
   - Just like the real player
   - No frustrating "scroll again" moments

2. **Efficient Implementation**
   - O(1) dictionary lookups
   - Minimal memory overhead
   - No performance impact

3. **Complete Coverage**
   - Works on ALL screens
   - Handles deep navigation
   - Supports multiple detail views

4. **Smart Defaults**
   - New screens start at top
   - Appropriate resets per screen type
   - Graceful handling of edge cases

---

## Summary

Selection memory creates an **authentic player experience** where:

✅ Your scroll position is **always remembered**  
✅ Works across **all screens**  
✅ Handles **complex navigation chains**  
✅ **Independent memory** for each screen  
✅ **Smart restoration** on every navigation  

Just like the real thing! 🎵📱
