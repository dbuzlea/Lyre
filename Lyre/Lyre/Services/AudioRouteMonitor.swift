//
//  AudioRouteMonitor.swift
//  Lyre
//

import AVFoundation
internal import Combine

// MARK: - AudioRouteMonitor
//
// Tracks where audio is going so the UI can offer and describe AirPlay.
//
// Playback runs through MPMusicPlayerController's application queue player, which is
// rendered by the system rather than in-process, so it follows the system output route
// on its own. Nothing here changes the route: picking a device is left entirely to the
// system picker behind AVRoutePickerView. This object only answers two questions:
//
//   • Is there anywhere else to play? (`multipleRoutesDetected`, via AVRouteDetector)
//   • Is audio on an AirPlay device right now, and which? (`airPlayDeviceName`)
//
// Route detection scans the network and costs power, so it only runs while at least
// one AirPlay button is on screen. Buttons call `beginDetection()` / `endDetection()`
// from onAppear / onDisappear, and the count keeps overlapping screens balanced.
final class AudioRouteMonitor: ObservableObject {
    static let shared = AudioRouteMonitor()

    @Published private(set) var multipleRoutesDetected = false
    /// Name of the AirPlay device audio is playing on, or nil when it is playing locally.
    @Published private(set) var airPlayDeviceName: String?

    private let detector = AVRouteDetector()
    private var detectionClients = 0
    private var routesObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    private init() {
        routesObserver = NotificationCenter.default.addObserver(
            forName: .AVRouteDetectorMultipleRoutesDetectedDidChange,
            object: detector, queue: .main
        ) { [weak self] _ in self?.updateMultipleRoutes() }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateCurrentRoute() }

        updateCurrentRoute()
    }

    func beginDetection() {
        detectionClients += 1
        detector.isRouteDetectionEnabled = true
        updateMultipleRoutes()
        updateCurrentRoute()
    }

    func endDetection() {
        detectionClients = max(0, detectionClients - 1)
        if detectionClients == 0 {
            detector.isRouteDetectionEnabled = false
        }
    }

    private func updateMultipleRoutes() {
        multipleRoutesDetected = detector.multipleRoutesDetected
    }

    private func updateCurrentRoute() {
        airPlayDeviceName = AVAudioSession.sharedInstance().currentRoute.outputs
            .first { $0.portType == .airPlay }?
            .portName
    }
}
