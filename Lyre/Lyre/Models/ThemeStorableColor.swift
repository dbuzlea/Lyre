//
//  StorableColor.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

struct StorableColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
    
    func toColor() -> Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension Color {
    func toStorableColor() -> StorableColor {
        guard let components = UIColor(self).cgColor.components else {
            return StorableColor(red: 0, green: 0, blue: 1, opacity: 1)
        }
        
        if components.count >= 3 {
            return StorableColor(
                red: Double(components[0]),
                green: Double(components[1]),
                blue: Double(components[2]),
                opacity: components.count >= 4 ? Double(components[3]) : 1.0
            )
        } else {
            // Grayscale
            return StorableColor(
                red: Double(components[0]),
                green: Double(components[0]),
                blue: Double(components[0]),
                opacity: components.count >= 2 ? Double(components[1]) : 1.0
            )
        }
    }
}
