# Privacy Policy

**Last updated: November 6, 2026**

Lyre ("the app") is developed by Daniel Buzlea / Pink Hat Creations. This policy explains what data the app does and does not handle.

## Summary

Lyre does not collect or sell personal data, and has no advertising or tracking. Three things can leave your device:

- **Problem reports, only if you send them or allow them.** If you use Report a Problem, or turn on Send Diagnostics Automatically (off unless you turn it on), Lyre sends a report about the problem to its developer so it can be fixed. Reports contain technical information about Lyre and your device and never your music library's contents; see Problem Reports and Diagnostics.
- **Usage statistics, only if you allow them.** If you turn on Share Usage Statistics (off unless you turn it on), Lyre sends counts of how the app is used, such as which players and features are used and how long it takes to start music, so it can be made easier to use. They never name your music or anything you search for, and aren't linked to you; see Usage Statistics.
- **Song identifiers, for tempos.** To find songs' tempos, the Liquid player sends song identifiers (never anything about you) to Deezer's public API, which you can turn off; see Third-Party Services.

## What Lyre Accesses

**Your Apple Music library.** Lyre uses Apple's own MusicKit and MediaPlayer frameworks to read and play songs, albums, artists, playlists, and podcasts from your Apple Music library, with your permission. This data is read directly from Apple's services onto your device to power playback — it is never sent to us, stored on our servers, or shared with any third party. Lyre's only server is the report service described below, which receives only the problem reports and usage statistics you send or allow, never your library.

## What Stays on Your Device

Your app preferences — theme, screen size, highlight color, scroll sensitivity, backlight duration, and whether you've completed onboarding — are stored locally on your device using Apple's standard `UserDefaults` storage. This information never leaves your device.

Lyre also keeps a diagnostics log on your device: a record of what the app did (for example, that it launched, which player and screen were open, how long loading your library took, and whether anything froze or failed), plus the crash and performance reports iOS gives it. The log never contains the names of your songs, albums, artists, or playlists. It stays on your device, keeping roughly the last few days, unless you choose to share it (Share Diagnostics, in settings) or send it with a problem report.

If Share Usage Statistics is on, the counts described in Usage Statistics wait on your device until they're sent, about once a day. The short note about setting up Lyre, described there too, is kept on your device until it's sent or deleted.

## Problem Reports and Diagnostics

Lyre uses Apple's MetricKit framework, through which iOS gives the app reports of crashes, freezes, and heavy CPU or storage use. These, and the diagnostics log above, are sent to Lyre's developer only in these cases:

- **Report a Problem** (in settings): when you send a report, it includes what you write, a screenshot of the screen you were on if you leave that option on, and the technical details below. A screenshot shows whatever was on screen, which may include song or album names; you can see it before sending and switch it off.
- **Send Diagnostics Automatically** (in settings): off unless you turn it on. Lyre asks you once whether to turn it on. When it's on, a report is sent automatically when iOS reports a crash, freeze, or excessive CPU or storage use. Turning it off stops this.
- **Share Diagnostics** (in settings): opens the share sheet with the diagnostics log and reports, for you to send wherever you choose. Nothing is sent unless you share it.

**What a report contains:** Lyre's version and build, an identifier for the exact app binary, your iPhone model, the iOS version, which of Lyre's players you were using, the last lines of the diagnostics log, the crash or freeze details (including the program's call stack) if it's an automatic report, and, for reports you send yourself, your words and optional screenshot. It never contains your name, email address, Apple Account, location, contacts, or the contents of your music library. Each report also carries a random identifier Lyre creates for itself on your device, used only to limit how many reports one device can send; it isn't linked to you. Reports are signed using Apple's App Attest, which lets the report service check that a report came from a genuine copy of Lyre; App Attest doesn't identify you.

**Where reports go:** reports are sent to Lyre's report service, which runs on Cloudflare, and are filed in Jira, an issue tracker run by Atlassian, where only Lyre's developer reviews them. Screenshots and attached files are stored with Cloudflare. The report service doesn't record your IP address; Cloudflare handles network traffic under [its own privacy policy](https://www.cloudflare.com/privacypolicy/), and Atlassian holds the filed reports under [its privacy policy](https://www.atlassian.com/legal/privacy-policy). Reports are kept only as long as needed to investigate and fix problems. To have a report you sent deleted, contact us (see Contact) with roughly when you sent it and what it was about.

Separately, iOS may also send crash and performance information to Apple if you've allowed it in your device's settings; that's handled by Apple, under [Apple's privacy policy](https://www.apple.com/legal/privacy/).

**TestFlight testers:** feedback, screenshots, and crash reports you send through TestFlight go to Apple, who makes them available to Lyre's developer, as described in Apple's TestFlight terms. Lyre's report service copies them, with the email address shown to the developer, into the same Jira tracker so they can be reviewed with other reports.

## Usage Statistics

**Share Usage Statistics** (in settings) is off unless you turn it on. Lyre asks you once, alongside Send Diagnostics Automatically, and you can change it in any player's settings at any time.

When it's on, Lyre counts how it's used, so its developer can see where it's easy or hard to get around and improve it:

- which of Lyre's players you use, and when you switch between them;
- how long it takes from opening Lyre to starting music, and from which kind of screen (for example a shelf, a card, a search, or the queue);
- which kinds of screens are opened, and which are left again within a couple of seconds;
- whether a search found anything in your library (never the words you searched for);
- moments the app froze, and on which kind of screen, and errors shown;
- the first time, and how often, features such as Shuffle, the Songs shelf, card decks, swiping to queue, or Add to Playlist are used;
- whether each song was skipped in its first 30 seconds, heard in part, or heard to the end, and from which kind of screen the music was started; and how long music played without stopping, and whether it carried on with Lyre in the background;
- how many screens were opened before the first song, and screens opened and quickly backed out of;
- whether a search led to music, how quickly, how long the search was in letters (never the words), and, in the classic player, the place in the list of the result chosen;
- in the classic player, how far the click wheel was turned for each choice and how often it was turned back;
- four or more quick taps in one spot, and on which kind of screen;
- iOS's daily performance figures for Lyre (average launch and resume times, freezes, scrolling smoothness, peak memory, and unexpected exits);
- once a day: your library's size in broad bands (for example "500 to 2,000 songs"), whether you have an Apple Music subscription, the width of the screen in points, which of Lyre's settings you've changed from their defaults and to what, and whether VoiceOver, Reduce Motion, Bold Text or a larger text size is on.

**Setting up Lyre.** Lyre's setup happens before it can ask about usage statistics, so it keeps a short note on your device of the setup steps you went through, how long each took, whether you allowed music access, and the player you chose. That note is sent only if you later turn on Share Usage Statistics, and is deleted after 30 days if you don't. A week after setup, Lyre also counts whether the player you chose is still the one you use.

Each count carries Lyre's version and build, whether the device is an iPhone or iPad (not the model), the major iOS version, the player in use, the date, which week Lyre was installed and how many days ago. It never contains the names of songs, albums, artists, playlists, podcasts or anything else in your library, anything you type or search for, where you tap, screenshots, your name, email address, Apple Account, location, or contacts, and it carries no identifier for you or your device, so counts from one device can't be linked together or to you.

Most of the working-out happens on your device (for example, Lyre sends "the first song started 6 seconds after opening, from a card", not each tap). Counts wait on your device and are sent about once a day, signed using Apple's App Attest like problem reports. They go to Lyre's report service on Cloudflare and are kept in Cloudflare's Workers Analytics Engine, where only Lyre's developer can see them, as totals, for up to three months. To limit how often a device can send, the service briefly keeps a one-way scrambled form of the sending key or network address, deleted within two days and never stored with the counts. Turning Share Usage Statistics off stops it and deletes any counts still waiting on your device.

**As Lyre changes.** Lyre's developer may add new counts over time to keep improving it. Any new count will follow the same rules: it's sent only with Share Usage Statistics on, it's a count or a kind of thing rather than anything you've written or anything in your library, it carries no identifier and isn't linked to you, and it isn't used for tracking or advertising or shared with anyone else. Each new kind of count is added to the list above, with this policy's date updated, before the version of Lyre that collects it is released. Anything that would break those rules would only happen if Lyre asks you again first.

## Third-Party Services

Lyre does not integrate any third-party analytics, advertising, or data-collection SDKs. Problem reports go through Cloudflare and Atlassian, as described in Problem Reports and Diagnostics; usage statistics, if you allow them, go only to Cloudflare, as described in Usage Statistics. Both are signed using Apple's App Attest.

**Deezer (song tempos).** So that the Liquid player can move to the beat, Lyre asks Deezer's public API (api.deezer.com) for the tempo of the songs in your library. Each request carries only the song's ISRC (the code that identifies a recording) or, where a song has none, its title and artist. No account, device identifier, location, or anything else about you is sent, and Lyre's developer receives nothing. The tempos found are kept on your device. This is on by default and can be turned off in Liquid's settings ("Look Up Tempos"); turned off, nothing is sent. Deezer's handling of these requests is covered by [Deezer's privacy policy](https://www.deezer.com/legal/personal-datas).

**Apple (podcast search).** Searching for podcasts sends the words you search for to Apple's iTunes Search API, and podcast feeds are fetched from their publishers.

## Children's Privacy

Lyre does not knowingly collect personal information from anyone, including children. Problem reports contain only the technical information described above, and anything a person chooses to write or include in a report they send themselves.

## Changes to This Policy

If this policy changes, the updated version will be posted at this same URL with a revised "Last updated" date, before the version of Lyre the change applies to is released. Lyre never starts collecting a new kind of data without it being described here first, and never collects anything beyond what this policy describes without asking you first.

## Contact

Questions about this policy or the app can be filed at [github.com/dbuzlea/Lyre/issues](https://github.com/dbuzlea/Lyre/issues).
