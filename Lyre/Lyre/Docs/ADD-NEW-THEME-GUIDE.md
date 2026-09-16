# Adding a New Theme - Developer Guide

## Quick Start: Add Your Own Theme in 5 Minutes

Want to add a custom theme to the player app? Here's how!

---

## Step 1: Add Theme to Enum

**File:** `Models/ThemeLyreThemeStyle.swift`

Find the `LyreThemeStyle` enum and add your theme:

```swift
enum LyreThemeStyle: String, CaseIterable, Identifiable {
    case classic = "Porcelain"
    case nano = "player Nano"
    case blackWhite = "Monochrome"
    case greenScreen = "Phosphor"
    case colorScreen = "Spectrum"
    case myTheme = "My Cool Theme"  // ← ADD THIS
    
    var id: String { rawValue }
}
```

---

## Step 2: Define Theme Colors

**File:** `Models/LyreTheme.swift`

Find the `theme(for:highlightColor:)` method and add your case:

```swift
static func theme(for style: LyreThemeStyle, highlightColor: Color? = nil) -> LyreTheme {
    let customHighlight = highlightColor
    
    switch style {
    // ... existing cases ...
    
    case .myTheme:  // ← ADD THIS CASE
        return LyreTheme(
            style: style,
            
            // player body colors
            bodyGradientStart: Color(red: 0.5, green: 0.3, blue: 0.8),  // Purple-ish
            bodyGradientEnd: Color(red: 0.4, green: 0.2, blue: 0.7),
            
            // Screen background (when backlight is ON)
            screenBackgroundLight: [
                Color(red: 0.9, green: 0.85, blue: 1.0),  // Light purple tint
                Color(red: 0.85, green: 0.8, blue: 0.95)
            ],
            
            // Screen background (when backlight is OFF/dimmed)
            screenBackgroundDark: [
                Color(red: 0.6, green: 0.55, blue: 0.7),
                Color(red: 0.55, green: 0.5, blue: 0.65)
            ],
            
            // Text colors on screen
            screenTextColor: Color(red: 0.1, green: 0.1, blue: 0.2),  // Dark purple text
            screenSecondaryTextColor: Color(red: 0.3, green: 0.2, blue: 0.5),  // Lighter for subtitles
            
            // Selection highlight
            highlightColor: customHighlight ?? Color.purple.opacity(0.6),  // Default purple
            highlightTextColor: .white,  // White text on highlight
            
            // Divider lines
            dividerColor: Color(red: 0.2, green: 0.1, blue: 0.4),
            
            // Scroll wheel outer ring gradient
            wheelOuterGradientColors: [
                Color(white: 0.7),
                Color(white: 0.5),
                Color(white: 0.4)
            ],
            
            // Scroll wheel center button gradient
            wheelCenterGradientColors: [
                Color(white: 0.8),
                Color(white: 0.65)
            ],
            
            // Button labels on wheel
            wheelButtonTextColor: Color.black.opacity(0.7),
            
            // Wheel strokes/outlines
            wheelStrokeColor: Color.black.opacity(0.3),
            wheelCenterStrokeColor: Color.black.opacity(0.2)
        )
    }
}
```

---

## Step 3: Test It!

1. Build and run the app
2. Go to Settings → Theme
3. Your new theme appears in the list!
4. Select it and see it applied instantly

---

## Color Picker Tips

### Getting Good Colors

Use these online tools:
- **Coolors.co** - Generate color palettes
- **Adobe Color** - Professional color wheel
- **Material.io/color** - Material Design palette generator

### SwiftUI Color from Hex

```swift
// If you have a hex color like #8B4FD9
Color(red: 0x8B / 255.0, green: 0x4F / 255.0, blue: 0xD9 / 255.0)

// Or more readable:
Color(red: 139/255, green: 79/255, blue: 217/255)
```

### Color Naming Convention

Use descriptive names in comments:

```swift
bodyGradientStart: Color(red: 0.85, green: 0.7, blue: 0.5),  // Warm sand
bodyGradientEnd: Color(red: 0.75, green: 0.6, blue: 0.4),    // Desert tan
```

---

## Theme Design Guidelines

### 1. Body Colors
**Purpose:** The physical player body appearance

**Tips:**
- Use metallic grays for classic look
- Try bold colors for modern feel
- Keep gradient subtle (not too different)
- Consider: Silver, Black, Rose Gold, Blue, Red, White

### 2. Screen Background
**Purpose:** LCD/OLED screen appearance

**Tips:**
- Light version = backlight ON (brighter)
- Dark version = backlight OFF (dimmer) — used by the configurable auto-dim timer
- Classic Lyres had greenish LCD tint
- Modern ones can be pure white or OLED black
- Gradient should be subtle
- The glass overlay renders on top, so pure white works well

### 3. Screen Text Colors
**Purpose:** Primary and secondary text

**Guidelines:**
- High contrast with background
- Secondary should be 60-70% opacity of primary
- Test readability in all lighting conditions
- Dark text on light screen OR light text on dark screen

### 4. Highlight Color
**Purpose:** Selected item background (also drives the glass-edge refraction effect)

**Guidelines:**
- Should stand out clearly
- Must contrast with both body and screen
- Consider theme's overall vibe
- Classic = Blue, Modern = Accent color
- Opacity 0.5-0.7 works well

### 5. Highlight Text Color
**Purpose:** Text on highlighted items

**Rules:**
- Must be readable on highlight color
- Usually white or black
- High contrast is critical

### 6. Wheel Colors
**Purpose:** Scroll wheel appearance

**Tips:**
- Match body colors for cohesive look
- Or contrast for visual interest
- Gradient adds depth and realism
- Button text must be visible

---

## Example Themes to Try

### Beach Sunset
```swift
case .beachSunset = "Beach Sunset"

// In switch:
bodyGradientStart: Color(red: 1.0, green: 0.7, blue: 0.4),  // Warm orange
bodyGradientEnd: Color(red: 0.9, green: 0.5, blue: 0.3),    // Deep orange
screenBackgroundLight: [Color(red: 1.0, green: 0.95, blue: 0.85), ...],
screenTextColor: Color(red: 0.3, green: 0.2, blue: 0.1),  // Brown
highlightColor: customHighlight ?? Color.orange.opacity(0.7),
```

### Ocean Blue
```swift
case .oceanBlue = "Ocean Blue"

bodyGradientStart: Color(red: 0.2, green: 0.4, blue: 0.6),  // Deep blue
bodyGradientEnd: Color(red: 0.1, green: 0.3, blue: 0.5),
screenBackgroundLight: [Color(red: 0.85, green: 0.92, blue: 0.98), ...],
screenTextColor: Color(red: 0.1, green: 0.2, blue: 0.4),
highlightColor: customHighlight ?? Color.cyan.opacity(0.6),
```

### Forest Green
```swift
case .forestGreen = "Forest Green"

bodyGradientStart: Color(red: 0.2, green: 0.4, blue: 0.2),
bodyGradientEnd: Color(red: 0.15, green: 0.35, blue: 0.15),
screenBackgroundLight: [Color(red: 0.9, green: 0.95, blue: 0.9), ...],
screenTextColor: Color(red: 0.1, green: 0.3, blue: 0.1),
highlightColor: customHighlight ?? Color.green.opacity(0.6),
```

### Rose Gold
```swift
case .roseGold = "Rose Gold"

bodyGradientStart: Color(red: 0.9, green: 0.8, blue: 0.8),
bodyGradientEnd: Color(red: 0.85, green: 0.7, blue: 0.7),
screenBackgroundLight: [Color(red: 1.0, green: 0.95, blue: 0.95), ...],
screenTextColor: Color(red: 0.4, green: 0.2, blue: 0.3),
highlightColor: customHighlight ?? Color.pink.opacity(0.5),
```

### Midnight Black
```swift
case .midnightBlack = "Midnight Black"

bodyGradientStart: Color(white: 0.1),
bodyGradientEnd: Color(white: 0.05),
screenBackgroundLight: [Color(white: 0.15), Color(white: 0.12)],  // OLED black
screenTextColor: Color.white,  // White text on black
screenSecondaryTextColor: Color.white.opacity(0.7),
highlightColor: customHighlight ?? Color.white.opacity(0.3),
highlightTextColor: .white,
wheelButtonTextColor: Color.white.opacity(0.8),  // Light text on dark wheel
```

---

## Testing Your Theme

### Checklist
- ☐ Body looks good
- ☐ Screen is readable (backlight ON)
- ☐ Screen is readable (backlight OFF / dimmed)
- ☐ Highlight clearly visible
- ☐ Text on highlight is readable
- ☐ Dividers visible but subtle
- ☐ Wheel matches overall aesthetic
- ☐ Button labels readable
- ☐ Glass overlay looks natural on screen background
- ☐ Works in bright light
- ☐ Works in dark room
- ☐ All screens look good (Menu, Now Playing, Lists, Details)

### Common Issues

**Text hard to read?**
→ Increase contrast between text and background

**Highlight doesn't stand out?**
→ Make it brighter or more saturated
→ Try adding more opacity

**Wheel doesn't match?**
→ Use colors from body gradient
→ Or try high contrast

**Looks washed out?**
→ Increase color saturation
→ Make gradients more distinct

**Dark theme looks bad when backlight is on?**
→ Keep `screenBackgroundLight` slightly brighter than `screenBackgroundDark` even for dark themes

---

## Advanced: Dynamic Themes

Want themes that change based on conditions?

```swift
// Example: Time-based theme
var currentTheme: LyreTheme {
    let hour = Calendar.current.component(.hour, from: Date())
    
    if hour >= 6 && hour < 18 {
        // Daytime theme
        return LyreTheme.theme(for: .spectrum, highlightColor: customHighlightColor)
    } else {
        // Nighttime theme
        return LyreTheme.theme(for: .monochrome, highlightColor: customHighlightColor)
    }
}
```

---

## Sharing Your Theme

If you create an awesome theme, consider:
1. Taking screenshots
2. Sharing the color values
3. Contributing to the project
4. Helping others customize!

---

## Summary

**To add a theme:**
1. Add case to `LyreThemeStyle` enum in `Models/ThemeLyreThemeStyle.swift` (1 line)
2. Add case to switch statement in `Models/LyreTheme.swift` with colors (30 lines)
3. Build and test
4. Done! 🎉

**That's it!** Your theme is now available to all users in the Settings menu.

Happy theming! 🎨
