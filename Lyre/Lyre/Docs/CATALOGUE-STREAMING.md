# Streaming from Apple Music

Lyre plays through `MPMusicPlayerController.applicationQueuePlayer`. Songs from the
library go into its queue as `MPMediaItem`s; songs from Apple Music's catalogue that
aren't in the library go in by store ID (`MPMusicPlayerStoreQueueDescriptor`), with a
subscription. Both sit in one queue (`PlaybackEntry`, `MusicService.setPlayerQueue(_:startingAt:)`).

## What the player does (measured on an iPhone Air, iOS 27, 2026-10-25)

This replaced the catalogue queue spike, which asked these questions:

| Question | Answer |
|---|---|
| A store-ID entry inserted into a queue set from library items plays? | Yes. Skipping onto it streamed it. |
| What `queue.items` reports for it | An `MPMediaItem` with `persistentID == 0`, `playbackStoreID` set, title filled in. |
| What `nowPlayingItem` reports while it plays | The same: `persistentID == 0`, its store ID, its real length. `indexOfNowPlayingItem` is right. |
| A queue set entirely from store IDs, then library items added? | Works. |
| Removing a store entry, inserting after one, `nowPlayingItem =` a queue entry | All work. |

So a queue entry is known by `MPMediaItem.queueKey`: its persistent ID, or when that's 0,
its store ID. `AppTrack.queueKey` gives the same for a track, and `PlaybackQueue`,
`syncQueueModel` and every queue edit match on it.

## Rules

- A song the library has is always played from its library item (offline, no
  subscription needed). Only `AppTrack.isStreamOnly` tracks stream.
- Streaming needs a subscription (`MusicService.canStream`); without one, stream-only
  tracks are dropped like any unplayable track.
- One descriptor holds one kind, so a mixed list goes in as runs (`MusicService.runs(of:)`).
- Catalogue requests need MusicKit enabled for the App ID
  (developer.apple.com → Identifiers → com.pinkhatcreations.lyreapp → App Services).
  Without it every request fails with `developerTokenRequestFailed`.
