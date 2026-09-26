# App Store Review Response — Guideline 2.1 (Information Needed)

Draft reply for the "Information Needed" request on Lyre's initial submission. Paste this into
the App Store Connect reviewer reply, and also into **App Review Information → Notes** for
reference on future submissions, as Apple's message requests.

---

**1. Screen recording**

Must be captured on a physical device by the developer — cannot be generated in advance.
Since Lyre has no account/login, no user-generated content, and no paid features, the
recording only needs to show the core flow:

- Launch the app → onboarding screen → grant Apple Music permission when prompted
- Main menu navigation via the scroll wheel (circular drag + tap zones)
- Browsing Songs / Albums / Artists / Playlists / Podcasts
- Playing a track, using Now Playing (scrub, repeat, shuffle)
- A couple of Settings screens (theme, backlight, etc.)
- Landscape artwork carousel and shake-to-shuffle if possible

**2. App's purpose and target audience**

Lyre is a nostalgic, scroll-wheel-driven music player for iPhone. It reimagines the tactile,
click-wheel browsing experience of classic dedicated music players as a native SwiftUI app
built on Apple's MusicKit, giving users a deliberate, physical way to browse their own Apple
Music library instead of flat, list-based UI. The target audience is iPhone users with an
Apple Music subscription (or local library) who want a more focused, retro-styled way to
browse and play the music they already have — particularly listeners who miss the feel of
classic click-wheel devices.

**3. Setup / accessing main features**

Lyre requires no account, login, or credentials of any kind. On first launch the user
completes a brief onboarding flow and grants the standard Apple Music permission prompt
(`NSAppleMusicUsageDescription`). Once granted, the app reads the user's own Apple Music
library (or local library) via MusicKit/MediaPlayer — there's nothing to configure and no
sample files or demo credentials are needed, since all content comes from the reviewer's own
Apple Music account/library on the test device. Navigation is entirely via the on-screen
scroll wheel (documented in the app's Main Menu → Settings → About, and in the public
README).

**4. External services/tools used**

Lyre uses only Apple's own first-party frameworks — no third-party services of any kind:

- **MusicKit** and **MediaPlayer** — to read and play the user's Apple Music
  library/subscription content
- **MetricKit** — standard on-device crash/hang diagnostics sent directly to Apple's OS-level
  diagnostics (the developer never receives this data)
- **CoreMotion** — for the shake-to-shuffle gesture

There is no backend server, no analytics/advertising SDK, no authentication service, and no
payment processor. (See the app's privacy policy for full detail.)

**5. Regional differences**

Lyre functions identically in every region and App Store storefront — there is no
region-based logic in the app. The only variability is Apple Music's own catalog/subscription
availability by region, which is entirely outside the app's control.

**6. Regulated industry / protected third-party material**

Not applicable. Lyre doesn't operate in a regulated industry. It only plays back content from
the end user's own Apple Music subscription/library through Apple's licensed MusicKit
framework — it doesn't host, provide, or redistribute any third-party protected material
itself. Apple Music access is already authorized via this developer account's MusicKit
capability/entitlement in the Apple Developer portal.

---

## Re: "Prevent Common Issues" checklist

- No demo account needed — the app has no login of any kind.
- No In-App Purchase products — Lyre currently has no paid features.
- Screenshots already show the actual scroll-wheel UI in use, not a splash/login screen.

## Before submitting

- Confirm the submitted build was tested end-to-end on a physical device running the latest
  iOS.
- If any App Store screenshot shows only the onboarding/splash screen, swap at least one for
  the main menu or Now Playing screen per Guideline 2.3.3.
