//
//  RecordIndexStrip.swift
//  Lyre
//

import SwiftUI

// MARK: - Record Index Strip
//
// The A–Z index along the drawer's front, under the stack (see RecordStackView): the
// shared ShelfIndexStrip in brass and cream serif, putting the first record filed under
// a letter on top of the stack. The Spool's rack has the same strip down its side.

struct RecordIndexStrip: View {
    let albums: [AppAlbum]
    @Binding var frontID: String?
    @Environment(\.gramophoneTheme) private var theme

    var body: some View {
        ShelfIndexStrip(titles: albums.map(\.title),
                        currentIndex: albums.firstIndex { $0.id == frontID } ?? 0,
                        style: .gramophone(theme),
                        accessibilityID: "gramophone.index") { index in
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            withTransaction(instant) { frontID = albums[index].id }
        }
    }
}
