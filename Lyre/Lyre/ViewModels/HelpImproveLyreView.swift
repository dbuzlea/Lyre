//
//  HelpImproveLyreView.swift
//  Lyre
//

import SwiftUI

/// The one-time question (DiagnosticsConsent): two switches, each off unless already on,
/// each saying what it sends; Done keeps whatever's chosen.
struct HelpImproveLyreView: View {
    let onDone: (_ diagnostics: Bool, _ usage: Bool) -> Void

    @State private var diagnostics = ProblemReporter.sendsAutomatically
    @State private var usage = UsageStats.isEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text(String(localized: "diagnostics.ask.message"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Toggle(isOn: $diagnostics) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.sendDiagnostics"))
                            Text(String(localized: "settings.sendDiagnostics.detail"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("helpImprove.diagnostics")
                    Toggle(isOn: $usage) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.shareUsage"))
                            Text(String(localized: "settings.shareUsage.detail"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("helpImprove.usage")
                } footer: {
                    Link(String(localized: "diagnostics.ask.privacyPolicy"), destination: ProblemReporter.privacyPolicyURL)
                }
            }
            .navigationTitle(String(localized: "diagnostics.ask.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "diagnostics.ask.done")) { onDone(diagnostics, usage) }
                        .accessibilityIdentifier("helpImprove.done")
                }
            }
        }
    }
}
