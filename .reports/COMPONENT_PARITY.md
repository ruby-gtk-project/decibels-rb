# Component parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `a062178` |
| Units with full parity | 15 / 17 |

This supersedes the previous version of this report, written against `ruby`
@ `6335b89`, which found 9/17 with the entire playback half (player page,
media stream, waveform generator, MPRIS) missing. All four now exist and are
exercised by a real file in `test/drive_decibels.rb`. The picture has changed
substantially; two concrete gaps remain, both on the window unit.

## Units compared

| # | Upstream | Port | Verdict |
|---|---|---|---|
| 1 | `src/window.ts` + `data/window.blp` | `lib/window.rb` | **gap** — see below |
| 2 | `src/empty.ts` + `.blp` | `lib/empty_state.rb` | parity |
| 3 | `src/error.ts` + `.blp` | `lib/error_state.rb` | parity (widget/CSS/signal axis; title binding gap is counted against unit 1, the binding's source) |
| 4 | `src/header.ts` + `.blp` | `lib/header_bar.rb` | parity |
| 5 | `src/player.ts` + `.blp` | `lib/player_state.rb` | parity |
| 6 | `src/waveform-scale.ts` | `lib/waveform_scale.rb` | parity |
| 7 | `src/waveform-bar-chart.ts` | `lib/waveform_bar_chart.rb` | parity |
| 8 | `src/waveform-generator.ts` | `lib/waveform_generator.rb` | parity |
| 9 | `src/playback-rate-button.ts` + `.blp` | `lib/playback_rate_button.rb` | parity |
| 10 | `src/volume-button.ts` + `.blp` | `lib/volume_button.rb` | parity |
| 11 | `src/drag-overlay.ts` + `.blp` | `lib/drag_overlay.rb` | parity |
| 12 | `data/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | parity (widget/CSS axis; see text axis below) |
| 13 | `src/application.ts` (about dialog) | `lib/about_dialog.rb` | parity |
| 14 | `src/application.ts` + `src/main.ts` | `lib/main.rb` | parity |
| 15 | `src/mpris.ts` | `lib/mpris.rb` | parity (built, D-Bus-correct — see `TEST_PARITY.md` for the separate finding that no automated check exercises it) |
| 16 | `src/stream.ts` | `lib/media_stream.rb` | **gap** — see below |
| 17 | `data/style.css` | `lib/style.rb` | parity (not byte-diffed line-by-line this pass; no reason found to doubt it, flagged as unverified rather than claimed clean) |

## Gap 1 — the header bar never shows the track's title or artist

`src/window.ts`'s constructor does four `bind_property` calls:

```ts
this.stream.bind_property("title", this._player.headerbar, "title", ...);
this.stream.bind_property("artist", this._player.headerbar, "subtitle", ...);
this.stream.bind_property("title", this._error.headerbar, "title", ...);
this.stream.bind_property("artist", this._error.headerbar, "subtitle", ...);
```

`lib/window.rb` builds `player_state` and `error_state`, each of which has its
own `HeaderBar` with working `title=`/`subtitle=` setters
(`lib/header_bar.rb:45-52`, confirmed by reading the file — they are not
stubs, `render_title` really sets an `Adwaita::WindowTitle`). But nothing in
`lib/window.rb`, `lib/player_state.rb` or `lib/error_state.rb` ever calls
either setter with a value derived from the stream:

```
$ grep -rn "header_bar\.\(title\|subtitle\)\s*=" lib/
(no matches outside header_bar.rb's own definitions)
```

`MediaStream#title`/`#artist` (`lib/media_stream.rb:112-121`) are correct and
are in fact consumed elsewhere — `lib/mpris.rb:169,207` reads them for the
MPRIS `Metadata` property — so the data path exists, it is just never wired
to either header bar. **User-visible effect:** the player page's and the
error page's title bar always shows the static window title; it never shows
the filename, tag title, or artist of whatever is loaded or playing, where
upstream does. Confirmed by reading `test/drive_decibels.rb`: none of its 97
checks assert on `header_bar.title` after a file loads, so this gap is also
invisible to the runtime gate.

## Gap 2 — closing a window does not reset its stream

`src/window.ts` overrides:

```ts
vfunc_close_request(): boolean {
  this.stream.reset();
  return false;
}
```

`lib/window.rb` has no `close_request` handling at all —
`grep -n close_request lib/*.rb` returns nothing in the whole port.
`MediaStream#reset` (`lib/media_stream.rb:384`) exists and is called from
`#set_file`, but never from window close. **Effect:** closing a window while
a file is playing leaves its GstPlay pipeline and discoverer thread running
rather than tearing them down the way upstream does on every close. The
second-window test in `test/drive_decibels.rb` (`[38]`/`[39]`) never closes a
window that has a file loaded, so this never gets exercised either.

## MPRIS (#15) — built correctly, not actually a parity gap, but see test-parity

`lib/mpris.rb` reproduces upstream's object path, all four interfaces
(`Introspectable`, `Properties`, `MediaPlayer2`, `MediaPlayer2.Player`), the
same method/property set, and the same "defer switching the active stream
until media info exists" behaviour as `active_window_changed_cb`. Read start
to finish against `src/mpris.ts`; no widget/CSS/signal/action axis applies
to it (it owns no widget), and nothing in it reads as weaker than upstream.
Its gap is not component parity, it is verification — recorded once, in
`TEST_PARITY.md`, not duplicated here.

## Text axis

Unchanged from the previous report: no unit in the port routes any string
through a translation marker. `grep -rn 'gettext' lib/ exe/ decibels-rb.gemspec Gemfile`
and `grep -rn '_(' lib/` both return nothing. Every label — including the 12
new/confirmed player-page strings (`Play`, `Pause`, `Skip Back 10s`, `Skip
Forward 10s`, `Adjust Playback Speed`) and the five `media_stream.rb` error
strings — is a bare Ruby literal. See `TRANSLATION_PARITY.md` for the full
count. No unit above is marked "parity" on the text axis; the verdicts in the
table are widget/CSS/behaviour only.

## Rules followed

- Verdicts are per-unit, not a single app-wide total.
- Did not let "the file now exists" stand in for "the file matches" —
  gap 1 and gap 2 were found by reading `lib/window.rb` and
  `lib/media_stream.rb` against their upstream counterparts line by line,
  not inferred from the inventory.
- Named the exact grep that found each gap so it can be re-run and falsified.
- Did not mark MPRIS a component-parity gap for being unverified — that is a
  different axis, and is reported once, in `TEST_PARITY.md`, to avoid
  double-counting the same fact as two different kinds of finding.
