//
//  LyreTheme.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

// MARK: - Lyre Theme Configuration

struct LyreTheme {
    let style: LyreThemeStyle
    
    // Body colors
    let bodyGradientStart: Color
    let bodyGradientEnd: Color
    
    // Screen colors
    let screenBackgroundLight: [Color]
    let screenBackgroundDark: [Color]
    let screenTextColor: Color
    let screenSecondaryTextColor: Color
    let highlightColor: Color
    let highlightTextColor: Color
    let dividerColor: Color
    
    // Scroll wheel colors
    let wheelOuterGradientColors: [Color]
    let wheelCenterGradientColors: [Color]
    let wheelButtonTextColor: Color
    let wheelStrokeColor: Color
    let wheelCenterStrokeColor: Color
    
    static func theme(for style: LyreThemeStyle, highlightColor: Color? = nil) -> LyreTheme {
        let customHighlight = highlightColor
        
        switch style {
        case .porcelain:
            return LyreTheme(
                style: style,
                bodyGradientStart: Color(white: 0.85),
                bodyGradientEnd: Color(white: 0.75),
                screenBackgroundLight: [
                    Color(red: 0.7, green: 0.85, blue: 0.7),
                    Color(red: 0.6, green: 0.75, blue: 0.6)
                ],
                screenBackgroundDark: [
                    Color(red: 0.4, green: 0.5, blue: 0.4),
                    Color(red: 0.35, green: 0.45, blue: 0.35)
                ],
                screenTextColor: .black,
                screenSecondaryTextColor: Color.black.opacity(0.7),
                highlightColor: customHighlight ?? Color.blue.opacity(0.5),
                highlightTextColor: .white,
                dividerColor: .black,
                wheelOuterGradientColors: [
                    Color(white: 0.7),
                    Color(white: 0.5),
                    Color(white: 0.4)
                ],
                wheelCenterGradientColors: [
                    Color(white: 0.8),
                    Color(white: 0.65)
                ],
                wheelButtonTextColor: Color.black.opacity(0.7),
                wheelStrokeColor: Color.black.opacity(0.3),
                wheelCenterStrokeColor: Color.black.opacity(0.2)
            )
            
        case .slim:
            return LyreTheme(
                style: style,
                bodyGradientStart: Color(red: 0.75, green: 0.75, blue: 0.8),
                bodyGradientEnd: Color(red: 0.65, green: 0.65, blue: 0.7),
                screenBackgroundLight: [
                    Color(red: 0.85, green: 0.87, blue: 0.9),
                    Color(red: 0.75, green: 0.77, blue: 0.8)
                ],
                screenBackgroundDark: [
                    Color(red: 0.5, green: 0.52, blue: 0.55),
                    Color(red: 0.45, green: 0.47, blue: 0.5)
                ],
                screenTextColor: .black,
                screenSecondaryTextColor: Color.black.opacity(0.7),
                highlightColor: customHighlight ?? Color.orange.opacity(0.6),
                highlightTextColor: .white,
                dividerColor: .black.opacity(0.8),
                wheelOuterGradientColors: [
                    Color(white: 0.65),
                    Color(white: 0.45),
                    Color(white: 0.35)
                ],
                wheelCenterGradientColors: [
                    Color(white: 0.75),
                    Color(white: 0.6)
                ],
                wheelButtonTextColor: Color.black.opacity(0.8),
                wheelStrokeColor: Color.black.opacity(0.4),
                wheelCenterStrokeColor: Color.black.opacity(0.25)
            )
            
        case .monochrome:
            return LyreTheme(
                style: style,
                bodyGradientStart: Color(white: 0.15),
                bodyGradientEnd: Color(white: 0.05),
                screenBackgroundLight: [
                    Color(white: 0.95),
                    Color(white: 0.90)
                ],
                screenBackgroundDark: [
                    Color(white: 0.6),
                    Color(white: 0.55)
                ],
                screenTextColor: .black,
                screenSecondaryTextColor: Color.black.opacity(0.6),
                highlightColor: customHighlight ?? .black,
                highlightTextColor: .white,
                dividerColor: .black.opacity(0.9),
                wheelOuterGradientColors: [
                    Color(white: 0.3),
                    Color(white: 0.15),
                    Color(white: 0.1)
                ],
                wheelCenterGradientColors: [
                    Color(white: 0.35),
                    Color(white: 0.2)
                ],
                wheelButtonTextColor: Color.white.opacity(0.9),
                wheelStrokeColor: Color.white.opacity(0.2),
                wheelCenterStrokeColor: Color.white.opacity(0.15)
            )
            
        case .phosphor:
            return LyreTheme(
                style: style,
                bodyGradientStart: Color(white: 0.2),
                bodyGradientEnd: Color(white: 0.1),
                screenBackgroundLight: [
                    Color(red: 0.1, green: 0.3, blue: 0.1),
                    Color(red: 0.08, green: 0.25, blue: 0.08)
                ],
                screenBackgroundDark: [
                    Color(red: 0.05, green: 0.15, blue: 0.05),
                    Color(red: 0.03, green: 0.12, blue: 0.03)
                ],
                screenTextColor: Color(red: 0.4, green: 0.9, blue: 0.4),
                screenSecondaryTextColor: Color(red: 0.3, green: 0.7, blue: 0.3),
                highlightColor: customHighlight ?? Color(red: 0.5, green: 1.0, blue: 0.5),
                highlightTextColor: Color(red: 0.05, green: 0.2, blue: 0.05),
                dividerColor: Color(red: 0.3, green: 0.8, blue: 0.3),
                wheelOuterGradientColors: [
                    Color(white: 0.25),
                    Color(white: 0.15),
                    Color(white: 0.1)
                ],
                wheelCenterGradientColors: [
                    Color(white: 0.3),
                    Color(white: 0.18)
                ],
                wheelButtonTextColor: Color(red: 0.5, green: 0.9, blue: 0.5),
                wheelStrokeColor: Color(red: 0.2, green: 0.6, blue: 0.2).opacity(0.4),
                wheelCenterStrokeColor: Color(red: 0.2, green: 0.5, blue: 0.2).opacity(0.3)
            )
            
        case .spectrum:
            return LyreTheme(
                style: style,
                bodyGradientStart: Color(white: 0.9),
                bodyGradientEnd: Color(white: 0.82),
                screenBackgroundLight: [
                    Color(red: 0.95, green: 0.95, blue: 1.0),
                    Color(red: 0.90, green: 0.92, blue: 0.98)
                ],
                screenBackgroundDark: [
                    Color(red: 0.6, green: 0.62, blue: 0.7),
                    Color(red: 0.55, green: 0.57, blue: 0.65)
                ],
                screenTextColor: Color(red: 0.1, green: 0.1, blue: 0.2),
                screenSecondaryTextColor: Color(red: 0.3, green: 0.3, blue: 0.5),
                highlightColor: customHighlight ?? Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.7),
                highlightTextColor: .white,
                dividerColor: Color(red: 0.2, green: 0.2, blue: 0.4),
                wheelOuterGradientColors: [
                    Color(white: 0.75),
                    Color(white: 0.55),
                    Color(white: 0.45)
                ],
                wheelCenterGradientColors: [
                    Color(white: 0.85),
                    Color(white: 0.7)
                ],
                wheelButtonTextColor: Color.black.opacity(0.75),
                wheelStrokeColor: Color.black.opacity(0.25),
                wheelCenterStrokeColor: Color.black.opacity(0.18)
            )
            
        case .onyx:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(white: 0.18),
                bodyGradientEnd: Color(white: 0.06),
                highlightColor: customHighlight ?? Color(white: 0.25),
                darkWheel: true
            )
            
        case .sterling:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(white: 0.82),
                bodyGradientEnd: Color(white: 0.62),
                highlightColor: customHighlight ?? Color.blue.opacity(0.55)
            )
            
        case .crimson:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(white: 0.14),
                bodyGradientEnd: Color(white: 0.04),
                highlightColor: customHighlight ?? Color(red: 0.85, green: 0.05, blue: 0.05),
                darkWheel: true
            )
            
        case .pebbleSilver:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(white: 0.88),
                bodyGradientEnd: Color(white: 0.74),
                highlightColor: customHighlight ?? Color.blue.opacity(0.55)
            )
            
        case .pebbleGold:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.90, green: 0.80, blue: 0.60),
                bodyGradientEnd: Color(red: 0.75, green: 0.63, blue: 0.42),
                highlightColor: customHighlight ?? Color(red: 0.72, green: 0.52, blue: 0.20)
            )
            
        case .pebbleBlue:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.52, green: 0.72, blue: 0.92),
                bodyGradientEnd: Color(red: 0.34, green: 0.54, blue: 0.78),
                highlightColor: customHighlight ?? Color(red: 0.18, green: 0.42, blue: 0.78)
            )
            
        case .pebblePink:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.98, green: 0.76, blue: 0.82),
                bodyGradientEnd: Color(red: 0.88, green: 0.56, blue: 0.66),
                highlightColor: customHighlight ?? Color(red: 0.86, green: 0.30, blue: 0.48)
            )
            
        case .pebbleGreen:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.68, green: 0.90, blue: 0.66),
                bodyGradientEnd: Color(red: 0.46, green: 0.72, blue: 0.44),
                highlightColor: customHighlight ?? Color(red: 0.28, green: 0.62, blue: 0.28)
            )
            
        case .slimSilver:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.82, green: 0.82, blue: 0.86),
                bodyGradientEnd: Color(red: 0.66, green: 0.66, blue: 0.72),
                highlightColor: customHighlight ?? Color.blue.opacity(0.55)
            )
            
        case .slimBlack:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(white: 0.18),
                bodyGradientEnd: Color(white: 0.07),
                highlightColor: customHighlight ?? Color(white: 0.28),
                darkWheel: true
            )
            
        case .slimGraphite:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.42, green: 0.43, blue: 0.46),
                bodyGradientEnd: Color(red: 0.24, green: 0.25, blue: 0.28),
                highlightColor: customHighlight ?? Color(red: 0.36, green: 0.38, blue: 0.42),
                darkWheel: true
            )
            
        case .slimBlue:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.20, green: 0.56, blue: 0.92),
                bodyGradientEnd: Color(red: 0.08, green: 0.34, blue: 0.70),
                highlightColor: customHighlight ?? Color(red: 0.05, green: 0.32, blue: 0.78)
            )
            
        case .slimPink:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.98, green: 0.44, blue: 0.64),
                bodyGradientEnd: Color(red: 0.82, green: 0.22, blue: 0.42),
                highlightColor: customHighlight ?? Color(red: 0.84, green: 0.18, blue: 0.40)
            )
            
        case .slimPurple:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.64, green: 0.44, blue: 0.86),
                bodyGradientEnd: Color(red: 0.44, green: 0.24, blue: 0.66),
                highlightColor: customHighlight ?? Color(red: 0.46, green: 0.22, blue: 0.72)
            )
            
        case .slimGreen:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.42, green: 0.82, blue: 0.42),
                bodyGradientEnd: Color(red: 0.22, green: 0.62, blue: 0.24),
                highlightColor: customHighlight ?? Color(red: 0.20, green: 0.62, blue: 0.22)
            )
            
        case .slimYellow:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 1.0, green: 0.88, blue: 0.28),
                bodyGradientEnd: Color(red: 0.86, green: 0.68, blue: 0.10),
                highlightColor: customHighlight ?? Color(red: 0.76, green: 0.54, blue: 0.06)
            )
            
        case .slimOrange:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 1.0, green: 0.56, blue: 0.22),
                bodyGradientEnd: Color(red: 0.86, green: 0.34, blue: 0.08),
                highlightColor: customHighlight ?? Color(red: 0.82, green: 0.30, blue: 0.04)
            )
            
        case .slimRed:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.92, green: 0.12, blue: 0.12),
                bodyGradientEnd: Color(red: 0.66, green: 0.02, blue: 0.04),
                highlightColor: customHighlight ?? Color(red: 0.72, green: 0.02, blue: 0.04)
            )
            
        case .clipSilver:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.84, green: 0.84, blue: 0.88),
                bodyGradientEnd: Color(red: 0.68, green: 0.68, blue: 0.74),
                highlightColor: customHighlight ?? Color.blue.opacity(0.55)
            )
            
        case .clipBlue:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.32, green: 0.70, blue: 0.98),
                bodyGradientEnd: Color(red: 0.12, green: 0.48, blue: 0.78),
                highlightColor: customHighlight ?? Color(red: 0.08, green: 0.40, blue: 0.78)
            )
            
        case .clipPink:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.98, green: 0.50, blue: 0.70),
                bodyGradientEnd: Color(red: 0.84, green: 0.28, blue: 0.50),
                highlightColor: customHighlight ?? Color(red: 0.84, green: 0.22, blue: 0.46)
            )
            
        case .clipGreen:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.58, green: 0.84, blue: 0.34),
                bodyGradientEnd: Color(red: 0.34, green: 0.66, blue: 0.18),
                highlightColor: customHighlight ?? Color(red: 0.30, green: 0.58, blue: 0.14)
            )
            
        case .clipOrange:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 1.0, green: 0.58, blue: 0.24),
                bodyGradientEnd: Color(red: 0.84, green: 0.36, blue: 0.10),
                highlightColor: customHighlight ?? Color(red: 0.80, green: 0.32, blue: 0.06)
            )
            
        case .clipPurple:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.60, green: 0.48, blue: 0.84),
                bodyGradientEnd: Color(red: 0.40, green: 0.28, blue: 0.64),
                highlightColor: customHighlight ?? Color(red: 0.42, green: 0.26, blue: 0.66)
            )
            
        case .clipGold:
            return finishTheme(
                style: style,
                bodyGradientStart: Color(red: 0.92, green: 0.78, blue: 0.48),
                bodyGradientEnd: Color(red: 0.74, green: 0.56, blue: 0.28),
                highlightColor: customHighlight ?? Color(red: 0.72, green: 0.50, blue: 0.18)
            )
        }
    }
    
    private static func finishTheme(
        style: LyreThemeStyle,
        bodyGradientStart: Color,
        bodyGradientEnd: Color,
        highlightColor: Color,
        darkWheel: Bool = false
    ) -> LyreTheme {
        LyreTheme(
            style: style,
            bodyGradientStart: bodyGradientStart,
            bodyGradientEnd: bodyGradientEnd,
            screenBackgroundLight: [
                Color(red: 0.94, green: 0.95, blue: 0.98),
                Color(red: 0.86, green: 0.88, blue: 0.92)
            ],
            screenBackgroundDark: [
                Color(red: 0.58, green: 0.60, blue: 0.64),
                Color(red: 0.50, green: 0.52, blue: 0.56)
            ],
            screenTextColor: .black,
            screenSecondaryTextColor: Color.black.opacity(0.68),
            highlightColor: highlightColor.opacity(0.72),
            highlightTextColor: .white,
            dividerColor: Color.black.opacity(0.75),
            wheelOuterGradientColors: darkWheel ? [
                Color(white: 0.32),
                Color(white: 0.18),
                Color(white: 0.10)
            ] : [
                Color(white: 0.82),
                Color(white: 0.66),
                Color(white: 0.52)
            ],
            wheelCenterGradientColors: darkWheel ? [
                Color(white: 0.38),
                Color(white: 0.22)
            ] : [
                Color(white: 0.90),
                Color(white: 0.72)
            ],
            wheelButtonTextColor: darkWheel ? Color.white.opacity(0.90) : Color.black.opacity(0.72),
            wheelStrokeColor: darkWheel ? Color.white.opacity(0.18) : Color.black.opacity(0.28),
            wheelCenterStrokeColor: darkWheel ? Color.white.opacity(0.14) : Color.black.opacity(0.18)
        )
    }
}
