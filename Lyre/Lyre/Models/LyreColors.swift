//
//  LyreColors.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI

struct LyreColorOption: Identifiable {
    let name: String
    let color: Color
    
    var id: String { name }
}

// Classic Lyre color schemes
struct LyreColors {
    // Screen colors (classic monochrome LCD)
    static let screenBackground = Color(white: 0.82)
    static let screenBacklight = LinearGradient(
        colors: [Color(white: 0.85), Color(white: 0.75)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let screenText = Color.black
    static let screenTextSecondary = Color.black.opacity(0.6)
    static let selectionHighlight = Color.blue.opacity(0.5)
    
    // Body colors (classic white)
    static let bodyWhite = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let bezelGray = Color.gray.opacity(0.3)
    
    // Scroll wheel (polished chrome effect)
    static let wheelChrome = RadialGradient(
        colors: [
            Color(white: 0.7),
            Color(white: 0.5),
            Color(white: 0.4)
        ],
        center: .center,
        startRadius: 70,
        endRadius: 140
    )
    
    static let wheelCenter = RadialGradient(
        colors: [Color(white: 0.8), Color(white: 0.65)],
        center: .center,
        startRadius: 0,
        endRadius: 60
    )
    
    static let buttonText = Color.black.opacity(0.7)
    static let buttonTextPressed = Color.black.opacity(0.9)
    
    // Wheel interaction feedback
    static let wheelHighlight = Color.white.opacity(0.15)
    
    // Finish colors used by theme and highlight settings.
    static let finishColorOptions: [LyreColorOption] = [
        LyreColorOption(name: "Porcelain", color: Color(red: 0.95, green: 0.95, blue: 0.97)),
        LyreColorOption(name: "Onyx", color: Color(white: 0.08)),
        LyreColorOption(name: "Sterling", color: Color(white: 0.72)),
        LyreColorOption(name: "Crimson", color: Color(red: 0.85, green: 0.05, blue: 0.05)),
        LyreColorOption(name: "Pebble Silver", color: Color(white: 0.82)),
        LyreColorOption(name: "Pebble Gold", color: Color(red: 0.85, green: 0.75, blue: 0.55)),
        LyreColorOption(name: "Pebble Blue", color: Color(red: 0.4, green: 0.6, blue: 0.85)),
        LyreColorOption(name: "Pebble Pink", color: Color(red: 0.95, green: 0.7, blue: 0.75)),
        LyreColorOption(name: "Pebble Green", color: Color(red: 0.6, green: 0.85, blue: 0.6)),
        LyreColorOption(name: "Slim Silver", color: Color(red: 0.75, green: 0.75, blue: 0.8)),
        LyreColorOption(name: "Slim Black", color: Color(white: 0.12)),
        LyreColorOption(name: "Slim Graphite", color: Color(red: 0.32, green: 0.33, blue: 0.35)),
        LyreColorOption(name: "Slim Blue", color: Color(red: 0.12, green: 0.46, blue: 0.82)),
        LyreColorOption(name: "Slim Pink", color: Color(red: 0.95, green: 0.35, blue: 0.56)),
        LyreColorOption(name: "Slim Purple", color: Color(red: 0.55, green: 0.34, blue: 0.78)),
        LyreColorOption(name: "Slim Green", color: Color(red: 0.34, green: 0.72, blue: 0.34)),
        LyreColorOption(name: "Slim Yellow", color: Color(red: 0.95, green: 0.82, blue: 0.20)),
        LyreColorOption(name: "Slim Orange", color: Color(red: 0.95, green: 0.45, blue: 0.16)),
        LyreColorOption(name: "Slim Red", color: Color(red: 0.82, green: 0.05, blue: 0.08)),
        LyreColorOption(name: "Clip Silver", color: Color(red: 0.78, green: 0.78, blue: 0.82)),
        LyreColorOption(name: "Clip Blue", color: Color(red: 0.24, green: 0.62, blue: 0.90)),
        LyreColorOption(name: "Clip Pink", color: Color(red: 0.95, green: 0.42, blue: 0.64)),
        LyreColorOption(name: "Clip Green", color: Color(red: 0.48, green: 0.76, blue: 0.28)),
        LyreColorOption(name: "Clip Orange", color: Color(red: 0.95, green: 0.50, blue: 0.18)),
        LyreColorOption(name: "Clip Purple", color: Color(red: 0.50, green: 0.38, blue: 0.75)),
        LyreColorOption(name: "Clip Gold", color: Color(red: 0.86, green: 0.72, blue: 0.43))
    ]
}

// Alternative color schemes for different Lyre models

struct LyreMiniColors {
    static let bodyBlue = Color(red: 0.4, green: 0.6, blue: 0.85)
    static let bodyPink = Color(red: 0.95, green: 0.7, blue: 0.75)
    static let bodyGreen = Color(red: 0.6, green: 0.85, blue: 0.6)
    static let bodySilver = Color(white: 0.85)
    static let bodyGold = Color(red: 0.85, green: 0.75, blue: 0.55)
}

struct LyreU2Colors {
    static let bodyBlack = Color.black
    static let accentRed = Color.red
}

// Typography for authentic Lyre look
extension Font {
    static let LyreTitle = Font.system(size: 16, weight: .bold, design: .default)
    static let LyreMenuItem = Font.system(size: 14, weight: .regular, design: .default)
    static let LyreMenuItemSelected = Font.system(size: 14, weight: .semibold, design: .default)
    static let LyreSongTitle = Font.system(size: 11, weight: .medium, design: .default)
    static let LyreSongArtist = Font.system(size: 9, weight: .regular, design: .default)
    static let LyreStatus = Font.system(size: 10, weight: .regular, design: .default)
    static let LyreButton = Font.system(size: 10, weight: .semibold, design: .default)
}
