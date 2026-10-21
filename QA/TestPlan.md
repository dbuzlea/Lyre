# Lyre Test Plan

The master test plan for Lyre: what is tested, how, where, and when a build is good
enough to ship. It follows the outline of IEEE 829 / ISO/IEC/IEEE 29119-3, trimmed to
what a one-person project needs.

| | |
|---|---|
| Product | Lyre for iPhone (and iPhone Duo), version 2.5.x |
| Owner | Daniel Buzlea |
| Test management | Qase, project `LYRE` |
| Automated tests | Xcode: `LyreTests` (Swift Testing), `LyreUITests` (XCTest UI) |
| Cases | [`QA/test-cases.json`](test-cases.json) (source of truth, synced to Qase) |

---

## 1. Scope

**In scope.** Everything a user can reach:

| Area | Qase suite | Risk |
|---|---|---|
| First launch and onboarding | Onboarding | High: a broken first run loses the user |
| Music access, loading, caching | Music Access & Library | High |
| Playback and the queue, shared by every player | Playback & Queue | High |
| The five players: Classic, Spool, Gramophone, Disc, Liquid | one suite each | Medium–High |
| Podcasts: search, subscribe, stream, download, OPML | Podcasts | High |
| Network states | Connectivity | High |
| Lock screen, AirPlay, interruptions, life cycle | System Integration | High |
| iPhone Duo postures | Foldable (iPhone Duo) | Medium |
| VoiceOver, Dynamic Type, RTL, motion, contrast | Accessibility & Localization | Medium |
| Settings, upgrades, damaged data | Settings & Persistence | Medium |

**Out of scope.** Apple's own frameworks (MusicKit, MediaPlayer, AVFoundation) beyond
how Lyre uses them; the iTunes Search API's own correctness; App Store Connect.

## 2. Approach

Lyre is tested at four levels, cheapest first:

1. **Unit tests** (`LyreTests`, ~300 tests, under a minute). Models, queue rules, parsing,
   persistence, error classification. Network behavior is tested against a stub
   (`StubNetwork` in `ConnectivityTests.swift`), so every connection state (offline,
   timeout, cellular off, roaming off, server down, captive portal, a feed cut off
   mid-download) runs on every build without touching the real network.
2. **UI tests** (`LyreUITests`, ~150 tests, ~60 minutes). Real flows on the simulator.
   Launch arguments put the app in a known state (see §6). `EnvironmentUITests` covers
   the "every user, every environment" matrix: offline and server-down podcasts, the
   largest text size, right-to-left, landscape, background/return, revoked access,
   and accessibility audits.
3. **Manual test cases** (Qase). What automation can't reach: real Apple Music
   accounts, AirPlay hardware, phone calls, headphones, low storage, Low Power Mode,
   the feel of the players. 15 of the 75 cases are manual only; the rest are partly
   automated and list their tests under `automated_by`.
4. **Exploratory sessions.** Time-boxed (45–60 min), unscripted, with a charter.
   Record each in Qase as a test run named "Exploratory: <charter>". Charters to start with:
   - Break the Up Next queue: queue, reorder, remove and switch players while playing.
   - Fold and unfold the Duo in every player while sheets and cases are open.
   - Use Lyre on a train: go in and out of signal while streaming and downloading.
   - Use Lyre with VoiceOver only, eyes closed, for one album and one podcast episode.

**Risk-based priority.** Each case carries a priority (High/Medium/Low: how much
testing it deserves) and a severity (Blocker…Trivial: how bad it is if it fails).
When time is short, run High-priority cases first.

## 3. Test plans (what runs when)

| When | Xcode test plan | Qase test plan | Time | Pass bar |
|---|---|---|---|---|
| Every change (⌘U) | **Unit** (default) | — | < 1 min | All pass |
| Before a TestFlight build | **Smoke** | **Smoke** | ~15 min + 20 min manual | All pass |
| Before an App Store release | **Regression** | **Release Regression** | ~60 min + ~3 h manual | See §5 |
| When the network code changes | Regression (EnvironmentUITests) | **Connectivity** | ~30 min | All pass |
| Before a release that touches UI | Regression | **Accessibility** | ~45 min | No High open |
| Duo or posture work | Regression (Duo simulator) | **Foldable (iPhone Duo)** | ~30 min | All pass |
| App Store screenshots | **Screenshots** | — | ~10 min | — |
| Launch-time checks, on a device | **Performance** | — | ~5 min | Cold launch < 1.5 s |

The Xcode test plans live in `Lyre/TestPlans/` and are chosen from the scheme (Product >
Test Plan, or `xcodebuild -testPlan <name>`). The **Unit** plan also has a *Thread
Sanitizer* configuration that reruns the unit tests looking for data races. **Regression**
retries a failing UI test once, but a test that only passes on retry still counts as
flaky: mark it `is_flaky` in Qase and fix it.

## 4. Environments

| Dimension | Covered by |
|---|---|
| Devices | iPhone Duo simulator (primary, folds), an iPhone 16-class simulator, the smallest supported iPhone (SE), one physical iPhone for manual and performance runs |
| iOS | The minimum supported and the latest release |
| Network | Wi‑Fi, cellular, cellular-off-for-Lyre, airplane mode, Network Link Conditioner "Very Bad Network" / "100% Loss", a captive portal |
| Account | No Apple ID music; Apple Music subscriber; music synced from a Mac only |
| Library | Empty; ~50 songs; 5,000+ songs; podcasts only; mixed scripts (accents, CJK, Arabic, emoji) |
| Access | Never asked; allowed; denied; revoked after onboarding |
| Accessibility | VoiceOver, largest Dynamic Type, Bold Text, Increase Contrast, Reduce Motion |
| Locale | English, a right-to-left language, a 24-hour region |
| Power | Normal, Low Power Mode, under 20% battery |

## 5. Entry and exit criteria

**Entry (start testing a build):** it builds; the Unit plan passes.

**Exit (ship it):**
- Unit and Smoke plans: 100% pass.
- Regression: no failures in High-priority cases; any other failure has a Qase defect
  with a decision recorded (fix now, or ship with a known issue).
- No open Blocker or Critical defects.
- Every manual High-priority case run on a physical device for this release.

## 6. Test hooks (debug builds only)

| Launch argument | Effect |
|---|---|
| `--uitest` | Stands down never-ending animations so XCUITest can settle |
| `--uitest-complete-onboarding` / `--uitest-reset-onboarding` | Start past onboarding, or at its first step |
| `-UITestNetwork offline` · `serverError` · `stub` | Podcast search and feeds fail offline, get HTTP 503, or answer with a canned show |
| `--uitest-open-podcast-search` | Classic player opens with the podcast search sheet up |
| `--uitest-reset-subscriptions` | Forget podcast subscriptions from earlier runs |
| `--uitest-hide-library-errors` | Keep the simulator's "no library" alert out of tests about something else (it no longer closes sheets: LYRE-2) |
| `-SpoolSampleTapes YES`, `--spool-sample-queue` | Sample albums and a queue in an empty library |
| `-LyrePlayerStyle <style>` | Start on a player |

## 7. Defects

Log defects in Jira, project **LYRE** on [lyre-app.atlassian.net](https://lyre-app.atlassian.net) (from a failed Qase case, use **Create defect** once Qase's Jira app is connected), with: steps to reproduce,
expected vs actual, build number, device and iOS, a screenshot or recording, and the
failing case. Severity follows the case's severity unless the failure is worse.

**Known at the time of writing (October 2026):**

| Jira | Defect | Severity | Found by |
|---|---|---|---|
| [LYRE-2](https://lyre-app.atlassian.net/browse/LYRE-2) | The library error alert ("Something Went Wrong"), shown when the library can't load, closes any open sheet (podcast search, settings). On a device with no library it can appear more than once after launch. | Major | EnvironmentUITests, while writing the podcast tests |
| [LYRE-3](https://lyre-app.atlassian.net/browse/LYRE-3) | 7 Liquid UI tests fail on the current working tree (Settings sheet doesn't open, swipe actions, carousel on rotation, player hand-over). They fail the same way with this session's changes reverted, so they predate it. | Major | Regression run |
| [LYRE-4](https://lyre-app.atlassian.net/browse/LYRE-4) | `SpoolSoundTests/theGramophonesSoundsAreShortEnoughToKeepUp()` fails: a Gramophone sound is outside 0.03–0.8 s. | Minor | Unit plan |
| [LYRE-5](https://lyre-app.atlassian.net/browse/LYRE-5) | After access is restored on a device whose library can't load, "Access Restored — Reloading…" stays up through every retry (well over 25 s on the simulator). | Minor | testARevokedLibraryAccessIsExplainedAndCanBeRestored |

Fixed during the same work: cellular-data-off and roaming-off read as "Service
Unavailable" instead of "No Internet Connection"; a red low-battery warning on devices
whose battery can't be read (Macs, the simulator); a 4-point VoiceOver target on
onboarding's progress bar; the Liquid A–Z index out of order and splitting accented
letters; the Gramophone preview overlapping Choose Your Player's subtitle.

## 8. Working with Qase

See [QA/README.md](README.md).
