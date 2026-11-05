//
//  ReportProblemView.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Report a Problem
//
// Every player's settings offer Report a Problem: a few words about what went wrong,
// and, if the listener wants, a picture of the screen they were on, sent with Lyre's
// diagnostics to the relay, which files it in Jira (ProblemReporter). The picture is
// taken as the form opens, of the screen behind it, so it shows what they were looking
// at, not the form; and it's only sent if they leave it switched on.

enum ProblemReporting {
    @MainActor
    static func present() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let controller = UIHostingController(rootView: ReportProblemView(screenshot: screenshot) {
            top.dismiss(animated: true)
        })
        Diagnostics.shared.record(.app, "Report a Problem opened", level: .info)
        UsageStats.shared.used(.reportProblem)
        top.present(controller, animated: true)
    }
}

struct ReportProblemView: View {
    let screenshot: UIImage?
    let onDone: () -> Void

    @State private var text = ""
    @State private var includesScreenshot = true
    @State private var isSent = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "report.placeholder"), text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($isFocused)
                        .accessibilityIdentifier("report.text")
                } header: {
                    Text(String(localized: "report.what"))
                }
                if let screenshot {
                    Section {
                        Toggle(String(localized: "report.includeScreenshot"), isOn: $includesScreenshot)
                            .accessibilityIdentifier("report.includeScreenshot")
                        if includesScreenshot {
                            Image(uiImage: screenshot)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(String(localized: "report.screenshot"))
                        }
                    }
                }
                Section {
                    Text(String(localized: "report.whatsSent"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(String(localized: "report.privacyPolicy"), destination: ProblemReporter.privacyPolicyURL)
                        .font(.footnote)
                        .accessibilityIdentifier("report.privacyPolicy")
                }
            }
            .navigationTitle(String(localized: "report.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "report.cancel"), action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "report.send"), action: send)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("report.send")
                }
            }
            .alert(String(localized: "report.thanks"), isPresented: $isSent) {
                Button(String(localized: "report.done"), action: onDone)
            } message: {
                Text(String(localized: ProblemReporter.shared.isConfigured ? "report.thanks.detail" : "report.thanks.later"))
            }
            .onAppear { isFocused = true }
        }
    }

    private func send() {
        var files: [ProblemReporter.Report.File] = []
        if includesScreenshot, let data = screenshot?.jpegData(compressionQuality: 0.6) {
            files.append(.init(name: "screenshot.jpg", contentType: "image/jpeg", base64: data.base64EncodedString()))
        }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = words.split(separator: "\n").first.map { String($0.prefix(80)) } ?? "Problem"
        let report = ProblemReporter.shared.makeReport(kind: .user, title: title, description: words, files: files)
        ProblemReporter.shared.submit(report)
        isSent = true
    }
}

/// The settings' Report a Problem, drawn by each player in its own style (`label`).
struct ReportProblemButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { ProblemReporting.present() } label: { label() }
            .accessibilityLabel(String(localized: "settings.reportProblem"))
            .accessibilityHint(String(localized: "settings.reportProblem.detail"))
            .accessibilityIdentifier("settings.reportProblem")
    }
}
