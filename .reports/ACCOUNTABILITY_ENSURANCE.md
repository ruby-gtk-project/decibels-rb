# Accountability ensurance — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `a062178` |

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree (including the other four reports just rewritten in this
pass) and hand-grepped `lib/`, `exe/`, `.reports/` for `TODO`, `FIXME`,
`not implemented`, `for now`, `in a future`. No `PORTING.md` exists in this
port.

## Source (`lib/`, `exe/`): one hit, judged not an excuse

```
$ grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/
lib/mpris.rb:13:# `NotImplementedError: TODO: Ruby -> GVariant(...)` from `GLib::Variant.new`
```

Read in context (`lib/mpris.rb:5-21`): this is the comment block explaining
*why* `lib/mpris.rb` builds every GVariant through
`GLib::Variant.parse(text, type)` instead of the generic
`GLib::Variant.new`/`VariantBuilder` path upstream's `DBusInterface` base
class uses. The quoted string `NotImplementedError: TODO: Ruby -> GVariant(...)`
is the literal exception text this binding version raises — the comment is
naming a binding limitation it found and names the specific workaround it
built (`Variant.parse`, cross-referenced against showtime-rb's and
blanket-rb's own `Mpris` classes as the house answer). This is not a label
standing in for undone work; it is documentation of a already-solved
problem. No rewrite needed — the only reason this hit exists is that the
word "TODO" happens to appear inside a quoted runtime error string, not as
an admission.

## The scanner's hits inside `.reports/` itself

```
$ .claude/skills/accountability-ensurance/scripts/find-excuses.sh .
.reports/component-inventory.md:8  "out of scope" — redefines the target
.reports/TEST_PARITY.md:9          "not ported"   — honest but toothless
.reports/TRANSLATION_PARITY.md:27  "unported"     — honest but toothless
```

Each judged on the only question that matters — is a real, owed behaviour
being waved away, or is the surrounding sentence already naming it in full:

- **`component-inventory.md:8`, "out of scope":** `"...translation parity is
  a gap but out of scope for this component survey (see the
  translation-parity skill)."` This is a cross-reference to a sibling skill
  that owns that axis explicitly (per this org's own skill boundaries,
  `component-identification` scopes to widgets/CSS/signals/actions, not
  text), not a redefinition that makes the gap disappear — the same sentence
  names the gap as a gap in the clause right before "out of scope," and
  `TRANSLATION_PARITY.md` carries the full 0/60 count forward. Verdict:
  false positive, same shape as the GSettings line the previous pass
  correctly cleared.
- **`TEST_PARITY.md:9`, "not ported":** this is the literal value in the
  `| Gaps (upstream tests not ported) | 0 |` table row, reporting that
  upstream has zero tests to port, not that the port skipped porting any.
  Verdict: false positive — the number next to it is `0`, and the
  surrounding prose explains why (upstream never wrote tests).
- **`TRANSLATION_PARITY.md:27`, "unported":** `"...src/player.ts and
  src/stream.ts — previously unported, so their strings had no port-side
  counterpart..."` — past tense, describing the *previous* audit's state,
  immediately followed by "now both have port files" and the explicit
  conclusion that their strings are still untranslated bare literals in the
  current port. The sentence does the opposite of filing a gap as closed —
  it tracks a sub-gap closing (file exists now) while keeping the larger one
  (0/60 translated) open in the very next sentence. Verdict: false positive.

No hit in this pass reads as a gap converted into a pass by wording. This is
a change from the standing risk the task brief calls out generically — it
means the rewrite loop found nothing to rewrite this time, not that the loop
was skipped.

## The false-green risk this audit is specifically watching for

The task's runtime gate (`drive_ok=true`, 97/97, 17 components) is genuine —
reproduced live in `TEST_PARITY.md`. The risk is not the number; it is
reading "97/97, 17 components" as "every one of the 17 components is
verified." It is not:

- **MPRIS (component #15 of 17) has zero automated checks.**
  `test/drive_mpris_server.rb` is the only script that touches it, and it
  makes no assertions — it idles so a human can run `gdbus call` by hand.
  `grep -ni mpris test/drive_decibels.rb` → 0 hits. The 97 checks are real
  and they are real evidence for the other 16 components; they are not
  evidence that MPRIS works. See `TEST_PARITY.md` for the full finding.
- **The header-bar title/artist binding and the close-request stream reset**
  (`COMPONENT_PARITY.md`, gaps 1 and 2) are both real behavioural gaps that
  the 97-check suite does not exercise and therefore cannot catch — neither
  gap would make any existing check fail. A green run and a component gap
  can and do coexist here; the gate passing says nothing about either.

Nobody in this repository is currently asserting "97/97 means the port is
finished" — there is no `PORTING.md` and no claim in `lib/` or `exe/` to that
effect. The risk is purely in a reader stopping at the headline number
without opening the other four reports, which is exactly what this document
and this pass are for.

## Verdict

One source-level hit, not an excuse (documents a solved binding problem).
Three report-level scanner hits, all false positives on inspection (each
names the real gap in the same sentence or the row next to it). Two new,
real, concrete gaps were found this pass by reading code
(`COMPONENT_PARITY.md` gaps 1–2) and one new, real, concrete verification gap
(MPRIS has no automated check, `TEST_PARITY.md`) — none of the three is
excused anywhere in this tree; all three are named plainly as open in their
respective reports and are not converted into a pass here or anywhere else.
