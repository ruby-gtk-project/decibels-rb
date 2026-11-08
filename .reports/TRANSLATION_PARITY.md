# Translation parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `a062178` |
| Domain | `gnome-decibels` upstream — port has no domain, no gettext dependency |
| Upstream messages | 60 distinct `(msgctxt, msgid)` keys, 70 occurrences |
| Ported (via a translation mechanism) | 0 |
| Gaps | 60 |
| Upstream languages | 57 `.po` files, matching `po/LINGUAS` |
| Languages shipped by the port | 0 |
| Build command | none — no `po/`, no gettext task, no `msgfmt` anywhere in the port |

This result is unchanged in substance from the previous audit, written
against `ruby` @ `6335b89`: the port still has no `po/` directory, no
gettext gem dependency, and no `_()`/`n_()`/`C_()` call anywhere in `lib/`.
Re-verified directly against the current tree:

```
$ find . -maxdepth 1 -name po          # nothing
$ grep -rn "gettext" lib/ exe/ decibels-rb.gemspec Gemfile    # no hits
$ grep -n '_(' lib/*.rb                                       # no hits
```

What has changed since the last pass is that `src/player.ts` and
`src/stream.ts` — previously unported, so their strings had no port-side
counterpart to even be a bare literal — now both have port files
(`lib/player_state.rb`, `lib/media_stream.rb`). Their strings are present on
the port side as bare Ruby literals, same as every other unit, closing the
"doubly blocked" note from the previous report (no component to even host a
translation marker). The translation-infrastructure gap itself is unchanged:
0/60 messages go through any marker anywhere, now including these two files.

## Representative messages still owed verbatim (grouped by upstream file)

| Upstream file | Count | Sample msgids |
|---|---:|---|
| `src/window.ts` + `data/window.blp` | 8 | `File Cannot Be Played`, `Directories Cannot Be Played`, `No available audio file found`, `No file was selected`, `Open File`, `Audio files`, `Please select a file.`, `The selected file is not a regular file.` |
| `data/header.blp` | 6 | `_About Audio Player`, `_Keyboard Shortcuts`, `Main Menu`, `New Window`, `Open…`, `Show in _Files` |
| `data/shortcuts-dialog.blp` (ctxt `shortcut window`) | 12 | `General`, `Show Shortcuts`, `New Window`, `Quit`, `Player`, `Open File`, `Pause/Play`, `Go Back 10 Seconds`, `Go Forward 10 Seconds`, `Playback Rate`, `Increase Playback Rate`, `Decrease Playback Rate`, `Reset Playback Rate` |
| `src/stream.ts` → **now** `lib/media_stream.rb` | 5 | `File uses a format that cannot be played...`, `An error happened while trying to get information about the file...`, `File uses an invalid URI`, `Reading the file's information timed out...`, `The selected file doesn't contain any audio` — confirmed present verbatim in `lib/media_stream.rb` as bare constants (`CANNOT_BE_PLAYED`, `DISCOVER_FAILED`, `INVALID_URI`, `TIMED_OUT`, `NO_AUDIO`), none behind a marker |
| `src/player.ts` + `data/player.blp` → **now** `lib/player_state.rb` | 5 | `Play`, `Pause`, `Skip Back 10s`, `Skip Forward 10s`, `Adjust Playback Speed` — confirmed present as literal tooltip/label strings in `lib/player_state.rb`, none behind a marker |
| `src/volume-button.ts` + `.blp` (ctxt `volume percentage` for `%d %%`) | 4 | `Muted`, `Full Volume`, `Mute/Unmute`, `%d %%` |
| `data/empty.blp` | 3 | `Play Audio Files`, `Drag and drop audio files here`, `_Open…` |
| `data/drag-overlay.blp` | 2 | `Drop Here to Open`, `Unable to access dropped files` |
| `data/error.blp` | 2 | `An unknown error happened`, `_Try Again…` |
| `src/application.ts` | 1 | `translator-credits` |
| desktop/metainfo | 10 | carried over byte-identical as plain English in `data/org.rubygtkproject.Decibels.*` — wording matches, not translation infrastructure; not counted as `ported` |

## Languages

| | Upstream | Port |
|---|---:|---:|
| `.po` files | 57 | 0 |
| Languages reaching a user | 57 | 0 |

## Summary

```
0/60 messages · 0/70 occurrences · 0/57 languages
```

No partial credit: there is no `po/`, no `.pot`, no domain, and the two
newly-ported files (`media_stream.rb`, `player_state.rb`) add their strings
to the owed list in exactly the same unmarked state as everything else.

## Rules followed

- Re-verified the "no gettext anywhere" claim against the current tree rather than carrying forward the old grep output unchanged.
- Did not count `media_stream.rb`'s/`player_state.rb`'s strings as newly "ported" just because a port file for them now exists — a bare literal in a new file is the same gap as a bare literal in an old one.
- Did not count the desktop/metainfo wording match as translation parity.
- Stated the 0/57 languages headline explicitly.
