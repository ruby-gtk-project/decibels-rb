# Test parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `6335b89` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | none exists for upstream; the port is driven by `nix develop --command xvfb-run -a ruby test/drive_decibels.rb` |

## Upstream has no test suite

Verified directly: upstream's tree has no `test/` or `tests/` directory, no
`meson.build` test target (`grep -n test meson.build src/meson.build` returns
nothing), no GLib `Test.add_func`, no Jasmine `it(...)`, no `.ts` file under a
`spec`/`test` naming convention. GNOME Decibels is a small app and upstream
simply never wrote automated tests for it.

**Parity is 0/0 and is met trivially. The port therefore inherits no safety
net** — every check that exists below was written for the port and pins
nothing upstream considered worth pinning.

## Extra

The port does not use RSpec despite shipping `spec/spec_helper.rb` — that file
holds only SimpleCov/coverage bootstrap, and `spec/` contains **zero actual
spec files**. There is no `bundle exec rspec` suite to run; `spec/` is dead
scaffolding. `test/` is a set of headless GTK driver scripts instead, run
directly with `ruby`, not through any test framework or `rake test` task:

- `test/drive_decibels.rb` — 80 checks (ran live for this audit:
  `nix develop --command xvfb-run -a ruby test/drive_decibels.rb` → **80 of 80
  checks passed, DRIVE OK**, confirming the runtime gate's claim). Covers: the
  window/empty page, the header-bar menu section by section, both error
  states, drag-and-drop, the file dialog's filter, the shortcuts dialog, the
  about dialog, a second window, app accelerators/actions, and — separately,
  explicitly labelled in the script's own header comment as widgets with
  "no player page to host them" — the playback-rate button, volume button,
  waveform bar chart and waveform scale exercised **in isolation**, outside
  any window, because there is nowhere in the real app to exercise them from.
- `test/drive_open.rb`, `test/drive_smoke.rb` — smaller smoke drivers, not
  separately censused in this pass.
- `test/gtk_driver.rb` — the harness the three drivers above share; not a test
  file itself.

## What the 80-check gate does not cover, and why that matters here

The task's runtime gate (`drive_ok=true, 80 checks, 0 failed, 14 components`)
is real and reproduced live in this audit. But "0 failed" is not the same
claim as "complete": **the drive script never opens the player page, never
plays a file, never drives the media stream, and never touches MPRIS — because
none of those exist yet in `lib/`.** A suite that is green because the feature
it would have tested was never built is the exact shape this org's own
`test-parity`/`accountability-ensurance` skills warn about: a component no
check exercises is unverified, not done, and here the single largest
component in the app (playback itself) is in that state. The 80 checks are a
real, passing, non-trivial suite over the parts of the app that exist. They
are not evidence that the app plays audio, because nothing in the suite asks
it to.

## Rules followed

- Reported the exact numbers ("0/0, trivially met, no inherited safety net"), not an adjective.
- Did not pad an empty upstream-test table; stated the 0/0 result and moved straight to what exists instead, under `## Extra`, outside the parity count.
- Ran the port's suite rather than trusting the stated gate — `80 of 80 checks passed, DRIVE OK` reproduced live.
- Named explicitly what the green suite does not exercise, rather than letting a passing run stand in for completeness.
