# Catalogue Queue Spike

Throwaway diagnostic. Delete `Services/CatalogueQueueSpike.swift`, the `#if DEBUG`
hooks in `MusicService`, the left-swipe branch in `ScrollWheelView`, and this file once
the questions below are answered.

## Why

Apple Music catalogue tracks can't be queued today. `getMPMediaItem` returns nil for
them, so `resolveForPlayback` drops them from playback and `addToQueue` refuses them:

```
Cannot queue 'Devil’s Trill Sonata (Live)' — no media item backs it
Starting playback: 16 track(s) → Queued 2 of 16
```

`MPMusicPlayerPlayParameters` can represent catalogue *and* cloud-library items, and
`applicationQueuePlayer` accepts a play-parameters descriptor. What the documentation
does not say is how such an entry behaves once it is in a queue — and the app's queue
model depends entirely on that.

`PlaybackQueue` identifies tracks by `MPMediaItem.persistentID`, and
`syncQueueModel(with:)` rebuilds the model from `queue.items` after every transaction.
If catalogue entries carry no stable persistent ID, that identity has to be replaced
before catalogue support is possible.

## Questions

| | Question | Why it matters |
|---|---|---|
| **Q1** | Does inserting a play-parameters descriptor into a queue set from `MPMediaItem`s actually play? | Decides whether mixed queues are possible at all |
| **Q2** | What does `queue.items` report for that entry — present? `persistentID`? | Decides whether `syncQueueModel` can still reconcile |
| **Q3** | What does `player.nowPlayingItem` report while it plays? | Decides whether `advanceCurrent(toPersistentID:)` can still track position |
| **Q4** | Does an all-play-parameters queue work (`setQueue` + `startItemPlayParameters`)? | The fallback if mixed queues fail |

## Running it

Debug build, on a device with an Apple Music subscription. Q3 logs itself on every
track change; the rest are triggered by **swiping left on the centre button** (the
mirror of the swipe-right that queues a song).

1. **Start a local queue.** Songs → pick a track you own → it plays.
2. **Q1/Q2** — go to a playlist with catalogue-only tracks (an editorial playlist like
   "WWDC25 Hello"), highlight one, **swipe left**. Banner reads "Spike: Q1/Q2 appended".
   Read the `Q1`/`Q2` lines in the log.
3. **Q3** — press NEXT until the appended track plays, or go to Now Playing and swipe
   left. Read the `Q3` line.
4. **Q4** — on a catalogue playlist, highlight any track and **swipe left** there.
   Banner reads "Spike: Q4 all-catalogue queue". Read the `Q4` lines.

Filter the console on `CatalogueSpike` plus the `Q1`–`Q4` prefixes.

## Reading the results

**Plan A — mixed queues work.** Q1 plays, Q2 shows the entry in `queue.items`, and Q3
gives a stable non-zero identifier for it. Catalogue and local tracks can live in one
queue. Work: a `PlaybackHandle` enum (`.mediaItem` / `.playParameters`), a resolve
chain preferring local items, and `PlaybackQueue`'s identity moving from
`MPMediaEntityPersistentID` to an identifier that covers both. That last part is
invasive — `advanceCurrent`, `syncQueueModel` and every transaction's item matching key
on it.

**Plan B — mixed queues don't work.** Q1 fails, or Q2/Q3 show entries with no usable
identity. A queue becomes all-local or all-catalogue, decided by its first track, and
queueing across kinds is refused with an explicit banner. Q4 decides whether catalogue
playlists can play at all.

**Neither** — Q1 and Q4 both fail: catalogue playback isn't reachable through
`MPMusicPlayerController`, and the only remaining route is MusicKit's
`ApplicationMusicPlayer`. That would cost podcast and local-file playback, which this
app supports, so it is not a straight trade.

## Regardless of the outcome

- Prefer `.mediaItem` whenever a local item exists. Play parameters need network and a
  subscription, so a downloaded song queued as catalogue would stop working offline.
- Gate catalogue handles on `subscriptionState`. `localItemFilter` already hides
  undownloaded cloud items from non-subscribers; without the same gate the app would
  queue things that cannot play.
- Podcasts stay `MPMediaItem`-only — they have no MusicKit representation.
