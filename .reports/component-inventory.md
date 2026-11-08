# Component inventory — decibels-rb

**Updated 2026-11-08, re-verified against `ruby` @ `a062178`.** The row below
for `src/mpris.ts` previously read "No — not present anywhere under `lib/`."
That was true against `ruby` @ `6335b89`; it is no longer true.
`lib/mpris.rb` exists (460+ lines), is wired into `lib/main.rb`, and is read
in full in `.reports/COMPONENT_IDENTIFICATION.md` and
`.reports/COMPONENT_PARITY.md` for this pass. The row and the "Summary"
section below are corrected in place rather than left to mislead a reader who
opens this file instead of the newer reports.

Surveyed against `origin/main` (upstream, GJS/TypeScript) on 2026-11-07.
Upstream has no GSettings schema and no `.gschema.xml` (checked
`data/meson.build`, `find -iname '*.gschema.xml'`) — there is no Preferences
window in this app. Upstream's `po/` catalogue (82 `.po` files) has no
counterpart under `ruby`'s `po/` (there is none) — translation parity is a
gap but out of scope for this component survey (see the `translation-parity`
skill).

Order below follows how a user meets each piece: the window, its states, the
header, the player and its sub-widgets, the dialogs, then the app-level
pieces (application/main, MPRIS) and stylesheet.

| Upstream file(s) | Kind | `lib/*.rb` target | Exists on `ruby`? |
|---|---|---|---|
| `src/window.ts` + `data/window.blp` | window (`Adw.ApplicationWindow`) | `lib/window.rb` | Yes (210 lines) |
| `src/empty.ts` + `data/empty.blp` | empty state page | `lib/empty_state.rb` | Yes (63 lines) |
| `src/error.ts` + `data/error.blp` | error state page | `lib/error_state.rb` | Yes (82 lines) |
| `src/header.ts` + `data/header.blp` | header bar (`Adw.HeaderBar`), open/primary menu | `lib/header_bar.rb` | Yes (101 lines) |
| `src/player.ts` + `data/player.blp` | player page (playback controls, timestamp/duration labels, waveform host) | `lib/player_state.rb` | Yes (312 lines) |
| `src/waveform-scale.ts` | custom widget — seekable waveform slider | `lib/waveform_scale.rb` | Yes (159 lines) |
| `src/waveform-bar-chart.ts` | custom widget — waveform bar rendering (drawn by `waveform-scale`) | `lib/waveform_bar_chart.rb` | Yes (111 lines) |
| `src/waveform-generator.ts` | non-widget helper — generates peak data from the decoded stream | `lib/waveform_generator.rb` | Yes (119 lines) |
| `src/playback-rate-button.ts` + `data/playback-rate-button.blp` | menu button — playback speed popover | `lib/playback_rate_button.rb` | Yes (107 lines) |
| `src/volume-button.ts` + `data/volume-button.blp` | menu button — volume slider popover, mute toggle | `lib/volume_button.rb` | Yes (146 lines) |
| `src/drag-overlay.ts` + `data/drag-overlay.blp` | overlay shown while a file is dragged over the window | `lib/drag_overlay.rb` | Yes (102 lines) |
| `data/shortcuts-dialog.blp` (standalone `.blp`, no backing `.ts`) | `Adw`/`Gtk.ShortcutsWindow` dialog | `lib/shortcuts_dialog.rb` | Yes (64 lines) |
| `src/application.ts` (`show_about_dialog_cb`, no backing `.blp`/`.ts` of its own — inline `Adw.AboutDialog.new_from_appdata`) | about dialog | `lib/about_dialog.rb` | Yes (127 lines) — the port gives it its own file; upstream builds it inline in `application.ts` |
| `src/application.ts` + `src/main.ts` | application class — `app.new-window`/`app.quit`/`app.about`/`app.shortcuts`/`win.open-file` actions, accelerators, `vfunc_activate`/`vfunc_open` (single-file-into-current-window vs. new-window-per-file), one `Window` per activation | `lib/main.rb` (aliased as `Decibels::Application` via `lib/decibels/application.rb`) | Yes (116 lines) — covers actions/accels/open-file logic |
| `src/mpris.ts` (MPRIS D-Bus `org.mpris.MediaPlayer2` interface: play/pause/next/previous/seek/metadata/loop status, wired into `application.ts` via `this.mpris` and `switch_mpris_stream`) | app-level service, no widget — system media-key / lock-screen / shell media-control integration | `lib/mpris.rb` | **Yes, as of `a062178`** (460+ lines, wired into `lib/main.rb`). Built correctly on inspection — see `COMPONENT_PARITY.md`. Not exercised by any automated check — see `TEST_PARITY.md`. |
| `src/stream.ts` (`APMediaStream`, `APPlaySignalAdapter` wrapping `GstPlay.Play`; also exports `get_cubic_volume`/`get_linear_volume` used by `volume-button.ts`) | non-widget model — the playable media stream | `lib/media_stream.rb` | Yes (477 lines) |
| `data/style.css` | stylesheet | `lib/style.rb` | Yes (41 lines) — verify every CSS class upstream defines is still loaded/applied (not re-verified in this pass; see `component-parity`) |
| `src/main.ts` (`main()` entry point) | app entry point | `lib/main.rb` / top-level `exe` | Yes |

## Summary (updated 2026-11-08)

- 17 of 17 upstream units now have a corresponding `lib/*.rb` file on
  `ruby`. Whether each file reproduces its upstream's widgets, CSS classes,
  signals and actions in full is assessed in `COMPONENT_PARITY.md`, not
  here — two concrete gaps were found there (the header bar never receives
  the stream's title/artist; no window closes its stream on close-request).
- MPRIS is no longer missing (corrected above). It is, however, unverified:
  no automated check in `test/` exercises it — see `TEST_PARITY.md`.
- No GSettings schema and no Preferences window exist upstream, so none are
  missing from the port.
- `po/` translation catalogue is still absent from the port entirely (0 of
  57 current-upstream locale files) — see `TRANSLATION_PARITY.md`, which
  this component survey continues to defer to for the text axis by design
  (not as a way of making the gap disappear — it is reported there in full).
