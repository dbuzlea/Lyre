//
//  ThemeSettings.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

enum BacklightDuration: String, CaseIterable {
    case fiveSeconds   = "5 Seconds"
    case tenSeconds    = "10 Seconds"
    case thirtySeconds = "30 Seconds"
    case alwaysOn      = "Always On"

    var interval: TimeInterval? {
        switch self {
        case .fiveSeconds:   return 5
        case .tenSeconds:    return 10
        case .thirtySeconds: return 30
        case .alwaysOn:      return nil
        }
    }
}

enum ScrollSensitivity: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var scrollThreshold: Double {
        switch self {
        case .low: return 25.0   // original pre-acceleration threshold
        case .medium: return 35.0
        case .high: return 22.0
        }
    }

    var velocityStepThresholds: (t1: Double, t2: Double, t3: Double) {
        switch self {
        case .low:    return (600, 1100, 1800)  // acceleration only at extreme spin speeds
        case .medium: return (180, 380, 600)
        case .high:   return (120, 280, 480)
        }
    }
}

@Observable
class ThemeSettings {
    var themeStyle: LyreThemeStyle {
        didSet {
            UserDefaults.standard.set(themeStyle.rawValue, forKey: "LyreThemeStyle")
            // Update screen size to match the new theme's default if using auto
            if useAutoScreenSize {
                screenSize = themeStyle.defaultScreenSize
            }
        }
    }
    
    var customHighlightColor: Color {
        didSet {
            if let colorData = try? JSONEncoder().encode(customHighlightColor.toStorableColor()) {
                UserDefaults.standard.set(colorData, forKey: "LyreCustomHighlightColor")
            }
        }
    }
    
    var useCustomHighlight: Bool {
        didSet {
            UserDefaults.standard.set(useCustomHighlight, forKey: "LyreUseCustomHighlight")
        }
    }
    
    var screenSize: ScreenSize {
        didSet {
            UserDefaults.standard.set(screenSize.rawValue, forKey: "LyreScreenSize")
        }
    }
    
    var useAutoScreenSize: Bool {
        didSet {
            UserDefaults.standard.set(useAutoScreenSize, forKey: "LyreUseAutoScreenSize")
            // If switching to auto, update screen size to match current theme
            if useAutoScreenSize {
                screenSize = themeStyle.defaultScreenSize
            }
        }
    }

    var scrollSensitivity: ScrollSensitivity {
        didSet {
            UserDefaults.standard.set(scrollSensitivity.rawValue, forKey: "LyreScrollSensitivity")
        }
    }

    var clickSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clickSoundEnabled, forKey: "LyreClickSoundEnabled")
        }
    }

    var backlightDuration: BacklightDuration {
        didSet {
            UserDefaults.standard.set(backlightDuration.rawValue, forKey: "LyreBacklightDuration")
        }
    }

    var playerStyle: PlayerStyle {
        didSet {
            UserDefaults.standard.set(playerStyle.rawValue, forKey: "LyrePlayerStyle")
        }
    }

    /// The Spool's body and finish. Any finish goes on either body.
    var spoolModel: SpoolModel {
        didSet {
            UserDefaults.standard.set(spoolModel.rawValue, forKey: "LyreSpoolModel")
        }
    }

    var spoolFinish: SpoolFinish {
        didSet {
            UserDefaults.standard.set(spoolFinish.rawValue, forKey: "LyreSpoolFinish")
        }
    }

    /// The Gramophone's design and finish. Any finish goes on either design.
    var gramophoneModel: GramophoneModel {
        didSet {
            UserDefaults.standard.set(gramophoneModel.rawValue, forKey: "LyreGramophoneModel")
        }
    }

    var gramophoneFinish: GramophoneFinish {
        didSet {
            UserDefaults.standard.set(gramophoneFinish.rawValue, forKey: "LyreGramophoneFinish")
        }
    }

    /// The faint crackle of the record under the music. On unless turned off.
    var gramophoneSurfaceNoise: Bool {
        didSet {
            UserDefaults.standard.set(gramophoneSurfaceNoise, forKey: "LyreGramophoneSurfaceNoise")
        }
    }

    /// Maps theme names persisted before the 1.0 rename onto their current
    /// equivalents, so an existing install keeps its chosen finish instead of
    /// silently falling back to the default.
    ///
    /// Safe to delete once no install predates 1.0.
    private static func migratedStyle(from legacyRawValue: String) -> LyreThemeStyle? {
        switch legacyRawValue {
        case "Classic White":    return .porcelain
        case "Classic Black":    return .onyx
        case "Classic Silver":   return .sterling
        case "U2 Black & Red":   return .crimson
        case "Black & White":    return .monochrome
        case "Green Screen":     return .phosphor
        case "Color Screen":     return .spectrum
        case "Lyre Mini Silver": return .pebbleSilver
        case "Lyre Mini Gold":   return .pebbleGold
        case "Lyre Mini Blue":   return .pebbleBlue
        case "Lyre Mini Pink":   return .pebblePink
        case "Lyre Mini Green":  return .pebbleGreen
        case "Lyre Nano":        return .slim
        case "Nano Silver":      return .slimSilver
        case "Nano Black":       return .slimBlack
        case "Nano Space Gray":  return .slimGraphite
        case "Nano Blue":        return .slimBlue
        case "Nano Pink":        return .slimPink
        case "Nano Purple":      return .slimPurple
        case "Nano Green":       return .slimGreen
        case "Nano Yellow":      return .slimYellow
        case "Nano Orange":      return .slimOrange
        case "Nano Red":         return .slimRed
        case "Shuffle Silver":   return .clipSilver
        case "Shuffle Blue":     return .clipBlue
        case "Shuffle Pink":     return .clipPink
        case "Shuffle Green":    return .clipGreen
        case "Shuffle Orange":   return .clipOrange
        case "Shuffle Purple":   return .clipPurple
        case "Shuffle Gold":     return .clipGold
        default:                 return nil
        }
    }

    var currentTheme: LyreTheme {
        LyreTheme.theme(
            for: themeStyle,
            highlightColor: useCustomHighlight ? customHighlightColor : nil
        )
    }
    
    init() {
        // Load theme style first
        let loadedThemeStyle: LyreThemeStyle
        if let savedStyle = UserDefaults.standard.string(forKey: "LyreThemeStyle"),
           let style = LyreThemeStyle(rawValue: savedStyle)
                    ?? Self.migratedStyle(from: savedStyle) {
            loadedThemeStyle = style
        } else {
            loadedThemeStyle = .porcelain
        }
        
        // Load custom highlight color
        if let colorData = UserDefaults.standard.data(forKey: "LyreCustomHighlightColor"),
           let storableColor = try? JSONDecoder().decode(StorableColor.self, from: colorData) {
            self.customHighlightColor = storableColor.toColor()
        } else {
            self.customHighlightColor = .blue
        }
        
        // Load use custom highlight flag
        self.useCustomHighlight = UserDefaults.standard.bool(forKey: "LyreUseCustomHighlight")
        
        // Load auto screen size flag
        self.useAutoScreenSize = UserDefaults.standard.bool(forKey: "LyreUseAutoScreenSize")
        
        // Load screen size using the loaded theme style
        if let savedSize = UserDefaults.standard.string(forKey: "LyreScreenSize"),
           let size = ScreenSize(rawValue: savedSize) {
            self.screenSize = size
        } else {
            // Default to theme's default screen size
            self.screenSize = loadedThemeStyle.defaultScreenSize
        }
        
        // Load scroll sensitivity
        if let savedSensitivity = UserDefaults.standard.string(forKey: "LyreScrollSensitivity"),
           let sensitivity = ScrollSensitivity(rawValue: savedSensitivity) {
            self.scrollSensitivity = sensitivity
        } else {
            self.scrollSensitivity = .medium
        }

        // Load click sound enabled (defaults to true)
        if UserDefaults.standard.object(forKey: "LyreClickSoundEnabled") != nil {
            self.clickSoundEnabled = UserDefaults.standard.bool(forKey: "LyreClickSoundEnabled")
        } else {
            self.clickSoundEnabled = true
        }

        // Load backlight duration (defaults to 10 seconds)
        if let savedDuration = UserDefaults.standard.string(forKey: "LyreBacklightDuration"),
           let duration = BacklightDuration(rawValue: savedDuration) {
            self.backlightDuration = duration
        } else {
            self.backlightDuration = .tenSeconds
        }

        // Load player style (defaults to the click-wheel player)
        if let savedStyle = UserDefaults.standard.string(forKey: "LyrePlayerStyle"),
           let style = PlayerStyle(rawValue: savedStyle) {
            self.playerStyle = style
        } else {
            self.playerStyle = .classic
        }

        self.spoolModel = UserDefaults.standard.string(forKey: "LyreSpoolModel")
            .flatMap(SpoolModel.init(rawValue:)) ?? .original
        self.spoolFinish = UserDefaults.standard.string(forKey: "LyreSpoolFinish")
            .flatMap(SpoolFinish.init(rawValue:)) ?? .blue
        self.gramophoneModel = UserDefaults.standard.string(forKey: "LyreGramophoneModel")
            .flatMap(GramophoneModel.init(rawValue:)) ?? .horn
        self.gramophoneFinish = UserDefaults.standard.string(forKey: "LyreGramophoneFinish")
            .flatMap(GramophoneFinish.init(rawValue:)) ?? .mahogany
        self.gramophoneSurfaceNoise = UserDefaults.standard.object(forKey: "LyreGramophoneSurfaceNoise") as? Bool ?? true

        // Finally, set the theme style
        self.themeStyle = loadedThemeStyle
    }
}
