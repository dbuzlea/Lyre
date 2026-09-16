//
//  SettingsView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

struct SettingsView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    
    let settingsItems = [
        String(localized: "settings.theme"),
        String(localized: "settings.screenSize"),
        String(localized: "settings.highlightColor"),
        String(localized: "settings.scrollSensitivity"),
        String(localized: "settings.clickSound"),
        String(localized: "settings.backlight"),
        String(localized: "settings.about")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<settingsItems.count, id: \.self) { index in
                    HStack {
                        if selection == index {
                            Rectangle()
                                .fill(themeSettings.currentTheme.highlightColor)
                                .overlay {
                                    HStack {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                        Text(settingsItems[index])
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                                .selectionBarRefraction()
                        } else {
                            HStack {
                                Text(settingsItems[index])
                                    .font(.system(size: 14))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                Spacer()
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .frame(height: 28)
                }
            }
            
            Spacer()
        }
    }
}

struct ThemeSelectionView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.theme"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(LyreThemeStyle.allCases.enumerated()), id: \.offset) { index, themeStyle in
                            HStack {
                                if selection == index {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                Image(systemName: themeSettings.themeStyle == themeStyle ? "checkmark" : "")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                    .frame(width: 12)
                                                Text(themeStyle.rawValue)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        Image(systemName: themeSettings.themeStyle == themeStyle ? "checkmark" : "")
                                            .font(.system(size: 10))
                                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                            .frame(width: 12)
                                        Text(themeStyle.rawValue)
                                            .font(.system(size: 14))
                                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            .frame(height: 28)
                            .id(index)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .onChange(of: selection) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct HighlightColorView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    
    let colorOptions = LyreColors.finishColorOptions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.highlightColor"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Default option
                        HStack {
                            if selection == 0 {
                                Rectangle()
                                    .fill(themeSettings.currentTheme.highlightColor)
                                    .overlay {
                                        HStack {
                                            Image(systemName: !themeSettings.useCustomHighlight ? "checkmark" : "")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                .frame(width: 12)
                                            Text(String(localized: "settings.highlightColor.default"))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            Spacer()
                                        }
                                        .padding(.leading, 8)
                                    }
                                    .selectionBarRefraction()
                            } else {
                                HStack {
                                    Image(systemName: !themeSettings.useCustomHighlight ? "checkmark" : "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                        .frame(width: 12)
                                    Text(String(localized: "settings.highlightColor.default"))
                                        .font(.system(size: 14))
                                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                    Spacer()
                                }
                                .padding(.leading, 8)
                            }
                        }
                        .frame(height: 28)
                        .id(0)
                        
                        // Color options
                        ForEach(Array(colorOptions.enumerated()), id: \.offset) { index, colorOption in
                            let adjustedIndex = index + 1
                            HStack {
                                if selection == adjustedIndex {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                Image(systemName: themeSettings.useCustomHighlight && colorMatches(themeSettings.customHighlightColor, colorOption.color) ? "checkmark" : "")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                    .frame(width: 12)
                                                Circle()
                                                    .fill(colorOption.color)
                                                    .frame(width: 10, height: 10)
                                                Text(colorOption.name)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        Image(systemName: themeSettings.useCustomHighlight && colorMatches(themeSettings.customHighlightColor, colorOption.color) ? "checkmark" : "")
                                            .font(.system(size: 10))
                                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                            .frame(width: 12)
                                        Circle()
                                            .fill(colorOption.color)
                                            .frame(width: 10, height: 10)
                                        Text(colorOption.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            .frame(height: 28)
                            .id(adjustedIndex)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .onChange(of: selection) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func colorMatches(_ color1: Color, _ color2: Color) -> Bool {
        let storable1 = color1.toStorableColor()
        let storable2 = color2.toStorableColor()
        
        return abs(storable1.red - storable2.red) < 0.1 &&
               abs(storable1.green - storable2.green) < 0.1 &&
               abs(storable1.blue - storable2.blue) < 0.1
    }
}

struct AboutView: View {
    let themeSettings: ThemeSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "about.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            VStack(alignment: .center, spacing: 12) {
                Spacer()
                
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                
                VStack(spacing: 4) {
                    Text(String(localized: "app.name"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    
                    Text(String(localized: "about.version").replacingOccurrences(of: "%@",
                        with: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                        .font(.system(size: 11))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    
                    Text(String(localized: "about.description"))
                        .font(.system(size: 10))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                        .padding(.top, 4)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ScreenSizeSelectionView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.screenSize"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Auto option
                        HStack {
                            if selection == 0 {
                                Rectangle()
                                    .fill(themeSettings.currentTheme.highlightColor)
                                    .overlay {
                                        HStack {
                                            Image(systemName: themeSettings.useAutoScreenSize ? "checkmark" : "")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                .frame(width: 12)
                                            Text("Auto (Match Theme)")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            Spacer()
                                        }
                                        .padding(.leading, 8)
                                    }
                                    .selectionBarRefraction()
                            } else {
                                HStack {
                                    Image(systemName: themeSettings.useAutoScreenSize ? "checkmark" : "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                        .frame(width: 12)
                                    Text("Auto (Match Theme)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                    Spacer()
                                }
                                .padding(.leading, 8)
                            }
                        }
                        .frame(height: 28)
                        .id(0)
                        
                        // Manual size options
                        ForEach(Array(ScreenSize.allCases.enumerated()), id: \.offset) { index, screenSize in
                            let adjustedIndex = index + 1
                            HStack {
                                if selection == adjustedIndex {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                Image(systemName: !themeSettings.useAutoScreenSize && themeSettings.screenSize == screenSize ? "checkmark" : "")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                    .frame(width: 12)
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(screenSize.rawValue)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                    Text("\(Int(screenSize.dimensions.width))×\(Int(screenSize.dimensions.height))")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.8))
                                                }
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        Image(systemName: !themeSettings.useAutoScreenSize && themeSettings.screenSize == screenSize ? "checkmark" : "")
                                            .font(.system(size: 10))
                                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                            .frame(width: 12)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(screenSize.rawValue)
                                                .font(.system(size: 13))
                                                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                            Text("\(Int(screenSize.dimensions.width))×\(Int(screenSize.dimensions.height))")
                                                .font(.system(size: 9))
                                                .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                        }
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            .frame(height: 32)
                            .id(adjustedIndex)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .onChange(of: selection) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct ScrollSensitivityView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.scrollSensitivity"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider()
                .background(themeSettings.currentTheme.dividerColor)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(ScrollSensitivity.allCases.enumerated()), id: \.offset) { index, sensitivity in
                    HStack {
                        if selection == index {
                            Rectangle()
                                .fill(themeSettings.currentTheme.highlightColor)
                                .overlay {
                                    HStack {
                                        Image(systemName: themeSettings.scrollSensitivity == sensitivity ? "checkmark" : "")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            .frame(width: 12)
                                        Text(sensitivity.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                                .selectionBarRefraction()
                        } else {
                            HStack {
                                Image(systemName: themeSettings.scrollSensitivity == sensitivity ? "checkmark" : "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                    .frame(width: 12)
                                Text(sensitivity.rawValue)
                                    .font(.system(size: 14))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                Spacer()
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .frame(height: 28)
                    .id(index)
                }
            }

            Spacer()
        }
    }
}


struct ClickSoundSelectionView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    private let options = [String(localized: "settings.clickSound.on"), String(localized: "settings.clickSound.off")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.clickSound"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider()
                .background(themeSettings.currentTheme.dividerColor)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let isActive = index == 0 ? themeSettings.clickSoundEnabled : !themeSettings.clickSoundEnabled
                    HStack {
                        if selection == index {
                            Rectangle()
                                .fill(themeSettings.currentTheme.highlightColor)
                                .overlay {
                                    HStack {
                                        Image(systemName: isActive ? "checkmark" : "")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            .frame(width: 12)
                                        Text(option)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                                .selectionBarRefraction()
                        } else {
                            HStack {
                                Image(systemName: isActive ? "checkmark" : "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                    .frame(width: 12)
                                Text(option)
                                    .font(.system(size: 14))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                Spacer()
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .frame(height: 28)
                }
            }

            Spacer()
        }
    }
}

struct BacklightDurationSelectionView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "settings.backlight"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(BacklightDuration.allCases.enumerated()), id: \.offset) { index, duration in
                    let isActive = themeSettings.backlightDuration == duration
                    HStack {
                        if selection == index {
                            Rectangle()
                                .fill(themeSettings.currentTheme.highlightColor)
                                .overlay {
                                    HStack {
                                        Image(systemName: isActive ? "checkmark" : "")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            .frame(width: 12)
                                        Text(duration.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                }
                                .selectionBarRefraction()
                        } else {
                            HStack {
                                Image(systemName: isActive ? "checkmark" : "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                    .frame(width: 12)
                                Text(duration.rawValue)
                                    .font(.system(size: 14))
                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                Spacer()
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .frame(height: 28)
                    .id(index)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            SettingsView(selection: .constant(0), themeSettings: ThemeSettings())
                .frame(width: 280, height: 200)
                .background(Color(red: 0.7, green: 0.85, blue: 0.7))
                .cornerRadius(12)
        }
    }
}
