# Test parity — decibels-rb

| | |
|---|---|
| Upstream | `main` @ `0f70ecb` |
| Port | `ruby` @ `a062178` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps (upstream tests not ported) | 0 |
| Test command | none upstream; port is driven with `nix develop --command xvfb-run -a ruby test/drive_decibels.rb` |

## Upstream has no test suite

Re-verified against `origin/main`: no `test/`/`tests/` directory, no test
target in `meson.build`/`src/meson.build`, no `GLib.Test`, no Jasmine-style
`it(...)`. Upstream never wrote automated tests for this app. Parity on
"upstream tests ported" is 0/0 and trivially met — the port inherits no
upstream safety net; everything below was written for the port itself.

## What exists, and what I actually ran

`spec/` is still dead scaffolding: `spec/spec_helper.rb` only bootstraps
SimpleCov, `spec/README.md` is prose, and there are **zero** `*_spec.rb`
files (`find spec -name '*_spec.rb'` → no matches). No `bundle exec rspec`
suite exists to run.

`test/` holds five files:

- `test/drive_decibels.rb` — the main driver. **Ran live for this audit:**
  `nix develop --command xvfb-run -a ruby test/drive_decibels.rb` →
  **97 of 97 checks passed, DRIVE OK**, reproducing the task's stated gate
  exactly. This is a real improvement over the previous audit: the script now
  loads a real audio file into a real window, asserts the stack switches to
  the `player` page, asserts `stream.get_duration.positive?` and
  `stream.playing?` after autoplay, drives the real play/pause button,
  skip-forward/skip-back (asserting the timestamp actually moves), the
  `player` action group's `play-pause`/`toggle-mute` actions against the real
  stream, and the playback-rate button's real slider against the real
  stream's rate. This is a genuine playback test, not a widget built and
  exercised in isolation the way the previous report (written before this
  script existed in its current form) described.
- `test/drive_mpris_server.rb` — **not part of the 97-check run and not a
  check script at all.** It starts the app, loads a file, starts MPRIS, logs
  `mpris.started`/`bus_name`, and then idles for 60 seconds so a *separate,
  manually invoked* `gdbus call` process can be driven against it. It
  contains zero `assert`/`check` calls — read in full,
  `grep -c 'check\|assert' test/drive_mpris_server.rb` → `0`. It is a fixture
  for manual/interactive testing, not an automated test.
- `test/drive_open.rb`, `test/drive_smoke.rb` — smaller smoke drivers, not
  separately censused here.
- `test/gtk_driver.rb` — the shared harness; not a test file itself.

## The gap: MPRIS (component #15/17) has no automated check at all

`grep -ni mpris test/drive_decibels.rb test/drive_smoke.rb test/drive_open.rb
test/gtk_driver.rb` returns **zero hits**. The only file that touches MPRIS is
`test/drive_mpris_server.rb`, which (as above) makes no assertions of its own
— it is a manual-only harness that requires a human or agent to separately
run `gdbus call` against the running bus name and read the output by hand.
No CI, no `nix develop --command xvfb-run -a ruby test/drive_decibels.rb`
run, and no part of the 97-check gate ever instantiates `Mpris`, starts the
D-Bus service, or calls a single MPRIS method.

This is exactly the condition the task brief calls out: *"a component no
check exercises is unverified, not done."* `lib/mpris.rb` (460+ lines) reads
as a careful, correct port on inspection (`COMPONENT_PARITY.md`), but
"reads as correct on inspection" is not the same claim as "verified to work,"
and nothing in this repository currently closes that gap with an executed
check. The runtime gate's "17 components" figure should not be read as "17
components verified" — 16 are exercised by `drive_decibels.rb`'s 97 checks;
MPRIS is not exercised by any script that makes an assertion.

## Rules followed

- Re-ran the suite rather than trusting the stated gate: 97/97 reproduced live, matching the task brief exactly.
- Distinguished "a script touches this component" from "a script asserts something about this component" — `drive_mpris_server.rb` touches MPRIS and asserts nothing, so it does not count as coverage.
- Named the exact grep (`grep -ni mpris test/drive_decibels.rb ...` → 0 hits) so the finding can be re-run and falsified.
- Did not let the previous report's "playback is entirely unbuilt" framing carry forward uncorrected — the player/stream/waveform-generator gap it described is closed, and saying so is as much this report's job as flagging what is still open.
