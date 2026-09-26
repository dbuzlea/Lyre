# Info.plist Configuration Guide

How Lyre's bundle metadata is actually configured. There are **two** sources, and
knowing which is which matters — editing the wrong one silently does nothing.

## Source 1 — `INFOPLIST_KEY_*` build settings

`GENERATE_INFOPLIST_FILE = YES`, so Xcode synthesises most keys from build
settings at build time. These are set on the **Lyre** target, not in any file:

| Build setting | Value |
|---|---|
| `INFOPLIST_KEY_CFBundleDisplayName` | `Lyre` |
| `INFOPLIST_KEY_NSAppleMusicUsageDescription` | Lyre plays music from your Apple Music library to give you a classic scroll-wheel listening experience. |
| `INFOPLIST_KEY_NSHumanReadableCopyright` | Copyright © 2026 Daniel Buzlea. All rights reserved. |
| `INFOPLIST_KEY_LSApplicationCategoryType` | `public.app-category.music` |
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` | `NO` |
| `INFOPLIST_KEY_UISupportedInterfaceOrientations` | Portrait, Landscape Left, Landscape Right |
| `INFOPLIST_KEY_UILaunchScreen_Generation` | `YES` |

To change any of these, edit the **build setting** — do not add the key to
`Info.plist`, or you will end up with two competing definitions.

### Deliberately unset

- `INFOPLIST_KEY_UIRequiredDeviceCapabilities` — must stay empty. It previously
  contained `armv7`, which App Store validation rejects for an arm64-only binary.
- No microphone, camera, location, or contacts usage descriptions — the app
  requests none of those permissions.

## Source 2 — `Lyre/Info.plist`

Only the keys that cannot be expressed as build settings live in the file:

```xml
<key>CFBundleGetInfoString</key>
<string>Lyre — a scroll-wheel music player for iPhone</string>

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Why the `audio` background mode is required

Playback goes through `MPMusicPlayerController.applicationQueuePlayer` — an
*application* player, whose queue belongs to this app. It replaced
`systemMusicPlayer`, which drives the Music app on our behalf: with that player the
Music app's queue could supersede ours and its autoplay would take over at the end,
so a song the user added to the queue would never play. The application queue player
is also the only player whose queue can be edited in place
(`perform(queueTransaction:)`), which is what makes queueing seamless.

An application player stops at the app's suspension unless the app declares
`UIBackgroundModes: [audio]`, so the mode is now load-bearing rather than an
unjustified capability — Guideline 2.5.4 is satisfied because the app genuinely is
the thing playing audio. (Before this change the guide correctly said the opposite;
it changed with the player.)

## Privacy manifest

`PrivacyInfo.xcprivacy` declares no tracking, no collected data types, and one
accessed API category:

- `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1` — persisting the
  chosen finish, screen size, and settings.

Keep this in sync with the App Store Connect privacy questionnaire, which should
answer "No, we do not collect data".

## MusicKit

MusicKit needs no entitlements file. It requires the App ID
`com.pinkhatcreations.lyreapp` to have the **MusicKit** service enabled in the Apple
Developer portal, plus the MusicKit capability on the target in
**Signing & Capabilities**. Without the portal-side service, `MusicLibraryRequest`
calls fail at runtime even though the app builds and signs cleanly.

## Verifying the result

Build settings and files both feed the final bundle, so check the built product
rather than the inputs:

```sh
plutil -p "$(ls -d ~/Library/Developer/Xcode/DerivedData/Lyre-*/Build/Products/Debug-iphoneos/Lyre.app)/Info.plist"
```
