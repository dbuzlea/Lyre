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
    /// Gathering the files takes a moment (reading this session's system log can take
    /// a few seconds), so a "Preparing diagnostics…" panel shows from the tap until the
    /// share sheet is up; meanwhile a second tap does nothing.
    @MainActor private static var isPreparing = false

    @MainActor
    static func share() {
        guard !isPreparing, let window = keyWindow else { return }
        isPreparing = true
        Diagnostics.shared.record(.app, "Diagnostics shared", level: .info)
        UsageStats.shared.used(.shareDiagnostics)
        let panel = PreparingPanel.show(in: window)
        Task {
            let files = await Task.detached(priority: .userInitiated) { await Diagnostics.shared.exportFiles() }.value
            guard var top = window.rootViewController else {
                panel.dismiss()
                isPreparing = false
                return
            }
            while let presented = top.presentedViewController { top = presented }
            let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
            // On an iPad-sized window the sheet needs somewhere to point.
            sheet.popoverPresentationController?.sourceView = top.view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                                                     width: 1, height: 1)
            // The panel goes as the sheet comes up, not before: no gap with neither.
            top.present(sheet, animated: true) {
                panel.dismiss()
                isPreparing = false
            }
        }
    }

    @MainActor private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }
}

/// A small panel in the middle of the window, a spinner over "Preparing diagnostics…",
/// that also keeps taps from reaching what's under it while it's up.
@MainActor
private final class PreparingPanel {
    private let cover: UIView

    private init(cover: UIView) { self.cover = cover }

    static func show(in window: UIWindow) -> PreparingPanel {
        let cover = UIView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        cover.accessibilityViewIsModal = true

        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        panel.layer.cornerRadius = 18
        panel.clipsToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        let label = UILabel()
        label.text = String(localized: "diagnostics.preparing")
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        cover.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -26),
        ])
        panel.isAccessibilityElement = true
        panel.accessibilityLabel = String(localized: "diagnostics.preparing")
        panel.accessibilityIdentifier = "diagnostics.preparing"

        cover.alpha = 0
        window.addSubview(cover)
        UIView.animate(withDuration: 0.15) { cover.alpha = 1 }
        UIAccessibility.post(notification: .announcement, argument: String(localized: "diagnostics.preparing"))
        return PreparingPanel(cover: cover)
    }

    func dismiss() {
        UIView.animate(withDuration: 0.15, animations: { self.cover.alpha = 0 }) { _ in self.cover.removeFromSuperview() }
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
