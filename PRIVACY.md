# Privacy Policy

**Last updated: October 25, 2026**

Lyre ("the app") is developed by Daniel Buzlea / Pink Hat Creations. This policy explains what data the app does and does not handle.

## Summary

Lyre does not collect, store, transmit, or sell any personal data. There are no analytics, advertising, or tracking services built into the app. To find songs' tempos, the Liquid player sends song identifiers (never anything about you) to Deezer's public API, which you can turn off; see Third-Party Services.

## What Lyre Accesses

**Your Apple Music library.** Lyre uses Apple's own MusicKit and MediaPlayer frameworks to read and play songs, albums, artists, playlists, and podcasts from your Apple Music library, with your permission. This data is read directly from Apple's services onto your device to power playback — it is never sent to us, stored on our servers, or shared with any third party. We do not have our own servers; Lyre has no backend at all.

## What Stays on Your Device

Your app preferences — theme, screen size, highlight color, scroll sensitivity, backlight duration, and whether you've completed onboarding — are stored locally on your device using Apple's standard `UserDefaults` storage. This information never leaves your device.

## Crash and Performance Diagnostics

Lyre uses Apple's MetricKit framework, which may collect on-device crash and performance diagnostics and send them directly to Apple as part of the standard iOS diagnostics system. This is handled entirely by Apple's operating system — Lyre's developer does not receive, store, or have access to this data. See [Apple's own privacy policy](https://www.apple.com/legal/privacy/) for how Apple handles this information.

## Third-Party Services

Lyre does not integrate any third-party analytics, advertising, or data-collection SDKs.

**Deezer (song tempos).** So that the Liquid player can move to the beat, Lyre asks Deezer's public API (api.deezer.com) for the tempo of the songs in your library. Each request carries only the song's ISRC (the code that identifies a recording) or, where a song has none, its title and artist. No account, device identifier, location, or anything else about you is sent, and Lyre's developer receives nothing. The tempos found are kept on your device. This is on by default and can be turned off in Liquid's settings ("Look Up Tempos"); turned off, nothing is sent. Deezer's handling of these requests is covered by [Deezer's privacy policy](https://www.deezer.com/legal/personal-datas).

**Apple (podcast search).** Searching for podcasts sends the words you search for to Apple's iTunes Search API, and podcast feeds are fetched from their publishers.

## Children's Privacy

Lyre does not knowingly collect any information from anyone, including children, because it does not collect information from anyone.

## Changes to This Policy

If this policy changes, the updated version will be posted at this same URL with a revised "Last updated" date.

## Contact

Questions about this policy or the app can be filed at [github.com/dbuzlea/Lyre/issues](https://github.com/dbuzlea/Lyre/issues).
