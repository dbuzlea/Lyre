//
//  TestDevice.swift
//  LyreUITests
//
//  What a UI test needs to know about the phone it's on, so the same tests hold on a
//  simulator and on a real iPhone Duo.
//

import XCTest
import UIKit

extension XCUIApplication {
    /// The screen Lyre is on, as a picture.
    ///
    /// An iPhone Duo has two displays, and `screenshot()` can take the one that's dark
    /// (on EDITH it came back black every time). So every display is taken, and the
    /// brightest kept: the one Lyre is drawing on.
    func lyreScreenshot() -> XCUIScreenshot {
        let candidates = [screenshot()] + XCUIScreen.screens.map { $0.screenshot() }
        return candidates.max { $0.image.lyreBrightness < $1.image.lyreBrightness } ?? screenshot()
    }

    /// The window's safe area as Lyre measured it (ContentView reports it to UI tests),
    /// or nil before it's known.
    var lyreSafeArea: UIEdgeInsets? {
        let element = descendants(matching: .any)["lyre.uitest.safeArea"].firstMatch
        guard element.waitForExistence(timeout: 5),
              let value = element.value as? String else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return UIEdgeInsets(top: parts[0], left: parts[1], bottom: parts[2], right: parts[3])
    }

    /// How wide the status bar's column down the right edge is, on a phone that keeps it
    /// there (an iPhone Duo closed, or held open as a book); nil on one that keeps it
    /// across the top.
    var lyreSideStatusColumn: CGFloat? {
        guard let inset = lyreSafeArea, inset.right >= 40 else { return nil }
        return inset.right
    }
}

private extension UIImage {
    /// How bright the picture is overall, 0 (black) to 1, from a few pixels' worth.
    var lyreBrightness: Double {
        guard let cgImage else { return 0 }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
        }
        return Double(total) / Double(side * side * 3 * 255)
    }
}

extension XCUIApplication {
    /// On a real iPhone Duo, skips a test asking for the other posture than the phone's
    /// in: `-SpoolFoldPosture` can tell Lyre it's open, but not make the window the open
    /// screen's size, so the test would only fail in the wrong layout. A test that asks
    /// for none means closed. Nothing is skipped without a hinge (a simulator, any other
    /// iPhone), where the posture asked for is simply stood in for.
    func skipUnlessTheHingeAgrees() throws {
        let element = descendants(matching: .any)["lyre.uitest.hinge"].firstMatch
        guard element.waitForExistence(timeout: 5), let hinge = element.value as? String, hinge != "none" else { return }
        var asked = "closed"
        if let index = launchArguments.firstIndex(of: "-SpoolFoldPosture"), launchArguments.indices.contains(index + 1) {
            asked = launchArguments[index + 1]
        }
        if asked != hinge {
            throw XCTSkip("This test is for an iPhone Duo \(asked); the phone is \(hinge)")
        }
    }
}
