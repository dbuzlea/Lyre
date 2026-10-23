//
//  MainMenuView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

// MARK: - Main Menu
//
// The root Lyre menu showing twelve items: Now Playing → Queue → Songs → Recently Added →
// Recently Played → Albums → Artists → Playlists → Podcasts → Search → Change Player →
// Settings. Change Player opens the list of players Settings has, one press closer.
// ScrollWheelView maps each position to its screen, so the two must change together.
//
// Selection is driven entirely by the parent (ScrollWheelView) via a binding; this
// view is display-only. A ScrollViewReader keeps the selected row scrolled to
// center so it never leaves the visible area as the user spins the wheel.
//
// Battery status is monitored via NotificationCenter observers (level + state
// change notifications) and shown as a SF Symbol icon in the title bar. Monitoring
// is enabled on appear and disabled on disappear to avoid unnecessary background
// updates. The simulator always reports -1 for battery level, which is normalised
// to 1.0 (100%) to avoid the low-battery icon in previews.
struct MainMenuView: View {
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @State private var batteryLevel: Float = 1.0
    @State private var batteryState: UIDevice.BatteryState = .unknown
    
    /// Shared with ScrollWheelView, which reads the highlighted item out to VoiceOver.
    static let items = [
        String(localized: "menu.nowPlaying"),
        String(localized: "menu.queue"),
        String(localized: "menu.songs"),
        String(localized: "menu.recentlyAdded"),
        String(localized: "menu.recentlyPlayed"),
        String(localized: "menu.albums"),
        String(localized: "menu.artists"),
        String(localized: "menu.playlists"),
        String(localized: "menu.podcasts"),
        String(localized: "menu.search"),
        String(localized: "menu.changePlayer"),
        String(localized: "menu.settings")
    ]

    private var menuItems: [String] { Self.items }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "app.name"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
                Image(systemName: batteryIconName)
                    .font(.system(size: 12))
                    .foregroundStyle(batteryColor)
            }
            .padding(.bottom, 8)
            .onAppear {
                startMonitoringBattery()
            }
            .onDisappear {
                stopMonitoringBattery()
            }
            
            Divider()
                .background(themeSettings.currentTheme.dividerColor)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<menuItems.count, id: \.self) { index in
                            HStack {
                                if selection == index {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                Text(menuItems[index])
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        Text(menuItems[index])
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
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: selection) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Battery Helpers
    
    private var batteryIconName: String {
        AppHelpers.batteryIconName(level: batteryLevel, state: batteryState)
    }

    private var batteryColor: Color {
        AppHelpers.batteryIsLow(level: batteryLevel, state: batteryState)
            ? .red
            : themeSettings.currentTheme.screenTextColor
    }
    
    private func startMonitoringBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryInfo()
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateBatteryInfo()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateBatteryInfo()
        }
    }
    
    private func stopMonitoringBattery() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }
    
    private func updateBatteryInfo() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        
        // If battery level is unknown (simulator), default to 100%
        if batteryLevel < 0 {
            batteryLevel = 1.0
        }
    }
}
