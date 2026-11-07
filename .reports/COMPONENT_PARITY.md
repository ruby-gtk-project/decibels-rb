# Component parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` (origin/main, GNOME Decibels, GJS/TypeScript + blueprint) |
| Port | `ruby` @ `6335b89` |
| Units with parity | 9 / 17 |

This audit re-derives the mapping already written in
`.reports/component-inventory.md` (produced by the `component-identification`
skill) and checks it against the four parity axes. The inventory's own
"State of the port" summary is accurate; this report makes the parity verdict
explicit per unit.

## Units compared

| # | Upstream file(s) | Port file | Verdict |
|---|---|---|---|
| 1 | `src/main.ts` + `src/application.ts` | `lib/main.rb` | **parity**, minus 2 behaviours below |
| 2 | `src/window.ts` + `data/window.blp` | `lib/window.rb` | **gap** — no `player` stack page |
| 3 | `src/drag-overlay.ts` + `data/drag-overlay.blp` | `lib/drag_overlay.rb` | parity |
| 4 | `src/header.ts` + `data/header.blp` | `lib/header_bar.rb` | parity |
| 5 | `src/empty.ts` + `data/empty.blp` | `lib/empty_state.rb` | parity |
| 6 | `src/error.ts` + `data/error.blp` | `lib/error_state.rb` | parity |
| 7 | `data/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | parity (text axis: see below) |
| 8 | `src/application.ts` (`show_about_dialog_cb`) | `lib/about_dialog.rb` | parity |
| 9 | `data/style.css` | `lib/style.rb` | parity (stylesheet not diffed line-by-line in this pass — flagged, not verified) |
| 10 | `src/player.ts` + `data/player.blp` | **none** | **gap — whole unit missing** |
| 11 | `src/stream.ts` | **none** | **gap — whole unit missing** |
| 12 | `src/waveform-generator.ts` | **none** | **gap — whole unit missing** |
| 13 | `src/waveform-bar-chart.ts` | `lib/waveform_bar_chart.rb` | **gap** — widget built, never instantiated by any window (no `player` page exists to host it) |
| 14 | `src/waveform-scale.ts` + bits of `data/player.blp` | `lib/waveform_scale.rb` | **gap** — same: orphaned widget |
| 15 | `src/playback-rate-button.ts` + `data/playback-rate-button.blp` | `lib/playback_rate_button.rb` | **gap** — orphaned widget |
| 16 | `src/volume-button.ts` + `data/volume-button.blp` | `lib/volume_button.rb` | **gap** — orphaned widget |
| 17 | `src/mpris.ts` | **none** | **gap — whole unit missing** |

9 units have full parity. 8 do not: 4 are entirely unbuilt (no port file exists
at all), and the other 4 (13–16) are real, well-built widgets that are
unreachable by a user — nothing in `lib/window.rb` or anywhere else
constructs or displays them, because the `player` stack page that would host
them (unit 10) was never written.

## The central finding

`lib/window.rb`'s `Gtk::Stack` has exactly two named pages, `'empty'` and
`'error'`. Upstream's `window.blp` has three: `empty`, `error`, and `player`.
Accepting a file (`Window#accept`) sets `@file` and enables `show-file` — and
never switches the stack to a player page, because there is none to switch to.
**The port cannot play audio.** Opening a valid audio file silently leaves the
user on the empty page forever; there is no code path from "file accepted" to
any audio output, waveform, or transport control in this entire port. This is
not a rough edge on the core feature — it is the absence of the core feature.
The app's own name ("Audio Player") describes behaviour this port does not
have.

## Axis-by-axis, unit 2 (`lib/window.rb`)

| Widget/behaviour | Upstream | Port | Verdict |
|---|---|---|---|
| `Gtk.Stack` pages | 3 (`empty`,`error`,`player`) | 2 (`empty`,`error`) | **gap** |
| `win.open-file`, `win.show-file` actions | present | present | parity |
| File dialog, audio filter | present | present | parity |
| `stream` property on the window | present | **absent** | **gap** — no stream, no player, nothing to hand to MPRIS |
| `player` action group (play/pause, seek, rate, volume) | present | **absent** | **gap** |
| `key_pressed_cb` (space = play/pause etc., captured at the window) | present | **absent** | **gap** |
| Title bindings (window title tracks the loaded file) | present | **absent** | **gap** — confirmed by the drive script itself: `header_bar.title_widget.title` is only ever set/cleared manually in the driver, never by `window.rb` reacting to a loaded file |
| `<Control>w` as a class-level `Gtk.Shortcut` | present | bound as an app-level accel instead | correspondence, not a gap (same accelerator, different mechanism — noted already in the inventory) |

## Text axis

`shortcuts_dialog.rb`, `header_bar.rb`, `error_state.rb`, etc. all build their
labels as **bare Ruby string literals** — `'File Cannot Be Played'`, `'_Open…'`
— not through any gettext marker. The inventory's own "Non-widget parity
surfaces" table already says this plainly: *"no `po/`, no gettext wiring,
every string a bare Ruby literal."* Every label in every unit above that
passes on widget/CSS/behaviour still fails the text axis. See
`.reports/TRANSLATION_PARITY.md` for the full count; it is cross-referenced
here because a unit cannot be marked "parity" outright while its text axis is
an unconditional gap. The verdicts above describe widget/CSS/behaviour only;
**no unit in this port has text-axis parity**, because no unit uses a
translation marker at all.

## Stylesheet

`lib/style.rb` loads `data/style.css` via `Gtk::CssProvider`. This audit did
not byte-diff it against upstream's `data/style.css` line by line — flagged
as **unverified**, not claimed clean. Given that four of the widgets the
stylesheet would style (`waveform-bar-chart`, `waveform-scale`,
`playback-rate-button`, `volume-button`) are never instantiated, any rules for
their CSS classes are currently dead code regardless of whether the file
matches byte-for-byte.

## Rules followed

- Verdicts are per-unit, not an app-wide total — a project-wide "9/17 pass" does not by itself distinguish "ported the player" from "ported forty buttons scattered anywhere," which is why the table above names the unit.
- The four orphaned widgets (13–16) are recorded as gaps, not as "extra" or "parity" — a correct widget nobody can reach is not a built feature.
- `PORTING.md`/`component-inventory.md`'s own candour about the missing playback half is good practice and is cited above for navigation, but it carries no authority over scope — it does not convert the gap into a pass.
