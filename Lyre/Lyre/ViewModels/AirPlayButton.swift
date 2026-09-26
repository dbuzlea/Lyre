//
//  AirPlayButton.swift
//  Lyre
//

import SwiftUI
import AVKit

// MARK: - AirPlay Button
//
// A small AirPlay glyph that opens the system route picker when tapped. The system
// offers no way to open that picker in code, so this is a touch target rather than
// something the scroll wheel can reach.
//
// AVRoutePickerView draws its glyph at a fixed size whatever frame it is given, which
// is far too big for the footer. So the glyph is drawn here as an SF Symbol at `size`,
// and the picker sits over it with a clear tint: invisible, but still the thing that
// receives the tap. Its touch area is a little larger than the glyph so the small
// footer version stays easy to hit, and it is an overlay so it never affects layout.
//
// It is only shown when there is somewhere to send audio, or when audio is already on
// an AirPlay device (so there is always a way back to the phone). While hidden it keeps
// a zero-size placeholder so onAppear / onDisappear still bracket route detection.
struct AirPlayButton: View {
    @ObservedObject var routeMonitor: AudioRouteMonitor = .shared
    let themeSettings: ThemeSettings
    /// Glyph size in points. The default matches the Now Playing title bar text.
    var size: CGFloat = 12

    private var isVisible: Bool {
        routeMonitor.multipleRoutesDetected || routeMonitor.airPlayDeviceName != nil
    }

    private var isActive: Bool { routeMonitor.airPlayDeviceName != nil }

    var body: some View {
        Group {
            if isVisible {
                Image(systemName: "airplayaudio")
                    .font(.system(size: size))
                    .foregroundStyle(isActive
                        ? themeSettings.currentTheme.highlightColor
                        : themeSettings.currentTheme.screenTextColor)
                    .frame(width: size, height: size)
                    .overlay {
                        RoutePickerRepresentable()
                            .frame(width: max(size, 24), height: max(size, 24))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("airplay.button")
            } else {
                Color.clear.frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { routeMonitor.beginDetection() }
        .onDisappear { routeMonitor.endDetection() }
    }

    private var accessibilityLabel: String {
        if let device = routeMonitor.airPlayDeviceName {
            return String(format: String(localized: "airPlay.playingOn"), device)
        }
        return String(localized: "airPlay.label")
    }
}

// MARK: - Route Picker

/// The system route picker with its own glyph hidden. Clear tint rather than zero
/// alpha, because UIKit stops delivering touches to views that are fully transparent.
private struct RoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        // Lyre is audio only; keep speakers at the top of the list.
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
