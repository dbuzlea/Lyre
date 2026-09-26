//
//  GatefoldControlsUITests.swift
//  LyreUITests
//

import XCTest

/// Drives the gatefold's controls on a device with a real music library.
///
/// This exists because the left-hand panel's Play, Shuffle and disc have repeatedly
/// looked dead while the right-hand panel worked, and reading the layout has not been
/// enough to say why. The test is written to be **diagnostic first**: for every control
/// it records three things before touching anything —
///
///   * `exists`    — is it in the accessibility tree at all? No ⇒ it is not being built,
///                   or an ancestor is hiding it from accessibility.
///   * `isHittable` — will a touch at its centre actually reach it? Exists but not
///                   hittable ⇒ a layout or hit-testing fault, not a wiring fault.
///   * `frame`     — where the system thinks it is. Compare against where it is drawn
///                   to catch a control answering in the wrong place.
///
/// Only then does it tap, and each tap is verified against observable state rather than
/// against "no crash": every control here changes a label, so a tap that does nothing is
/// a tap that failed.
///
/// `continueAfterFailure` is on so one dead control does not mask the state of the
/// others — a run should report on all three.
final class GatefoldControlsUITests: XCTestCase {

    // Mirrors `GatefoldID` in the app target.
    private enum ID {
        static let cover = "gatefold.cover"
        static let disc = "gatefold.disc"
        static let play = "gatefold.play"
        static let shuffle = "gatefold.shuffle"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - The Test

    @MainActor
    func testGatefoldLeftPanelControlsRespondToTaps() throws {
        let app = try openGatefold()

        // Geometry first, while nothing has been touched.
        attach(app.debugDescription, named: "element-tree-gatefold-open")
        let play = report(app, ID.play, "Play/Pause pill")
        let shuffle = report(app, ID.shuffle, "Shuffle pill")
        let disc = report(app, ID.disc, "Disc")

        // 1. Play starts playback. The pill relabels itself Pause, which is the only
        //    signal available from outside the app.
        let playLabel = play.label
        let playMessage = tapAndCaptureMessage(play, in: app, step: "1-play")
        XCTAssertTrue(
            waitForLabel(play, toChangeFrom: playLabel),
            failure("Play pill", label: playLabel, message: playMessage, element: play)
        )

        // 2. The same control pauses again, so this is a toggle rather than a one-shot.
        let pauseLabel = play.label
        let pauseMessage = tapAndCaptureMessage(play, in: app, step: "2-pause")
        XCTAssertTrue(
            waitForLabel(play, toChangeFrom: pauseLabel),
            failure("Play pill (second tap)", label: pauseLabel, message: pauseMessage, element: play)
        )

        // 3. Shuffle. Checked from a paused state so the assertion is unambiguous:
        //    shuffling starts playback, so the Play pill must end up reading Pause.
        pause(play)
        let shuffleMessage = tapAndCaptureMessage(shuffle, in: app, step: "3-shuffle")
        XCTAssertTrue(
            waitForLabel(play, toBe: "Pause"),
            failure("Shuffle pill", label: play.label, message: shuffleMessage, element: shuffle)
        )

        // 4. The disc is the same action as the Play pill, so it must toggle too.
        let discLabel = disc.label
        let discMessage = tapAndCaptureMessage(disc, in: app, step: "4-disc")
        XCTAssertTrue(
            waitForLabel(disc, toChangeFrom: discLabel),
            failure("Disc", label: discLabel, message: discMessage, element: disc)
        )

        attach(app.debugDescription, named: "element-tree-after-taps")
    }

    // MARK: - Tap Evidence

    /// Every message the gatefold shows when a tap cannot start playback.
    private static let failureMessages = [
        "Nothing here can be played",
        "That song can't be played",
    ]

    /// Taps, then immediately looks for the app's toast and snapshots the tree.
    ///
    /// The toast lives for 1.6 s, so it has to be read straight after the tap — by the
    /// time the label wait times out it has gone, which is how the last run failed all
    /// four steps without saying why.
    @MainActor
    private func tapAndCaptureMessage(_ element: XCUIElement, in app: XCUIApplication, step: String) -> String? {
        let traceBefore = trace(in: app)
        element.tap()
        let message = Self.failureMessages.first { app.staticTexts[$0].exists }

        // Playback outcomes arrive asynchronously, so give the trace time to move
        // rather than reading it once straight after the tap.
        let traceElement = app.staticTexts["gatefold.trace"]
        _ = expect(NSPredicate(format: "label != %@", traceBefore), on: traceElement, timeout: 5)
        lastTrace = trace(in: app)
        traceMovedOnLastTap = lastTrace != traceBefore

        attach(app.debugDescription, named: "element-tree-after-\(step)")
        attach("toast: \(message ?? "none")\ntrace: \(lastTrace)", named: "evidence-\(step)")
        return message
    }

    /// What the app says its gatefold actions did, oldest first.
    @MainActor
    private func trace(in app: XCUIApplication) -> String {
        let element = app.staticTexts["gatefold.trace"]
        return element.exists ? element.label : "trace element missing"
    }

    private var lastTrace = ""
    private var traceMovedOnLastTap = false

    /// Distinguishes the ways a tap can fail, because they need different fixes.
    private func failure(_ name: String, label: String, message: String?, element: XCUIElement) -> String {
        if !traceMovedOnLastTap {
            return """
            \(name): the action never ran — the app recorded nothing for this tap. The \
            touch lands on an element that is hittable but its Button action is not \
            called. hittable=\(element.isHittable) frame=\(element.frame) trace: \(lastTrace)
            """
        }
        if let message {
            return """
            \(name): the action ran and the app refused to play — it showed "\(message)". \
            trace: \(lastTrace)
            """
        }
        return """
        \(name): the action ran but the label did not change. The app's own record of \
        what happened: \(lastTrace)
        """
    }

    /// Reports the controls without touching them, for a clean read of the geometry
    /// even if the tapping test above goes wrong somewhere earlier.
    @MainActor
    func testGatefoldLeftPanelControlsAreHittable() throws {
        let app = try openGatefold()

        attach(app.debugDescription, named: "element-tree")
        report(app, ID.play, "Play/Pause pill")
        report(app, ID.shuffle, "Shuffle pill")
        report(app, ID.disc, "Disc")

        // The right panel works, so it is the control group to compare against: if
        // these are hittable and the left panel's are not, the fault is on the left.
        let liner = app.scrollViews.firstMatch
        attach("liner scroll view: exists=\(liner.exists) frame=\(liner.frame)", named: "right-panel")
    }

    // MARK: - Long-Press Queueing

    /// Touch and hold on a closed cover must queue the record *without* opening it,
    /// and must leave the cover usable afterwards — the menu cancels the cover's own
    /// gesture, which once left it stuck in its lifted state.
    @MainActor
    func testLongPressOnClosedCoverQueuesTheRecord() throws {
        let (app, cover) = try launchIntoCarousel()

        cover.press(forDuration: 1.0)

        let addToQueue = app.buttons["Add to Queue"]
        guard addToQueue.waitForExistence(timeout: 5) else {
            attach(app.debugDescription, named: "element-tree-no-menu")
            XCTFail("Touch and hold on the cover did not show the queue menu")
            return
        }
        XCTAssertTrue(app.buttons["Play Next"].exists, "The menu is missing Play Next")

        addToQueue.tap()

        // The app's own record, not the toast. The toast *was* on screen in an earlier
        // run ("Playing: …") but never reached the element tree while the menu was
        // dismissing, and it only lives 1.6 s anyway. The trace stays put.
        let traceElement = app.staticTexts["gatefold.trace"]
        let recorded = expect(
            NSPredicate(format: "label CONTAINS 'queue last:'"), on: traceElement, timeout: 10
        )
        let traceAfterQueue = trace(in: app)
        attach("trace: \(traceAfterQueue)", named: "evidence-long-press")
        XCTAssertTrue(recorded, "Choosing Add to Queue never reached the app. trace: \(traceAfterQueue)")
        XCTAssertFalse(
            traceAfterQueue.contains("unavailable"),
            "The record could not be queued. trace: \(traceAfterQueue)"
        )
        // Asked of the app rather than the element tree: the closed sleeve's hidden
        // interior used to put a Play button in the tree, so "Play exists" could not tell
        // an open sleeve from a closed one.
        XCTAssertFalse(
            traceAfterQueue.contains("open"),
            "The long press opened the sleeve as well as showing the menu. trace: \(traceAfterQueue)"
        )

        // And the cover still opens with an ordinary tap.
        cover.tap()
        XCTAssertTrue(
            expect(NSPredicate(format: "label CONTAINS 'open'"), on: traceElement, timeout: 5),
            "After the long press, tapping the cover no longer opened the sleeve. trace: \(trace(in: app))"
        )
        XCTAssertTrue(
            app.buttons[ID.play].waitForExistence(timeout: 10),
            "The sleeve opened but its controls never appeared"
        )
    }

    // MARK: - Setup

    /// Launches, rotates into the carousel and opens the centred sleeve.
    ///
    /// Skips rather than fails when the device has no albums: an empty library is not
    /// a bug in the controls, and a red test would say the wrong thing.
    @MainActor
    private func openGatefold() throws -> XCUIApplication {
        let (app, cover) = try launchIntoCarousel()
        cover.tap()

        // The hinge spring runs for roughly 0.85 s; the controls only exist once the
        // spread has settled.
        guard app.buttons[ID.play].waitForExistence(timeout: 10) else {
            attach(app.debugDescription, named: "element-tree-sleeve-did-not-open")
            XCTFail("The sleeve did not open, or it opened without its Play control")
            throw XCTSkip("Cannot test the controls: the sleeve never opened.")
        }

        // Existing is not enough: the controls appear while the hinge is still landing,
        // at a fraction of their final size and partly off-screen. Measuring or tapping
        // then reports failures the app is not responsible for — the first tap of one
        // run landed on no point at all. Wait until they are really where they belong.
        let settled = NSPredicate(format: "hittable == true")
        for id in [ID.play, ID.shuffle, ID.disc] {
            _ = expect(settled, on: app.buttons[id], timeout: 10)
        }

        // While the hinge animates, the settled spread already exists underneath it,
        // invisible, so the sleeve and the spread both carry a copy of each control.
        // Only one remains once the animation lands, which is the state to measure.
        let landed = Date().addingTimeInterval(5)
        while app.buttons.matching(identifier: ID.play).count > 1, Date() < landed {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return app
    }

    /// Launches and rotates into the carousel, returning the centred, closed cover.
    @MainActor
    private func launchIntoCarousel() throws -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        // `--uitest` stands down the never-ending animations. Without it the spinning
        // disc keeps the app from ever being quiescent, and XCUITest waits out its idle
        // timeout before every query.
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding"]
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            for label in ["Allow", "OK", "Continue"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()

        guard app.buttons["Scroll wheel"].waitForExistence(timeout: 15) else {
            throw XCTSkip("The Lyre interface never appeared; onboarding may not be complete on this device.")
        }

        // Landscape is what presents the carousel — the same path a person takes.
        XCUIDevice.shared.orientation = .landscapeLeft

        let cover = app.buttons[ID.cover]
        guard cover.waitForExistence(timeout: 15) else {
            attach(app.debugDescription, named: "element-tree-no-carousel")
            throw XCTSkip("No album cover appeared in landscape — this device's library may have no albums.")
        }

        return (app, cover)
    }

    // MARK: - Diagnostics

    /// Records how many copies exist, plus hittability and frame, and asserts on all
    /// three.
    ///
    /// The count matters as much as the rest: a control built twice — once by the
    /// animation and once by the settled spread — leaves two identical elements, and a
    /// touch can land on whichever the system prefers. That is invisible on screen,
    /// because the two are drawn in the same place.
    @MainActor
    @discardableResult
    private func report(_ app: XCUIApplication, _ identifier: String, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(identifier: identifier)
        let count = matches.count
        let element = matches.firstMatch

        let exists = count > 0
        let hittable = exists && element.isHittable
        let frame = exists ? "\(element.frame)" : "n/a"
        let summary = "\(name): copies=\(count) hittable=\(hittable) frame=\(frame)"

        attach(summary, named: name)
        XCTContext.runActivity(named: summary) { _ in }

        XCTAssertGreaterThan(count, 0, "\(name) is not in the accessibility tree at all")
        XCTAssertLessThanOrEqual(
            count, 1,
            """
            \(name) exists \(count) times. The control is being built more than once — \
            most likely the animated sleeve and the settled spread are both on screen — \
            so a touch may be going to the copy that cannot receive it.
            """
        )
        XCTAssertTrue(
            hittable,
            """
            \(name) exists but is not hittable. A touch at its centre does not reach it, \
            so this is geometry rather than wiring — it is drawn somewhere other than \
            \(frame), or something transparent is sitting over it.
            """
        )
        return element
    }

    @MainActor
    private func pause(_ play: XCUIElement) {
        guard play.label == "Pause" else { return }
        play.tap()
        _ = waitForLabel(play, toBe: "Play")
    }

    @MainActor
    private func waitForLabel(
        _ element: XCUIElement,
        toChangeFrom old: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        expect(NSPredicate(format: "label != %@", old), on: element, timeout: timeout)
    }

    @MainActor
    private func waitForLabel(
        _ element: XCUIElement,
        toBe expected: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        expect(NSPredicate(format: "label == %@", expected), on: element, timeout: timeout)
    }

    private func expect(_ predicate: NSPredicate, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func attach(_ string: String, named name: String) {
        let attachment = XCTAttachment(string: string)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
