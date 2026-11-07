# Component identification — decibels-rb

An inventory already exists at `.reports/component-inventory.md`, produced
with this skill and explicitly labelled as such in its own header. This audit
re-verified it against the current `lib/` tree rather than re-running the
whole scan from scratch, because the existing document's claims checked out
line for line:

- `lib/window.rb`'s stack: confirmed by reading the file directly — exactly
  two named pages (`empty`, `error`), no `player` page, no `stream` property,
  no `player` action group. Matches the inventory's "partial" verdict on this
  file exactly.
- `lib/` file list: confirmed by `find lib exe -type f` — 14 Ruby files (plus
  `exe/decibels`), none named `player_state.rb`, `mpris.rb`, `media_stream.rb`
  or `waveform_generator.rb`, matching the inventory's "Still absent" list
  exactly.
- Non-widget surfaces (icons, desktop entry, metainfo, D-Bus service file,
  translations): spot-checked against `data/` and confirmed present/absent as
  the inventory states, including its own correct flag that translations are
  "the one parity surface that has not been started."

No drift was found between the inventory and the tree it describes. The
document is current as of `6335b89` and this audit's findings in
`COMPONENT_PARITY.md`, `TEST_PARITY.md`, `TRANSLATION_PARITY.md` and
`ACCOUNTABILITY_ENSURANCE.md` all build on it directly.

## One correction

The inventory's component table (`component-inventory.md`, "Components, in
the order a user meets them") stops short of giving `src/player.ts`,
`src/stream.ts`, `src/waveform-generator.ts` and `src/mpris.ts` full
per-widget rows the way it does for the built units — it names them in the
"Still absent" line and in "Blockers and open questions" instead, but does
not table their widget/CSS/signal/action inventory the way `empty.ts` or
`error.ts` get tabled. For a unit that does not exist yet, cataloguing the
upstream widget tree in full (every `Gtk.Button`, its CSS class, its signal)
is exactly what tells a future agent the actual shape of the remaining work
rather than just its name. This audit did not backfill those four tables —
doing so properly means reading `src/player.ts`, `data/player.blp`,
`src/stream.ts`, `src/waveform-generator.ts` and `src/mpris.ts` in full,
which is scoped as a gap in `ACCOUNTABILITY_ENSURANCE.md` rather than done
silently here.
