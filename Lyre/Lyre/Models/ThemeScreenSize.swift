//
//  ScreenSize.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import Foundation

enum ScreenSize: String, CaseIterable, Identifiable {
    case nano = "Nano"
    case mini = "Mini"
    case nanoTall = "Nano Tall"
    case retro = "Retro"
    case standard = "Standard"
    case large = "Large"
    case extraLarge = "Extra Large"

    var id: String { rawValue }

    var dimensions: CGSize {
        switch self {
        case .nano:
            return CGSize(width: 220, height: 155)
        case .mini:
            return CGSize(width: 250, height: 175)
        case .nanoTall:
            return CGSize(width: 320, height: 420)
        case .retro:
            return CGSize(width: 260, height: 180)
        case .standard:
            return CGSize(width: 280, height: 200)
        case .large:
            return CGSize(width: 320, height: 240)
        case .extraLarge:
            return CGSize(width: 360, height: 280)
        }
    }

    var wheelSize: CGFloat {
        switch self {
        case .nano:
            return 240
        case .mini:
            return 255
        case .nanoTall:
            return 260
        case .retro:
            return 270
        case .standard:
            return 280
        case .large:
            return 300
        case .extraLarge:
            return 320
        }
    }
}
