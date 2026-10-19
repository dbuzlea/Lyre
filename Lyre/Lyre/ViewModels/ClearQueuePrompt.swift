//
//  ClearQueuePrompt.swift
//  Lyre
//

import SwiftUI

// MARK: - Clear Queue Prompt
//
// Asks before Up Next is emptied, as every player does: the Classic player's Clear Queue
// row and the Clear button on the Spool's and the Gramophone's Up Next tray. It says how
// many songs would go, and that what's playing keeps playing; Clear Queue is marked
// destructive, and Cancel leaves the queue as it was.
//
// Playing something new — an album, a playlist, a song from a list, a shuffle of every
// song — replaces Up Next too, so `replaceQueuePrompt` asks the same question first when
// the listener has queued songs of their own (`MusicService.listenerQueuedCount`). The
// rest of a record carrying on isn't asked about: moving from one album to the next is
// what playing something is for.

extension View {
    /// Shows the prompt while `isPresented`; `onClear` runs only if the user confirms.
    func clearQueuePrompt(isPresented: Binding<Bool>, count: Int, onClear: @escaping () -> Void) -> some View {
        alert(String(localized: "queue.clear.confirm.title"), isPresented: isPresented) {
            Button(String(localized: "queue.clear"), role: .destructive, action: onClear)
            Button(String(localized: "queue.clear.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(count == 1
                 ? String(localized: "queue.clear.confirm.message.one")
                 : String(format: String(localized: "queue.clear.confirm.message"), count))
        }
    }
}

// MARK: - Replace Queue Prompt
//
// The app's own dialog rather than an alert, so it can hold a close button: Clear and
// Play (destructive) goes ahead; Add to Queue puts what was chosen at the end of Up Next
// instead, leaving what's playing alone; the ✕ in the corner, or Escape, cancels. A show's
// episodes can't be queued, so for them there is no Add to Queue.

/// Something about to play that would clear what the listener queued, waiting for them
/// to say so.
struct PendingPlay: Identifiable {
    let id = UUID()
    let action: () -> Void
    /// Queues what was chosen instead of playing it, in the player's own words; nil when
    /// it can't be queued (a podcast's episodes).
    var addToQueue: (() -> Void)?
    /// Puts back whatever was set going for the play, if the listener says no.
    var onCancel: () -> Void = {}
}

extension MusicService {
    /// Runs `play` now, or, when it would clear songs the listener queued, hands it to
    /// `ask` to be held until they choose: play it, queue it instead (`addToQueue`), or
    /// neither.
    func play(asking ask: (PendingPlay) -> Void, addToQueue: (() -> Void)?, _ play: @escaping () -> Void) {
        if listenerQueuedCount > 0 {
            ask(PendingPlay(action: play, addToQueue: addToQueue))
        } else {
            play()
        }
    }
}

extension View {
    /// Asks before `pending` plays: it would clear the `count` songs the listener queued.
    /// Attach where it can cover the whole screen.
    func replaceQueuePrompt(_ pending: Binding<PendingPlay?>, count: Int) -> some View {
        overlay {
            if let play = pending.wrappedValue {
                ReplaceQueueDialog(count: count, canQueue: play.addToQueue != nil) { choice in
                    pending.wrappedValue = nil
                    switch choice {
                    case .play:    play.action()
                    case .queue:   play.addToQueue?()
                    case .cancel:  play.onCancel()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: pending.wrappedValue?.id)
    }
}

private struct ReplaceQueueDialog: View {
    enum Choice { case play, queue, cancel }

    let count: Int
    let canQueue: Bool
    let onChoose: (Choice) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(String(localized: "queue.replace.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(count == 1
                         ? String(localized: "queue.replace.message.one")
                         : String(format: String(localized: "queue.replace.message"), count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)
                .padding(.top, 22)
                .padding(.bottom, 18)

                VStack(spacing: 8) {
                    choiceButton(String(localized: "queue.replace.confirm"), role: .destructive, id: "queue.replace.play") {
                        onChoose(.play)
                    }
                    if canQueue {
                        choiceButton(String(localized: "queue.action.addToQueue"), role: nil, id: "queue.replace.queue") {
                            onChoose(.queue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { onChoose(.cancel) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel(String(localized: "queue.clear.confirm.cancel"))
                .accessibilityIdentifier("queue.replace.cancel")
            }
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("queue.replace")
            .accessibilityAction(.escape) { onChoose(.cancel) }
        }
    }

    private func choiceButton(_ title: String, role: ButtonRole?, id: String, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
        .accessibilityIdentifier(id)
    }
}
