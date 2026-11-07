# Translation parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `6335b89` |
| Domain | `gnome-decibels` upstream (`meson.project_name()` in `meson.build`) — port has **no domain**, no gettext dependency at all |
| Upstream messages | 60 distinct `(msgctxt, msgid)` keys (70 occurrences, 10 reused; 1 plural (`%d %%`, implicit via ngettext-style context `"volume percentage"` — actually single with context, see below), 12 carry the `"shortcut window"` context) |
| Ported | 0 |
| Gaps | 60 |
| Extra (untranslated) | 10, incidentally |
| Upstream occurrences | 70 across 60 messages (censused with `.claude/skills/translation-parity/scripts/msgid-census.sh` against a detached `origin/main` worktree, after excluding `po/*.po` and the two ambient-TypeScript `.d.ts` files whose function-signature text the scanner misreads as `!unresolved` markers — those are not real messages) |
| Port occurrences | 13 across 10 messages — see "What looks like 10 ported strings, and isn't" below |
| Upstream languages | 57 `.po` files, matching `po/LINGUAS` exactly (57 entries) |
| Languages shipped by the port | **0** |
| Build command | none — no `po/`, no `Rakefile` gettext task, no `msgfmt`/`rmsgfmt` anywhere in the port |

## Upstream source files, by message count

`src/application.ts`, `src/drag-overlay.ts`, `src/error.ts`, `src/player.ts`,
`src/stream.ts`, `src/volume-button.ts`, `src/window.ts`, and
`data/drag-overlay.blp`, `data/empty.blp`, `data/error.blp`, `data/header.blp`,
`data/player.blp`, `data/shortcuts-dialog.blp`, `data/volume-button.blp`,
`data/window.blp`, `data/org.gnome.Decibels.desktop.in.in`,
`data/org.gnome.Decibels.metainfo.xml.in.in` — matching `po/POTFILES.in`
exactly (verified: the census's file list and `POTFILES.in`'s 17 entries
agree).

## What looks like 10 ported strings, and isn't

The port ships `data/org.rubygtkproject.Decibels.desktop` and
`data/org.rubygtkproject.Decibels.metainfo.xml`, adapted from upstream's. 10 of
upstream's 60 msgids (`Audio Player`, `Play audio files`, `Adjustable playback
speed`, `An elegant waveform of the track`, `Easy seek controls`, `Playing
multiple files at the same time`, `The GNOME Project`,
`music;player;media;audio;decibels;`, and the two longer descriptive sentences)
survive byte-identical in those two files, because they were carried over
verbatim as plain English text. **This is not translation parity.** There is
no `po/` directory, no `.pot`, no domain, no `msgfmt`/`rmsgfmt` build step, and
nothing marks these strings for extraction — they are English text in a port
with no i18n mechanism, and would be emitted exactly like this to a German
locale. They are recorded here as a correspondence of *wording*, explicitly
**not** as `ported`.

## The other 50 messages

Every string in `lib/*.rb` — `'File Cannot Be Played'`, `'No available audio
file found'`, `'Open…'`, `'_Keyboard Shortcuts'`, all 12 shortcuts-dialog
entries, the three player-page strings (`Play`/`Pause`/`Skip Back 10s`/etc.,
which exist upstream in `src/player.ts` and `data/player.blp` but have no port
file to even start from) — is a bare Ruby literal. None go through `_()`,
`n_()`, `C_()` or any marker; the `gettext` gem is not in `decibels-rb.gemspec`
or `Gemfile`. Confirmed with
`grep -rn "gettext" lib/ exe/ decibels-rb.gemspec Gemfile` → no hits, and
`grep -rn '_\(' lib/` → no hits.

## Languages

| | Upstream | Port |
|---|---:|---:|
| `.po` files | 57 | 0 |
| `LINGUAS` entries | 57 (matches file list) | — |
| Languages reaching a user | 57 | **0** |

Every one of the 57 languages upstream ships — `ar`, `de`, `fr`, `ja`, `zh_CN`,
`zh_TW`, and 51 more — is simply gone. No user of this port can ever see
anything but English, in any locale, because there is no mechanism by which
they could.

## Summary

```
0/60 messages · 0/70 occurrences · 0/57 languages · 0 translated strings
```

`summary.parity: false` — gaps (60) is non-zero, languages_missing is all 57,
and there is no domain to match. This is not a partial result; it is the
"when upstream has no translations" case inverted — upstream has a full,
mature catalogue and the port has started none of it.

## Messages still owed (representative — grouped by upstream file; full 60-row
table omitted here for space, census data is in `/tmp/up-real-msgids.tsv`-shaped
form and can be regenerated with
`.claude/skills/translation-parity/scripts/msgid-census.sh <origin/main worktree>`)

| Upstream file | Count | Sample msgids still owed verbatim |
|---|---:|---|
| `src/window.ts` + `data/window.blp` | 8 | `File Cannot Be Played`, `Directories Cannot Be Played`, `No available audio file found`, `No file was selected`, `Open File`, `Audio files`, `Please select a file.`, `The selected file is not a regular file.` |
| `data/header.blp` | 6 | `_About Audio Player`, `_Keyboard Shortcuts`, `Main Menu`, `New Window`, `Open…`, `Show in _Files` |
| `data/shortcuts-dialog.blp` (ctxt `shortcut window`) | 12 | `General`, `Show Shortcuts`, `New Window`, `Quit`, `Player`, `Open File`, `Pause/Play`, `Go Back 10 Seconds`, `Go Forward 10 Seconds`, `Playback Rate`, `Increase Playback Rate`, `Decrease Playback Rate`, `Reset Playback Rate` |
| `src/stream.ts` | 5 | `File uses a format that cannot be played. Additional media codecs may be required.`, `An error happened while trying to get information about the file. Please try again.`, `File uses an invalid URI`, `Reading the file's information timed out. Please try again.`, `The selected file doesn't contain any audio`, `Unknown File` |
| `src/player.ts` + `data/player.blp` | 5 | `Play`, `Pause`, `Skip Back 10s`, `Skip Forward 10s`, `Adjust Playback Speed` |
| `src/volume-button.ts` + `data/volume-button.blp` (ctxt `volume percentage` for `%d %%`) | 4 | `Muted`, `Full Volume`, `Mute/Unmute`, `%d %%` |
| `data/empty.blp` | 3 | `Play Audio Files`, `Drag and drop audio files here`, `_Open…` |
| `data/drag-overlay.blp` | 2 | `Drop Here to Open`, `Unable to access dropped files` |
| `data/error.blp` | 2 | `An unknown error happened`, `_Try Again…` |
| `src/application.ts` | 1 | `translator-credits` |
| desktop/metainfo (see "What looks like 10 ported strings" above) | 10 | present as English text, not as translation infrastructure |

Every row above whose upstream file has no port counterpart at all
(`src/stream.ts`, `src/player.ts`) is doubly blocked: it cannot become
`ported` until `COMPONENT_PARITY.md`'s matching component gap closes first.

## Rules followed

- Did not reword anything while reading it; every "still owed" string above is transcribed, not retyped.
- Did not count the 10 desktop/metainfo strings as `ported` just because the bytes match — there is no catalogue, no domain, no marker, so translation parity is not what produced the match.
- Reported occurrences as well as messages, and did not treat `uses_mismatch`-shaped findings as a pass condition.
- Named every unrun check: `msgfmt -c` validation was not run (no `po/` exists to validate), and no non-English locale run was performed (there is nothing to display in one).
- Stated the "0 of 57 languages" headline explicitly rather than leaving it as an implication of a message count.
