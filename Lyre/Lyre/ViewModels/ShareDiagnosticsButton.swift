//
//  ShareDiagnosticsButton.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Share Diagnostics
//
// Every player's settings offer Share Diagnostics: the share sheet, with what Lyre has
// kept for finding problems (Diagnostics): a summary of this Lyre and phone with this
// session's log, the log files, and iOS's MetricKit reports. Nothing personal is in
// them; nothing leaves the phone until it's shared. Presented from the top-most screen,
// as the library's error is, so it works over any player's own sheets.

enum DiagnosticsSharing {
    @MainActor
    static func share() {
        Diagnostics.shared.record(.app, "Diagnostics shared", level: .info)
        Task {
            let files = await Task.detached(priority: .userInitiated) { await Diagnostics.shared.exportFiles() }.value
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
                  var top = window.rootViewController else { return }
            while let presented = top.presentedViewController { top = presented }
            let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
            // On an iPad-sized window the sheet needs somewhere to point.
            sheet.popoverPresentationController?.sourceView = top.view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                                                     width: 1, height: 1)
            top.present(sheet, animated: true)
        }
    }
}

/// The settings' Share Diagnostics, drawn by each player in its own style (`label`).
struct ShareDiagnosticsButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { DiagnosticsSharing.share() } label: { label() }
            .accessibilityLabel(String(localized: "settings.shareDiagnostics"))
            .accessibilityHint(String(localized: "settings.shareDiagnostics.detail"))
            .accessibilityIdentifier("settings.shareDiagnostics")
    }
}
