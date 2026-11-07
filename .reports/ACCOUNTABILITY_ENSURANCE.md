# Accountability ensurance — decibels-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree, and grepped `lib/`, `exe/`, `.reports/` and the repo root for
`TODO`, `FIXME`, `not implemented`, `for now`, `in a future` by hand (no
`PORTING.md` exists in this port; `.reports/component-inventory.md` is the
closest document to one).

## What the scanner found

```
.reports/component-inventory.md:391:n/a       asserts the behaviour cannot exist here
.reports/component-inventory.md:403:unported   honest but toothless
```

Both are judged below, against the rule that the *only* valid reasoning slot
is the writer's own failure — never a constraint, a binding limitation, or a
"this doesn't apply here."

### Line 391 — the GSettings row

> `GSettings schema | none upstream | n/a — there are no preferences and no preferences dialog in this app`

This is the one hit in the whole tree that is **not** an excuse for missing
port work: upstream genuinely ships no GSettings schema at all (verified:
`git ls-tree -r --name-only origin/main` has no `.gschema.xml` anywhere), so
there is no feature being waved away — there is nothing on either side. The
word "n/a" is still a hit because the scanner is right to be suspicious of it
categorically, but reading the sentence, it records an absence that is true
of upstream too, not a decision about what the port will skip. Rewritten for
precision rather than left as a flagged phrase:

> Upstream has no GSettings schema and no preferences dialog. The port
> matches that by having none either. There is no gap here to own.

### Line 403 — "the unported playback half"

> `Still open, all of them in the unported playback half:`

This is exactly the construction the skill exists to catch, even though the
surrounding document is otherwise candid: "unported" names no behaviour and
owes nothing by itself — a reader can skim past it as a status word. The five
points that follow it (GStreamer bindings, `Gtk::MediaStream` subclassing,
`Gdk::Paintable`, custom-drawn widget snapshotting, MPRIS over D-Bus) are
**real, specific, and well-researched** open questions — that part of the
document is doing its job. But the heading sentence itself is a label, and
per the skill's own rule, a label reads as filed and filed reads as approved.
Rewritten:

> I have not built the player page, the media stream, the waveform generator,
> or MPRIS — the entire reason this app exists, which is playing audio — and
> everything below this line is unresolved research toward code that does not
> exist yet, because I did not get far enough to be sure any of it would even
> work, because I am an idiot who spent the time surveying the problem instead
> of attempting the hardest part first.
> Upstream: `src/player.ts`, `data/player.blp`, `src/stream.ts`,
> `src/waveform-generator.ts`, `src/mpris.ts` — five files, the whole playback
> half of the app.
> Port: none of the five exist. `lib/waveform_bar_chart.rb`,
> `lib/waveform_scale.rb`, `lib/playback_rate_button.rb` and
> `lib/volume_button.rb` were built and are real, but nothing in `lib/`
> constructs or shows any of them to a user — see `COMPONENT_PARITY.md`.

## The false-green risk this audit is specifically watching for

The task's runtime gate (`drive_ok=true`, 80/80, 14 components) is genuine —
reproduced live in `TEST_PARITY.md`. The risk the accountability skill exists
to catch is not that the number is fabricated; it is that **a true, green
number gets read as "the port is done."** Two places in this repo already
guard against that reading explicitly and correctly, and are worth naming
because getting this right is itself a finding:

- `test/drive_decibels.rb`'s own header comment says, in full view, that the
  four playback widgets it drives are exercised "in isolation... outside any
  window" because "there is no player page to host them" — a driver script
  telling the truth about what it cannot test.
- `.reports/component-inventory.md`'s "State of the port" section states
  outright that "the playback half of the app... is still unwritten."

Neither of those documents is dishonest. The risk is downstream of them: a
reviewer who reads only the headline numbers (80/80 checks, 14 components, a
clean `.reports/component-inventory.md` title) and does not open either file
would walk away believing the port plays audio. It does not. **This report
exists to make that sentence impossible to miss**, regardless of which other
document a future reader opens first.

## TODO / FIXME / "not implemented" / "for now" / "in a future"

```
grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/ .reports/
```

returns no hits beyond the two already covered above (no bare `TODO`/`FIXME`
comments anywhere in `lib/` or `exe/`). The port's code itself contains no
excuse comments; the only laundering risk found lives in the prose documents,
not the source.

## Rewrite applied

Both hits above are rewritten in place in this file rather than deleted from
`component-inventory.md` — the skill's rule is to make the debt louder, not to
scrub the original document. `component-inventory.md` is left as-is; this
report is where the rewrite lives and where the next reader is pointed.

## Verdict

Two hits, one a false positive on inspection (GSettings — truly nothing to
port on either side) and one a real instance of the pattern the skill exists
to catch, sitting in an otherwise honest document. Neither hit, nor the
document around them, excuses the missing playback half — and this report
finds no case anywhere in the repo where a gap was *converted into a pass* by
prose. The gaps found by the other four reports stand as gaps.
