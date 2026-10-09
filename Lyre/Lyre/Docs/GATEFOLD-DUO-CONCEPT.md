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

## 8. Resolved: the carousel trigger follows the window

`LyreView` used to present the carousel on `UIDevice.current.orientation.isLandscape`
and force-lock `AppDelegate.orientationLock`. The Duo's inner display honours neither.

It now follows the window's shape: whenever the classic player's window is wider than
tall, the carousel opens (`windowShapeChanged(isWide:)`). On an ordinary iPhone that is
the same as turning the phone. On the Duo, unfolding to the wide inner display opens
the carousel — "open the phone, open the album". Rotation requests go through the
view's own window scene (`OrientationLock`) instead of `UIApplication.shared`.

Still open: carousel sizing keys off `verticalSizeClass == .compact` (`coverSize` 210 vs
260). Panel size already derives from the measured window, but the closed cover size
should too, once it can be checked on a Duo.

---

## 9. Toolchain

| | |
| --- | --- |
| iPhone Duo announced | 9 September 2026 |
| Hinge API ships in | iOS 27.1 SDK |
| This project's SDK | **iOS 27.1** — hinge API present; Duo simulator needs the 27.1 runtime |

Verified against the SDK headers and interface (not the press write-ups, which were
wrong about the shape):

- SwiftUI: `View.onHingeChange(isEnabled:_:)`, handing old and new `DeviceHingeContext`.
- `DeviceHingeContext.hinge` is `DeviceHinge?` — `nil` on every non-folding iPhone.
- `DeviceHinge.status` is `.closed`, `.partiallyOpen` or `.fullyOpen`; `angle` is an
  `Angle`. Update rate and precision are system policy: prefer `status`.
- UIKit: `UIHingeInteraction`, with `UIHinge.status` and `angle` in radians.
- The hinge does not report how the phone is standing, so book and tent postures cannot
  be told apart from it.

`HingeObserver` (FoldPosture.swift) feeds `FoldPostureMonitor` from `onHingeChange`.

---

## 10. Sequencing

1. **Build Gatefold flat-phone first.** *(Done — see `GatefoldView.swift`.)*
2. **Unblock the orientation gating** (section 8). *(Done.)*
3. **Read the hinge**, behind an availability check. *(Done — posture only.)*
4. **Drive `foldProgress` from the hinge angle** (section 3) — not yet built.
5. **Posture-specific layouts** (section 2), once there is a device to feel them on.
