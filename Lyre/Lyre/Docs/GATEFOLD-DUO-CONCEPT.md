# Gatefold on iPhone Duo — Design Concept

Status: **concept + flat-phone implementation.** The Duo layer is not built and
cannot be built on the current toolchain (see "Toolchain" below).

Gatefold is the album-open interaction in `ArtworkCarouselView`. Tapping the centre
cover swings it left through 180° on its **left edge (the spine)**, uncovering a 2:1
spread of two square panels: the record on the left, the printed liner on the right.

This document covers how that interaction should extend to iPhone Duo, Apple's
book-style foldable, and what has to change in Lyre before it can.

---

## 0. The fold animates; a separate view is what you touch

The hinge cannot carry the interactive content. SwiftUI hit-tests against a view's
*untransformed* geometry, so anything inside the flap's `rotation3DEffect` answers in a
mirrored position off to the side, and a layer faded to `opacity(0)` keeps taking
touches because transparency is not the same as being out of the way. Fixing those one
at a time only moved the dead zone from the left panel to the right.

So the two roles are split:

- **`foldAssembly`** is the animation — hinge, reflection, shadows. Once the sleeve is
  open it is not touchable at all.
- **`openSpread`** is the real interface: two square panels in a plain `HStack`, no
  rotation, no offset, nothing drawn outside its bounds. It is shown once the opening
  animation *finishes* and owns every touch.

"Finishes" is tracked with its own flag, set in the `withAnimation` completion. It
cannot be read off `foldProgress`: `withAnimation` sets the stored value to its target
at once and only the rendered value travels, so testing `foldProgress == 1` swapped the
spread in on the first frame and the album appeared with no animation. The spread also
stays in the hierarchy, invisible, for as long as the sleeve is open or being dragged.
The hinge scrub runs on it, and removing a view cancels the gesture running on it.

The two line up because the animated spread lands centred: the centre card is pushed
right by half a panel while its flap swings a full panel left, and the two cancel. The
swap is invisible — the same pixels, with a hit region that finally matches them.

This does not weaken the "one driven value" rule below; `foldProgress` still drives
every visual. It only says that the value drives *pictures*, and the controls live in
a view that value never transforms.

A related rule for anything added to either panel: prefer SwiftUI-drawn controls. The
panels sit well outside their ancestor's frame, which SwiftUI's hit testing tolerates
and UIKit's does not — a `.segmented` `Picker` there never received a touch, which is
why `ABControl` now serves every side count.

### Gesture map

Every drag in the gatefold is told apart by where it starts and which way it goes. A new
gesture must not reuse a slot.

| Where | Tap | Drag | Touch and hold |
|---|---|---|---|
| Closed, centred cover | Open the sleeve | Sideways scrolls the carousel | Play Next / Add to Queue for the whole record |
| Open, left panel | Play, Shuffle, disc | Sideways scrubs the hinge. Down closes. Up flips the record. | — |
| Open, track list | Play the song | Vertical scrolls. Right queues the song. The A/B slider drags between sides. | Play Next / Add to Queue for the song |

The hinge scrub is on the left panel only. Across the whole spread it also ran under the
track list, so scrolling a long playlist moved the hinge and a downward scroll closed it.

Touch and hold is the one slot left, because it is recognised by holding still. When the
menu appears it *cancels* the cover's open gesture (confirmed on device), so `onEnded`
never runs: a hold cannot open the sleeve, but the cover would stay lifted. A
`@GestureState` resets on cancellation, so the view watches it and puts the cover back
down. Do not add state that only `onEnded` clears — it is never cleared after a menu,
which is how a hold-time limit once broke the next ordinary tap. Both menus are mirrored
as VoiceOver actions.

The animated sleeve's interiors are `accessibilityHidden`. They are built even while the
sleeve is closed, only transparent, and transparency does not hide a view from
accessibility — so a closed sleeve used to expose Play, Shuffle and the disc.

---

## 1. Why Gatefold and the Duo fit

The core architectural rule of Gatefold is **one driven value**: a single
`foldProgress: CGFloat` where 0 is a closed sleeve and 1 is an open spread, with every
visual derived as a pure function of it. Animations set it, drags set it, nothing
keyframes independently.

A foldable hands you exactly that value in hardware. The hinge is a continuous 0→1
control, so it becomes a **third input** alongside tap and drag — not a rewrite.

The geometry lines up too. A 2:1 spread of two squares with a gutter down the middle
is what an unfolded book-style foldable *is*. On a 844x390 phone we are simulating a
gatefold sleeve. On a Duo we are holding one.

---

## 2. Posture drives layout, angle drives effect

Apple's guidance for the hinge API is explicit: it is for **interactions and effects,
not layout**. If you are computing frames from the hinge angle, you are on the wrong
API — layout belongs to arrangements and reserved regions.

That constraint produces a cleaner design than ignoring it would. Discrete posture
selects the screen; the continuous angle only drives the animation between them.

| Posture          | State                | What it is                                                                                  |
| ---------------- | -------------------- | ------------------------------------------------------------------------------------------- |
| Folded (outer)   | Now Playing only     | Single square, classic wheel UI. No carousel — there is no room for one.                     |
| Book, ~90–150°   | The carousel         | Cards recede *into* the crease; the physical V supplies the perspective `sideAngle` fakes.   |
| Flat, ~180°      | The Gatefold spread  | Left panel = record, right panel = liner, gutter sitting on the physical crease.             |

**The flow:** you browse with the phone half-folded, and you open an album by opening
the phone. Closing back to book posture closes the sleeve and returns you to the
carousel. The gesture is the hardware.

This also resolves a detail already latent in the flat-phone spec, which notes that
the closed cover sits where the right panel will be. So in book posture the centre
card belongs on the **right** panel, with the queue receding leftward toward the
crease. Opening the device then swings the cover open onto the left panel — into
exactly the space the queue was occupying.

---

## 3. Coupling the hinge to `foldProgress`

**Do not bind `p` to the angle directly.** A straight `p = θ / 180` map means the album
reopens whenever someone shifts their grip, and full-open is unreachable if their hinge
rests at 165°.

Use **last-writer-wins with takeover**. Whichever input moved most recently owns `p`.
A tap or drag takes ownership immediately; the hinge only reclaims it after roughly 6°
of deliberate travel. This is the motorised-car-window pattern: manual input overrides,
and the motor does not fight back.

```
enum FoldDriver { case gesture, hinge, spring }
```

Map the usable window with dead band at both ends, so a flat phone reliably reads as
fully open:

```
p_hinge = clamp((θ - 130) / 45)      // 130° -> 0, 175° -> 1
```

---

## 4. Delete the simulation where the hardware is real

This is the governing principle for the Duo variant. Every cue in the flat-phone design
that *fakes* a physical gatefold has a real counterpart on a folding device, and drawing
both reads as cheap.

| Flat-phone cue                                              | On Duo                                                                 |
| ----------------------------------------------------------- | ---------------------------------------------------------------------- |
| Gutter shadow, `sin(πp) * 0.42 + 0.09p`, settling at 0.09    | The crease shades itself. Drop the resting term to ~0.03.               |
| 3 pt card-coloured edge at the hinge, visible near 90°       | Redundant when the device is genuinely at 90°. Remove.                  |
| Gutter width hardcoded at 52 pt                              | Derive from the division region.                                        |
| Specular sweep tied to fold position                         | Keep. It reads as light on paper, and has no hardware counterpart.      |

---

## 5. Two flat-phone rules that invert on Duo

**Off-centre open.** The flat-phone spec blends the carousel's own ±70° tilt so an album
opened slightly off-centre hinges from where it actually sits. On a Duo the gatefold
*must* hinge exactly on the crease or the illusion collapses. Snap `position` to the
centred index before allowing the fold to start.

**Horizontal shift.** The `0.5 * panel * p` shift that centres the finished spread is a
flat-phone rule. On Duo the panels are pinned to the display halves and nothing shifts.

---

## 6. Haptics

Gatefold fires `.rigid` 0.3 when `p` crosses 0.5 and `.medium` 0.7 on landing flat.
When the user is physically snapping the device open there is already a real mechanical
detent, and a synthetic thunk layered on top of it is muddy.

**Suppress the 90° tick and the landing haptic when `FoldDriver == .hinge`.** Keep both
for tap and drag. All other haptics (record lift, record seat, sleeve re-seat) are
unrelated to the fold and stay as they are.

---

## 7. Accessibility and power

**Reduce Motion.** You cannot turn off the hardware's motion, so the software should
stop *adding* to it: snap between postures at a threshold (θ > 150° reads as open)
rather than tracking the angle continuously.

**Low Power Mode.** Beyond stopping the disc rotation, throttle hinge sampling to about
20 Hz and interpolate. Continuous hinge callbacks recomputing a two-artwork spread with
a rotating disc is the expensive path.

**VoiceOver.** Unchanged from the flat-phone design. The fold is decorative and never
announced; the open state posts "[Album], by [Artist], open. Side A, N tracks."

---

## 8. Blocker: the carousel is unreachable on a Duo

This has to be fixed before any Duo work, and is worth fixing regardless.

`LyreView.swift` (`handleOrientationChange()`) only presents the carousel when
`UIDevice.current.orientation.isLandscape`, and it force-locks
`AppDelegate.orientationLock` through `supportedInterfaceOrientations`.

On the Duo's inner display, reportedly **neither mechanism works**: the inner display
does not honour supported interface orientations, and `UIDevice.orientation` will lie.
Separately, all carousel sizing keys off `verticalSizeClass == .compact` (`coverSize`
210 vs 260), which will not classify usefully on a near-square inner display.

The fix is to re-ground the entry trigger on geometry rather than device orientation.
The same code is fragile on iPad and in multitasking today, so this is not Duo-specific
debt.

---

## 9. Toolchain

| | |
| --- | --- |
| iPhone Duo announced | 9 September 2026 |
| Hinge API ships in | Xcode 27.1 (`onHingeChange`, `UIHingeInteraction`) |
| This project's SDK | **iOS 27.0** — no Duo simulator, no hinge API |

The API details in this document come from press and developer write-ups following the
announcement, not from Apple's documentation, which is not yet in the local doc set.
**Verify every symbol against the real SDK before implementing section 3.**

Reported shape of the API, to be confirmed:

- SwiftUI `onHingeChange` delivers continuous angle updates.
- `context.hinge` is `nil` on every non-folding iPhone — always nil-check.
- `hinge.status` includes `.partiallyOpen`; a closed device reports closed and exposes
  no division region at all.
- `occlusionRegionKind` is **not** fold-specific — relying on it makes every modern
  iPhone report its Dynamic Island as a fold. Foldability cannot be read from regions.

---

## 10. Sequencing

1. **Build Gatefold flat-phone first.** It needs no Duo and no new SDK. Structure it so
   `foldProgress` can accept a third driver, and keep the shift/scale/gutter constants in
   one place so the Duo variant overrides rather than forks the view. *(Done — see
   `GatefoldView.swift`.)*
2. **Unblock the orientation gating** (section 8), independently.
3. **Add the hinge driver** on Xcode 27.1, behind an availability check.
4. **Posture-specific layouts** (section 2) last, once there is a device to feel them on.
