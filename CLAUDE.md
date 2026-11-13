# Lyre: working rules for Claude

Lyre is an iOS music player with five players: Classic (a click wheel), Spool (cassettes), Disc (a Discman), Gramophone (3D) and Liquid (bubbles and water). Sources are in `Lyre/Lyre/` (views in `ViewModels/<Player>/`, services in `Services/`). Tests are in `Lyre/LyreTests` (Swift Testing) and `Lyre/LyreUITests` (XCUITest). The Jira triage workflow is in `.claude/skills/jira-triage/SKILL.md`.

The developer works alone on Lyre and is building experience in software QA. Explain QA practice briefly as it comes up (the why, not only the what), and keep the QA setup close to how real teams work.

## The players and what each is for

Decided 2026-11-12 (Apple's Purpose and Simplicity principles). The emotion Lyre is built around is **connection**: with the music, the artists, and the app. Every player keeps the shared features (podcasts, Discover, Up Next, search, both models of the Spool and the Gramophone), but each is *for* one thing, and new work is weighed against it. A feature that serves a player's purpose is polished there first; one that doesn't is kept simple there.

| Player | What it's for |
|---|---|
| Classic | Fast, familiar control of the whole library with one thumb. |
| Spool | Making and playing mixtapes: the personal, handmade side of music. |
| Disc | Sitting with an album from first track to last, booklet in hand. |
| Gramophone | Listening as an occasion: slow, deliberate, one record at a time. |
| Liquid | Wandering and discovering your library and Apple Music. |

## Git, merging and shipping

- Work in `~/Developer/Lyre`. The repo left iCloud Drive on 2026-11-10 after offloaded files stalled git and a commit half-completed. If a git command ever fails oddly, check `git reflog`, `git log`, `.git/HEAD` and the working tree before retrying; never assume it didn't happen. `find . -flags +dataless` lists offloaded files.
- Do each change on its own branch. Once it builds and its tests pass, merge it into the local `main` yourself (`git merge --no-ff`), leave `main` checked out, and build `main` again, so the latest work runs from Xcode without approvals. If tests fail or a conflict isn't obvious, leave the work on its branch and say so.
- Push to GitHub or upload to TestFlight only when asked, each time, and confirm the version and build number first. "Push" doesn't mean TestFlight.
- TestFlight "What to Test" notes must be plain ASCII in a code block: `-` bullets, no `•`, `★`, emoji, curly quotes or markdown, at most 4000 characters. Anything else gets a vague "Validation Error". Uploads also fail with "PLA Update available" until the new license agreement is accepted on developer.apple.com.
- Never commit `.DS_Store`. Never stash, reset or commit work you didn't make.
- Never print or commit secrets: the Jira token, the App Store Connect key, relay secrets. Credentials are set by the developer (for example `wrangler secret put`), never pasted into chat.
- Don't change macOS system or security settings; ask the developer to.
- Put the issue key in commit messages for fixes (`LYRE-12: …`).

## Jira and QA

- Bugs: Jira site `lyre-app.atlassian.net`, project **LYRE** (cloudId `0e15c93f-24fb-41a9-99bc-9cc27b5a944f`). Transitions: In Progress 21, Done 41. Titles read "[Area] What's wrong".
- Comments posted by Claude start with `🤖 Claude:` (they post as the developer's account).
- Ask before creating or changing issues outside `/jira-triage`. Triage runs only when the developer runs `/jira-triage` or asks; never schedule it (no cron, no `/loop`).
- Manual test cases: `QA/test-cases.json` is the source of truth, pushed to Qase project LYRE with `python3 Lyre/Scripts/qase_sync.py push-cases`. Results go up with `push-results`, and ids are kept in `QA/qase-map.json`. Edit the JSON and push; don't edit in Qase. Qase's `isManual` must be `0` or `1` (booleans get HTTP 422).

## Building and testing

- Simulator: "Lyre iPhone Duo", which models a closed iPhone Duo with its status bar and camera in an 84 pt column down the right edge.
- Test plans are in `Lyre/TestPlans/`. `Unit` is the scheme's default; UI tests need `-testPlan Regression`, which also rebuilds the UI test bundle:
  ```sh
  cd Lyre
  xcodebuild build-for-testing -scheme Lyre -testPlan Regression -destination id=<sim>
  xcodebuild test-without-building -scheme Lyre -testPlan Regression -destination id=<sim> \
    -parallel-testing-enabled NO -only-testing:LyreUITests/<Suite>/<test>
  xcodebuild test-without-building -scheme Lyre -testPlan Unit -destination id=<sim>
  ```
- Check that a new test appears in the results (if not, the bundle is stale). For anything visual, export the screenshots (`xcrun xcresulttool export attachments`) and look at them before reporting.
- UI tests reset state with `--uitest-complete-onboarding` (it forgets the player and Liquid's open-Duo section). Values written with `simctl spawn … defaults write` land in the simulator's device-wide preferences, which the app reads as a fallback; remove them the same way when done.
- Known failures that aren't regressions (they fail on `main` too): Disc `testChoosingASongFromACasePutsTheDiscOnAndShutsTheLid` (taps on an opened case don't land in the simulator); Gramophone `testTheUpNextBinFlipsRemovesReordersAndPlays`; `testSettingsOpenAndOfferTheOtherPlayers`, `testTurningThePhoneOpensTheArtworkCarousel…`; Spool `testSwipingATapeRightQueuesIt`, `testSwipingInFromTheRightEdgeOpensTheCarousel`, `testTappingTheGripBringsUpUpNextAndASwipeRemovesASong`, `testWithAnEpisodeInTheKeysJumpTheSpeedKnob…`, `testOnAnOpenDuoACaseOpensOverTheRack…` (flaky); unit LYRE-4 `SpoolSoundTests/theGramophonesSoundsAreShortEnoughToKeepUp`; also Liquid `testDiscoverOpensItsCoversAndGenres`, PlayerSwitch `testDiscChangePlayerButtonSwitchesToSpool`, Search `testClassicSearchLowersTheWheelWhileTypingAndBringsItBack` (failing on main as of 2026-11-12). Report these as known.

## Test phones

- **EDITH**: the developer's iPhone Duo (iPhone19,4), for checking Duo layouts by hand.
- **DUM-E**: the old iPhone Air (iPhone18,4). All hitch baselines up to 2026-11-09 were measured on it; numbers from EDITH aren't comparable.
- Find UDIDs with `xcrun devicectl list devices`. To install a debug build: `xcodebuild build -scheme Lyre -configuration Debug -destination id=<UDID> -allowProvisioningUpdates`, then `xcrun devicectl device install app --device <UDID> <…>/Debug-iphoneos/Lyre.app`.
- Profiling, with either phone connected and unlocked (real library of about 6,400 songs):
  1. Build optimized but testable: `build-for-testing … SWIFT_OPTIMIZATION_LEVEL=-O`. The Release configuration fails because tests use DEBUG-only helpers.
  2. Run the workload `LyreUITests/StreamingDeviceUITests/testATypicalLiquidSession`.
  3. Attach by name: `xcrun xctrace record --template 'Time Profiler' --device EDITH --attach Lyre --time-limit 75s`.
  4. For logs, use `devicectl device process launch --console` plus `print()`.

## Performance first

No change may add lag or unresponsiveness. Don't trade features or looks for speed without asking.

- The target is MainActor by default, so anything O(library) runs on the main thread unless made `nonisolated`/`@concurrent`. Keep scans, sorts, normalising, JSON and file work off it.
- Never do library- or queue-sized work in `body` or in computed properties `body` reads. Compute once when the data changes (didSet, memos keyed on the input, index dictionaries).
- Nothing per frame (TimelineView, Canvas, display links, drags) that allocates, scans, or reads regex or MPMediaItem properties. Wrap expensive static drawing in an Equatable view under the animated transform.
- Publish only on change (`MusicService.setIfChanged`). Pause animations, 3D and timers when hidden or idle. Debounce typing-driven work.
- Measure significant changes on a phone (see Test phones).

## Fluid interfaces (every new action or animation)

Every new action, gesture, transition or animation follows Apple's "Designing Fluid Interfaces" (WWDC18), using the shared vocabulary in `ViewModels/LyreMotion.swift`. Check each before merging:

- **Respond on touch-down.** Every Button gets a press style: `LyrePressStyle()` for icons, keys, chips and tiles; `LyrePressStyle(isRow: true)` for rows and tabs; `HotspotPressStyle` for invisible spots over drawn parts. Use `.buttonStyle(.plain)` only when the thing reacts itself, with a comment saying so.
- **Track the finger 1:1** while dragging. Past an end, rubber-band (`LyreMotion.rubberBand`) instead of stopping dead.
- **Decide at the lift with momentum:** `max(translation, translation + LyreMotion.project(velocity))`, never position alone.
- **Hand the finger's speed to the spring:** `LyreMotion.release(velocity:distance:)`.
- **Springs, not durations,** for anything the user moves: `LyreMotion.tap`, `.light`, `.heavy`. Fixed `easeInOut(duration:)` is for colour fades and scripted tours only.
- **Always interruptible and redirectable.** Never block input for an animation to finish. A touch mid-animation takes over or hurries it (see `PlayerSwitchStage.hurry`). Enable controls as soon as they're visibly reachable, not once settled.
- **Spatial consistency.** Things open from where they were touched and go back there: transitions anchored at the touch (`LiquidTouchTracker`), matched or zoom transitions. Back gestures follow the finger with the previous page showing (`InteractivePop` where the navigation bar is hidden).
- **Hint a hold as it builds** (`HoldHint`). Touch targets at least 44 pt.
- **Respect Reduce Motion:** a crossfade or an instant change with the same outcome.
- Add or extend a UI test for each new gesture, and check its screenshots. Reusable motion helpers belong in `LyreMotion.swift`.

## Dynamic Type (every piece of text)

Text people read grows with their text size (Settings > Display & Brightness > Text Size), as Apple's guidelines ask. Use `lyreFont(size:weight:design:maxScale:)` (`ViewModels/LyreType.swift`), not `.font(.system(size:))`:

- The size is the design's size at the standard text size; it scales along the curve of the nearest system text style.
- `maxScale: 2` for reading pages (settings, lists, cards, cases, sleeves, booklets, Liquid's pages); `maxScale: 1.5` for text inside a player or the Classic's screen, where room is tight.
- Leave as drawn only words that are part of an object's picture (a cassette's or record's label, the Discman's display, the click wheel, tape spines, index strips, the tutorials' animations). Fonts sized from the object (`size * 0.1`) count as these.
- Titles that mustn't break mid-word get `.lineLimit(1).minimumScaleFactor(0.5)`; rows and lists should grow, not clip (no fixed heights around text).
- Check new screens at a large size: `DynamicTypeUITests` launches each player at Accessibility Large (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL`); look at the screenshots.

## Contrast and transparency (every faded word, faint fill and frosted panel)

Follow Increase Contrast and Reduce Transparency (Settings > Accessibility > Display & Text Size) with the helpers in `ViewModels/LyreContrast.swift`:

- `lyreFaded(0.6)` for text faded back, and `lyreInk(.white, 0.6)` for faded text or symbols, instead of `.opacity` or `.foregroundStyle(color.opacity)`: at least 90% with Increase Contrast.
- `lyreFill(.white, 0.1, in: Circle())` for a faint fill behind a control: firmer and outlined with Increase Contrast, solid with Reduce Transparency.
- `lyreMaterial(.ultraThinMaterial, in:solid:)` for frosted glass, with a solid colour that suits where it is.
- Text laid over artwork needs a scrim that darkens further with Increase Contrast (see Liquid's Now Playing).
- Check with `ContrastUITests`, which turns both on (`--lyre-increase-contrast`, `--lyre-reduce-transparency`, debug builds), and look at its screenshots.

## Agency: anything taken away can be put back

Removing a song from Up Next, clearing Up Next, taking a song out of a playlist, unsubscribing and removing a download all offer Undo through `LyreUndo.shared.offer(message) { ... }` (`Services/LyreUndo.swift`). That shows the bottom banner (`lyre.undo.button`) for 6 seconds and registers shake-to-undo. For Up Next, use `removeFromQueueOfferingUndo(at:)` and `clearQueueOfferingUndo()`, not the bare calls. Don't show a separate "Removed" notice as well. A step that can't be taken back still asks first (Clear the Queue? asks and also offers Undo).

- Every gesture has a button, a menu item or a VoiceOver action as well. Holding a tape or case offers Play, Play Next and Add to Queue.
- An on-screen line saying how a gesture works fades once the person has done it 3 times. Use `GestureLessons.shared.learned(.x)` to hide it and `did(.x)` where the gesture lands. Settings' "Show Gesture Tips Again" (`GestureTipsButton`) brings the lines back. UI-test launches start fresh; `--lyre-gestures-learned` starts with everything learned. A one-time hint motion, like the tape leaning toward the deck, shows once per launch until learned, never with Reduce Motion, and in UI tests only with `--lyre-nudge`.

## Touches: read for what they mean

Where something can be tapped, held or carried among things that scroll, don't decide from the first few points of a touch. Use `GestureIntent` (`Services/GestureIntent.swift`, a pure classifier with named rules) through `GestureIntentTouch` (`ViewModels/GestureIntentTouch.swift`):

- Moving off at once scrolls.
- Resting about 0.16s lifts the thing: it rises in place, with a light tap. Moved after that, it's carried in any direction.
- Resting on to 0.5s holds it (Liquid's song spread).
- A quick, still release is a tap, even just after the lift.
- A flick toward the drop target carries at once, but only where that direction isn't the scroll's (left in Liquid's book layout, none when turned).

Thresholds live in `GestureIntent.Thresholds`. Tune them on a device with `-LyreGestureHUD YES`, which shows speed, distance and the rule live. `GestureIntentTests` replays traces. Liquid's bubble field and song lists (Songs, the recent lists, an album's page; `LiquidSongLift` / `LiquidSongCarry`) use it. In the lists, a lifted song goes across the fold to play, or onto Up Next; the row's own tap, swipes and hold menu stay. A single's bubble held opens nothing; it stays lifted. Up Next's drop bubble reaches its edge toward what's carried and warps as it takes it in (`UpNextReachShape`). The Spool, Disc and Gramophone racks are next.

## iPhone Duo

- Closed, the status bar sits in a column down the right edge. `SideRail` (`ViewModels/SideRail.swift`) puts each player's header buttons in that column, with a "…" menu past its capacity. Keep new header buttons working with it.
- Liquid open: held as a book (Now Playing left, section right) or turned (Now Playing above the fold, section below). Both layouts navigate by the side bar: Albums, Songs, Artists and Search fixed, a fifth button for the section last used from Playlists, Podcasts, Discover, Recently Played and Recently Added, and the rest in "…".
- Liquid open, a bubble held: its songs spread out (`TrackSpread`). A song carried across the fold plays. While a song is carried, a big, lit Up Next bubble (`UpNextDropBubble`, 96pt, smaller only where room is short) comes up in the open place nearest the held bubble (`TrackSpreadLayout.openSpot`). It also comes up at the foot of the page while any bubble itself is carried; dropped there, the whole bubble is queued the same way. Dropped on it, or on Now Playing's Up Next bulge, the song joins Up Next after any songs queued by hand, or next if there are none (`MusicService.quickQueue`, `LiquidUpNextWell`). Both targets swell and lean toward the song, then gulp it, as the fold's water does.

## Privacy and data collection

- Any change that adds, removes or alters what Lyre collects or sends (usage statistics, problem reports, third-party calls, anything leaving the device) updates `PRIVACY.md` (list it, bump "Last updated") and `Lyre/Lyre/PrivacyInfo.xcprivacy` in the same branch, before it ships. Also tell the developer what to change in App Store Connect's privacy section.
- New usage counts stay opt-in, nameless, unlinked and untracked. Never collect song, album, artist or playlist names, search text, screenshots or session replay.
- No third-party analytics SDKs: Lyre's own Cloudflare relay (`relay/`) handles it.

## Agreed plans

- **Problem reports to Jira** (agreed 2026-11-04):
  - A Cloudflare Worker holds the Jira token; the app never does. It checks App Attest, rate-limits, dedupes by fingerprint, stores diagnostics in R2, and creates Bugs labelled `auto-report` and `needs-triage`.
  - It never adds `claude`. The developer adds that after review, so `/jira-triage` picks it up.
  - Key evidence goes inline in the issue text, because Jira attachments can't be downloaded.
  - "Send Diagnostics Automatically" is opt-in; "Report a Problem" is always available.
  - TestFlight feedback and crashes are bridged in from the App Store Connect API.
- **Usage statistics** (agreed 2026-11-05):
  - Stored on the relay (Analytics Engine, dataset `lyre_usage`). "Share Usage Statistics" is off by default.
  - Focus areas: player adoption and switching, time to music, dead ends and friction, feature discovery.
  - Deploying the relay (`wrangler deploy`) is the developer's step.
