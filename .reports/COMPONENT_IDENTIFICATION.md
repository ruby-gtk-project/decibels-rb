# Component identification — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` (GNOME Decibels, GJS/TypeScript + blueprint) |
| Port | `ruby` @ `a062178` |

This re-runs the `component-identification` skill against the current tree.
The previous version of this report (and of `.reports/component-inventory.md`)
was written against `ruby` @ `6335b89`, before `lib/player_state.rb`,
`lib/media_stream.rb`, `lib/waveform_generator.rb` and `lib/mpris.rb` existed.
All four now exist. The inventory below supersedes that snapshot.

## Units (one upstream top-level widget class / app-level surface = one row)

| # | Upstream file(s) | Kind | Port file | Exists? |
|---|---|---|---|---|
| 1 | `src/window.ts` + `data/window.blp` | window (`Adw.ApplicationWindow`) | `lib/window.rb` | Yes |
| 2 | `src/empty.ts` + `data/empty.blp` | empty-state page | `lib/empty_state.rb` | Yes |
| 3 | `src/error.ts` + `data/error.blp` | error-state page | `lib/error_state.rb` | Yes |
| 4 | `src/header.ts` + `data/header.blp` | header bar + menu | `lib/header_bar.rb` | Yes |
| 5 | `src/player.ts` + `data/player.blp` | player page | `lib/player_state.rb` | Yes |
| 6 | `src/waveform-scale.ts` | custom widget — seek slider | `lib/waveform_scale.rb` | Yes |
| 7 | `src/waveform-bar-chart.ts` | custom widget — bar rendering | `lib/waveform_bar_chart.rb` | Yes |
| 8 | `src/waveform-generator.ts` | non-widget — peak generator | `lib/waveform_generator.rb` | Yes |
| 9 | `src/playback-rate-button.ts` + `.blp` | menu button | `lib/playback_rate_button.rb` | Yes |
| 10 | `src/volume-button.ts` + `.blp` | menu button | `lib/volume_button.rb` | Yes |
| 11 | `src/drag-overlay.ts` + `.blp` | drop overlay | `lib/drag_overlay.rb` | Yes |
| 12 | `data/shortcuts-dialog.blp` (no `.ts`) | shortcuts dialog | `lib/shortcuts_dialog.rb` | Yes |
| 13 | `src/application.ts` (`show_about_dialog_cb`) | about dialog | `lib/about_dialog.rb` | Yes |
| 14 | `src/application.ts` + `src/main.ts` | application class | `lib/main.rb` / `lib/decibels/application.rb` | Yes |
| 15 | `src/mpris.ts` | app-level service, no widget | `lib/mpris.rb` | Yes (added since the last snapshot) |
| 16 | `src/stream.ts` | non-widget — playback model | `lib/media_stream.rb` | Yes (added since the last snapshot) |
| 17 | `data/style.css` | stylesheet | `lib/style.rb` | Yes |

17 of 17 upstream units now have a corresponding port file. **This table
answers only "does a file exist," not "does the file reproduce the upstream
widget tree, CSS, signals and actions."** That axis-by-axis comparison is
`COMPONENT_PARITY.md`'s job, and the sections below flag where this pass
found drift worth carrying forward into it.

## Drift found against the window unit (#1)

Reading `lib/window.rb` against `src/window.ts` line by line surfaced two
behaviours that identification (not yet full axis comparison) can already
confirm are absent from the port:

- Upstream's constructor binds `stream.title` → `this._player.headerbar.title`,
  `stream.artist` → `this._player.headerbar.subtitle`, and the same pair again
  onto `this._error.headerbar`. `lib/window.rb`/`lib/player_state.rb` build a
  `HeaderBar` with working `title=`/`subtitle=` setters (`lib/header_bar.rb`),
  but nothing in `lib/` ever calls them with the stream's title or artist —
  `grep -rn 'header_bar\.\(title\|subtitle\)\s*=' lib/` has zero matches
  against anything other than the setters' own definitions. `MediaStream#title`
  and `#artist` exist and are read by `lib/mpris.rb`'s
  `on_media_info_updated` callback, so the data is available; it is simply
  never routed to either header bar.
- Upstream overrides `vfunc_close_request` to call `this.stream.reset()`
  before the window closes, stopping the discoverer thread and the GstPlay
  pipeline. `grep -n close_request lib/*.rb` has no hits anywhere in the
  port — no `Window` in `lib/` overrides a close handler, and `#reset` is
  never called from window-close at all (it is called from `#set_file` only,
  via `lib/media_stream.rb:147`).

Both are carried into `COMPONENT_PARITY.md` as gaps on unit #1 rather than
re-derived there.

## Rules followed

- Re-verified the inventory against the tree as it exists now, not against
  the superseded `6335b89` snapshot or the claims already on file.
- Did not accept "a file exists" as "the unit has parity" — flagged the two
  behavioural gaps found while reading the window unit for the parity pass
  to size exactly, instead of leaving them as an impression.
