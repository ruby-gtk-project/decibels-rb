# decibels-rb — upstream component inventory

Upstream: `origin/main` (GNOME Decibels, GJS/TypeScript + blueprint).
Port: `ruby` branch, `lib/`.
Produced with the `component-identification` skill: every component is listed
with its widget types, CSS classes, signals and actions, and the set of
upstream files that define it (a `.ts` class plus its `.blp` is one component).

Upstream is GJS with blueprint, so the `.blp` files *are* the widget tree; the
`.ts` files hold the callbacks, properties and bindings. Both halves are
unioned per component below.

## State of the port

`lib/` on `ruby` now carries the window chrome, all three dialogs, two of the
three stack pages and the stylesheet. The playback half of the app — the player
page, the waveform, the transport controls and the media stream behind them —
is still unwritten.

| File | Upstream it came from | State |
|---|---|---|
| `lib/main.rb` | `src/main.ts` + `src/application.ts` | present (`App`: actions, accels, open handling, icon search path) |
| `lib/decibels/application.rb` | — | present (alias `Decibels::Application = App`) |
| `lib/window.rb` | `src/window.ts` + `data/window.blp` | partial — window, drag overlay, `empty`/`error` pages, `win.open-file`, `win.show-file`, file dialog. No `player` page, no `stream` property, no `player` action group, no `key_pressed_cb`, no title bindings, no `<Control>w` class shortcut (bound as an app accel instead) |
| `lib/drag_overlay.rb` | `src/drag-overlay.ts` + `data/drag-overlay.blp` | present |
| `lib/header_bar.rb` | `src/header.ts` + `data/header.blp` | present |
| `lib/empty_state.rb` | `src/empty.ts` + `data/empty.blp` | present |
| `lib/error_state.rb` | `src/error.ts` + `data/error.blp` | present |
| `lib/shortcuts_dialog.rb` | `data/shortcuts-dialog.blp` | present |
| `lib/about_dialog.rb` | `src/application.ts` (`show_about_dialog_cb`) | present (reads the port's own metainfo XML instead of `new_from_appdata`) |
| `lib/style.rb` | `data/style.css` | present (loaded through `Gtk::CssProvider`) |
| `lib/decibels/rb/version.rb` | — | gem version |

Still absent, in dependency order: `lib/media_stream.rb`, `lib/waveform_generator.rb`,
`lib/waveform_bar_chart.rb`, `lib/waveform_scale.rb`, `lib/playback_rate_button.rb`,
`lib/volume_button.rb`, `lib/player_state.rb`, `lib/mpris.rb`.

House shape to follow (from the pilot port `gnome-contacts-rb`): one upstream
source file becomes one flat `lib/<thing>.rb`, the application class stays at
`lib/decibels/application.rb`, each file opens with
`# frozen_string_literal: true` then `require 'adwaita'` and `require_relative`
for siblings, each class carries a comment naming the upstream file it was
ported from, and widgets are memoized methods configured in `.tap` blocks.

## Components, in the order a user meets them

### `src/main.ts` → `lib/main.rb` — entry point

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| — | — | — | — | `main(argv)` constructs `Application` and runs it |

Port shape: `exe/decibels` requires `decibels` and calls
`Decibels::Application.new.build.run`. Upstream's `main.ts` and
`application.ts` are both folded into `lib/main.rb`'s `App`, since `main.ts`
holds nothing but that one call. **Present.**

### `src/application.ts` → `lib/decibels/application.rb` — the application

Not a widget class, but it owns the app-level actions, the accelerators, the
About dialog, MPRIS and the open/activate handling.

| Facet | Value |
|---|---|
| Base | `Adw.Application` (port must use `Gtk::Application`; `Adwaita::Application` is broken in the Ruby bindings) |
| App id | `org.gnome.Decibels` upstream; port currently `org.rubygtkproject.Decibels` |
| Flags | `Gio.ApplicationFlags.HANDLES_OPEN` |
| `resource_base_path` | `/org/gnome/Decibels` |
| Actions | `app.new-window`, `app.quit`, `app.about`, `app.shortcuts` (referenced by the menu and the shortcuts dialog; **never installed in upstream source** — libadwaita 1.8 auto-loads `shortcuts-dialog.ui` from the resource base path and installs the action) |
| Accels | `app.new-window` `<Control>n`; `app.quit` `<Control>q`; `win.open-file` `<Control>o` |
| CSS class | `devel` added to the window when the app id ends in `Devel` |
| Other | `GLib.set_application_name(_("Audio Player"))`, `PULSE_PROP_application.icon_name`, `Gtk.Window.set_default_icon_name`, `notify::active-window` → hand the active window's stream to MPRIS (deferred on `notify::media-info` when the stream has not loaded a track yet), `vfunc_activate` → new window, `vfunc_open(files)` → load into the current empty window, else one new window per file, autoplay only for a single file |

**Present** in `lib/main.rb` — actions, accelerators (`app.shortcuts` bound
to `<Control>question`, `window.close` to `<Control>w` as an app accel rather
than upstream's class-level `Gtk.Shortcut`), `handles_open`, `vfunc_open`'s
single-file-into-the-empty-window rule, the stylesheet load and the icon-theme
search path. **Still missing:** the MPRIS hand-off on
`notify::active-window`, the `devel` CSS class for Devel builds, autoplay for a
single opened file, `GLib.set_application_name`, the PulseAudio icon property
and `resource_base_path`. App id is `org.rubygtkproject.Decibels`.

### `src/application.ts` (`show_about_dialog_cb`) → `lib/about_dialog.rb` — About dialog

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.AboutDialog` | 1 | — | — | built with `new_from_appdata("/org/gnome/Decibels/<app-id>.metainfo.xml", version)`, then `set_version`, `set_developers` (Angelo Verlain, David Keller), `set_artists` (kramo), `set_designers` (Allan Day), `set_translator_credits(_("translator-credits"))`; presented on the active window |

Upstream builds it inline in `application.ts`; the port extracts it to its own
file per house style. `new_from_appdata` needs the metainfo inside a
GResource, which the port has not got, so `lib/about_dialog.rb` reads
`data/<app-id>.metainfo.xml` off disk with a narrow regex reader (no REXML in
the runtime bundle) and sets name, icon, developer name, version, license,
URLs and release notes itself, plus the hand-written developer/artist/designer
credits. **Present.** Missing: `set_translator_credits(_("translator-credits"))`,
which needs gettext.

### `src/window.ts` + `data/window.blp` → `lib/window.rb` — the main window

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template root `$Gjs_Window`) | 1 | `devel` (dynamic, Devel builds only) | `close-request` (`vfunc_close_request` → `stream.reset()`, returns false) | `default-width: 650`, `default-height: 450`, `height-request: 260`, `title: _("Audio Player")` |
| `$APDragOverlay` | 1 | — | — | `content:` of the window, hosts the stack in its `[content]` slot |
| `Gtk.Stack` `stack` | 1 | — | — | three pages, switched by `show_stack_page` |
| `Gtk.StackPage` | 3 | — | — | names `empty`, `error`, `player` (not widgets; `<child>` wrappers) |
| `$APEmptyState` | 1 | — | — | page `empty` |
| `$APErrorState` `error` | 1 | — | — | page `error` |
| `$APPlayerState` `player` | 1 | — | — | page `player` |
| `Gtk.EventControllerKey` | 1 (controller) | — | `key-pressed => key_pressed_cb` | `propagation-phase: capture` |
| `Gtk.FileDialog` | 1 (type) | — | — | `modal: true`, `title: _("Open File")`, one `Gtk.FileFilter` `_("Audio files")` / `audio/*` in a `Gio.ListStore` |
| `Gtk.FileLauncher` | 1 (type) | — | — | `show_file` → `open_containing_folder` |
| `Gtk.WindowGroup` | 1 (type) | — | — | each window gets its own |

| Facet | Value |
|---|---|
| Property | `stream` (`APMediaStream`, READWRITE) |
| Actions | `win.open-file`, `win.show-file` (installed disabled; enabled once a file loads, disabled again on error) |
| Action group | `player` ← `stream.get_action_group()`, inserted on the window |
| Window shortcut | `<Control>w` → `window.close` (class-level `Gtk.Widget.add_shortcut` with a `Gtk.NamedAction`) |
| Bindings | `stream.title`/`artist` → `player.headerbar.title`/`subtitle` and `error.headerbar.title`/`subtitle` |
| Signals consumed | `stream::loaded` → show `player` page; `stream::error` → `show_error(_("File Cannot Be Played"), error)` |
| Keyboard (`key_pressed_cb`, ignored until `media_info` exists) | `space` play/pause; `Left` −10s; `Right` +10s; `=`/`+`/`KP_Equal` (with or without Ctrl) rate +0.1; `-`/`KP_Subtract` rate −0.1; `0`/`KP_0` rate = 1 |
| Error strings | `_("File Cannot Be Played")`, `_("No available audio file found")`, `_("Directories Cannot Be Played")`, `_("Please select a file.")`, `_("The selected file is not a regular file.")`, `_("No file was selected")`, `"Couldn’t read the file"` (untranslated upstream) |
| File loading | `query_info_async("standard::*", NOFOLLOW_SYMLINKS)`, branches on `REGULAR` / `DIRECTORY` / other; `Gtk.DialogError.DISMISSED` from the file dialog is swallowed |

**Partial.** `lib/window.rb` has the window, the drag overlay, the stack with
the `empty` and `error` pages, both `win.*` actions with `show-file` starting
disabled, the file dialog with its `audio/*` filter, `load_file`/`load_uri`,
`show_error` and the `Gtk::WindowGroup`. The window is *composed*, not
subclassed — `Adwaita::ApplicationWindow` instantiates but does not usefully
derive in these bindings — so the pages reach it through callbacks instead of
`get_root`. **Missing:** the `player` stack page, the `stream` property and the
`player` action group it supplies, `key_pressed_cb` (space / Left / Right /
rate keys), the `stream.title`/`artist` → headerbar title bindings,
`close-request` → `stream.reset()`, and the `devel` CSS class.

### `src/drag-overlay.ts` + `data/drag-overlay.blp` → `lib/drag_overlay.rb` — drag-and-drop overlay

Adapted upstream from Amberol. Wraps the stack and reveals a drop target hint.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APDragOverlay`) | 1 | `drag-overlay` | — | implements `Gtk.Buildable`; `vfunc_add_child` routes the `content` slot into the overlay's child |
| `Gtk.Overlay` `overlay` | 1 | — | — | its child gains/loses `blurred` while a drop hovers |
| `Gtk.Revealer` `revealer` | 1 | — | — | `can-target: false`, `transition-type: crossfade` |
| `Adw.StatusPage` | 1 | `drag-overlay-status-page` | — | `icon-name: folder-music-symbolic`, `title: _("Drop Here to Open")` |
| `Gtk.DropTarget` | 1 (controller) | — | `notify::current-drop` → reveal + blur; `drop` → `window.load_file(files[0])` | `actions: COPY`, formats `Gdk.FileList` |

Dynamic CSS: `blurred` added to / removed from the overlay child. Error path:
`_("Unable to access dropped files")` under `_("File Cannot Be Played")`.
**Present** as `lib/drag_overlay.rb`; the `[content]` Buildable slot becomes a
`content=` writer.

### `src/header.ts` + `data/header.blp` → `lib/header_bar.rb` — shared header bar and primary menu

Used by all three pages (empty, error, player).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APHeaderBar`) | 1 | — | — | properties `title`, `subtitle` (both READWRITE strings) |
| `Adw.HeaderBar` `header_bar` | 1 | — | — | — |
| `Gtk.MenuButton` | 1 | — | — | `[start]`, `icon-name: open-menu-symbolic`, `primary: true`, `tooltip-text: _("Main Menu")`, `menu-model: primary_menu` |
| `Adw.WindowTitle` | 1 | — | — | created lazily by `render_title`; cleared (`set_title_widget(null)`) when `title` is empty |

Menu model `primary_menu` — 3 sections, 5 items:

| Section | Label | Action | Notes |
|---|---|---|---|
| 1 | `_("New Window")` | `app.new-window` | |
| 1 | `_("Open…")` | `win.open-file` | |
| 2 | `_("Show in _Files")` | `win.show-file` | `hidden-when: action-disabled` |
| 3 | `_("_Keyboard Shortcuts")` | `app.shortcuts` | |
| 3 | `_("_About Audio Player")` | `app.about` | |

**Present** as `lib/header_bar.rb`; `hidden-when: action-disabled` is set with
`Gio::MenuItem#set_attribute_value`, and `render_title` builds the
`Adwaita::WindowTitle` lazily and clears `title_widget` when the title is
blank, as upstream does.

### `src/empty.ts` + `data/empty.blp` → `lib/empty_state.rb` — empty state (startup page)

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APEmptyState`) | 1 | — | — | |
| `Adw.ToolbarView` | 1 | — | — | |
| `$APHeaderBar` | 1 | — | — | `[top]`, unnamed (no title binding on this page) |
| `Adw.StatusPage` `statusPage` | 1 | — | — | `title: _("Play Audio Files")`, `description: _("Drag and drop audio files here")`, `icon-name` set in source to `<app-id>-symbolic` |
| `Gtk.Box` | 1 | — | — | vertical, spacing 12 |
| `Gtk.Button` | 1 | `pill`, `suggested-action` | — | `label: _("_Open…")`, `use-underline`, `action-name: win.open-file`, `can-shrink`, `halign: center` |

**Present** as `lib/empty_state.rb`.

### `src/error.ts` + `data/error.blp` → `lib/error_state.rb` — error state

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APErrorState`) | 1 | — | — | exposes `headerbar` as a public child for the title bindings |
| `Adw.ToolbarView` | 1 | — | — | |
| `$APHeaderBar` `headerbar` | 1 | — | — | `[top]`, bound to `stream.title`/`artist` |
| `Adw.StatusPage` `statusPage` | 1 | — | — | `icon-name: no-sound-symbolic` (custom icon), `title: _("File Cannot Be Played")`; `show_error(title, error)` overwrites title and sets the description from the error message, falling back to `_("An unknown error happened")` |
| `Gtk.Box` | 1 | — | — | vertical, spacing 12 |
| `Gtk.Button` | 1 | `pill`, `suggested-action` | — | `label: _("_Try Again…")`, `use-underline`, `action-name: win.open-file`, `can-shrink`, `halign: center` |

**Present** as `lib/error_state.rb`, including `show_error(title, error)` with
the `_("An unknown error happened")` fallback. The header bar is exposed but
not yet bound to a stream.

### `src/player.ts` + `data/player.blp` → `lib/player_state.rb` — the player page

The largest component. Upstream binds everything to `window.stream` lazily, on
`notify::stream` after `vfunc_root`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APPlayerState`) | 1 | — | — | exposes `headerbar` |
| `Adw.ToolbarView` | 1 | — | — | |
| `$APHeaderBar` `headerbar` | 1 | — | — | `[top]`, bound to `stream.title`/`artist` |
| `Adw.Clamp` | 1 | — | — | vertical, `maximum-size: 600`, `tightening-threshold: 300` |
| `Gtk.Box` | 1 | — | — | vertical, holds waveform + labels |
| `$APWaveformScale` `waveform` | 1 | — | `position-changed => waveform_position_changed_cb` → `stream.seek(value * duration)` | `vexpand`, `margin-start/end: 14` |
| `Gtk.EventControllerScroll` | 1 (controller) | — | `scroll => scroll_cb` → `stream.skip_seconds(delta)` (×10 for `Gdk.ScrollUnit.WHEEL`) | `flags: both_axes`, on the waveform |
| `Gtk.Box` `labels` | 1 | — | — | `margin-start/end: 24`, forced `Gtk.TextDirection.LTR` |
| `Gtk.Label` `timestamp_label` | 1 | `caption`, `numeric` | — | bound from `stream.timestamp`, formatted `hh:mm:ss`/`mm:ss`; forced LTR |
| `Gtk.Label` `duration_label` | 1 | `caption`, `numeric` | — | bound from `stream.duration`, same format, `hexpand`, `halign: end`; forced LTR |
| `Gtk.CenterBox` `controls` | 1 | `toolbar` | — | `[bottom]`, `margin-start/end/bottom: 9` |
| `$APPlaybackRateButton` | 1 | — | — | `[start]`, `valign: center`, `tooltip-text: _("Adjust Playback Speed")` |
| `Gtk.Box` `playback_box` | 1 | — | — | `[center]`, spacing 12, forced LTR |
| `Gtk.Button` (skip back) | 1 | `circular` | — | `action-name: player.skip-seconds`, `action-target: "-10"`, `icon-name: skip-backwards-10-symbolic`, `tooltip-text: _("Skip Back 10s")` |
| `Gtk.Button` `playback_button` | 1 | `pill` | — | `action-name: player.play-pause`, 42×42, `tooltip-text` bound from `stream.playing` → `_("Pause")` / `_("Play")` |
| `Gtk.Image` `playback_image` | 1 | — | — | `icon-size: large`, `icon-name` bound from `stream.playing` → `pause-large-symbolic` / `play-large-symbolic` |
| `Gtk.Button` `skip_forward_10_button` | 1 | `circular` | — | `action-name: player.skip-seconds`, `action-target: "10"`, `icon-name: skip-forward-10-symbolic`, `tooltip-text: _("Skip Forward 10s")` |
| `$APVolumeButton` `volume_button` | 1 | — | — | `[end]`, `valign: center`; `volume` bound bidirectionally through cubic/linear conversion |
| `Gtk.ShortcutController` | 1 (controller) | — | — | `scope: managed`, one `Gtk.Shortcut`: `<Control><Shift>leftarrow` → `action(player.skip-seconds)` with argument `10` |

Bindings to reproduce: `duration`→`duration_label`, `timestamp`→`timestamp_label`,
`volume`↔`volume_button.volume` (cubic↔linear), `playing`→image icon and button
tooltip, `timestamp`→`waveform.position` (suppressed while the waveform has
`Gtk.StateFlags.ACTIVE`), `stream.waveform_generator.peaks`→`waveform.paintable.peaks`.
Helpers: `seconds_to_string`, `micro_to_seconds`, `micro_to_string`. **Absent.**

### `src/playback-rate-button.ts` + `data/playback-rate-button.blp` → `lib/playback_rate_button.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APPlaybackRateButton`) | 1 | — | — | |
| `Gtk.MenuButton` | 1 | `flat`, `numeric` | — | |
| `Gtk.Box` | 2 | — | — | one in the button (spacing 6), one in the popover (vertical, spacing 4, margins 4) |
| `Gtk.Image` | 1 | — | — | `icon-name: speedometer-symbolic` (custom icon) |
| `Gtk.Label` `label` | 1 | — | — | `× 1.0`; bound from `stream.rate` as `× %.1f` |
| `Gtk.Popover` | 1 | — | — | |
| `Gtk.Scale` | 1 | — | `change-value => scale_change_value_cb` → `stream.rate = value` | vertical, `inverted`, `height-request: 200`, `vexpand`, marks at 0.5/1/2/3 (bottom) |
| `Gtk.Adjustment` `adjustment` | 1 (type) | — | — | lower 0.5, upper 3, value 1, step 0.5; bound to `stream.rate` with SYNC_CREATE |

`adjust_value(increase)` steps the rate by `step_increment`. Wiring happens in
`vfunc_root` on `notify::stream`. **Absent.**

### `src/volume-button.ts` + `data/volume-button.blp` → `lib/volume_button.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root `$APVolumeButton`) | 1 | — | — | properties `volume` (double 0…1, default 0.5), `muted` (boolean); `tooltip-text` from a closure |
| `Gtk.MenuButton` `menu_button` | 1 | `flat`, `numeric` | — | `direction: up`; `icon-name` from a closure |
| `Gtk.Popover` | 1 | — | — | `width-request: 250` |
| `Gtk.Box` | 1 | — | — | margins 4, spacing 4 |
| `Gtk.ToggleButton` `mute_button` | 1 | `circular`, `flat` | — | `action-name: player.toggle-mute`, accessibility label `_("Mute/Unmute")`, `icon-name` from a closure |
| `Gtk.Scale` | 1 | — | — | `hexpand`, one mark at 0.5 (bottom) |
| `Gtk.Adjustment` `adjustment` | 1 (type) | — | — | 0…1, value 0.5, step 0.2; bound bidirectionally to `volume` |

Icon logic (`menu_button_icon_cb`): muted or 0 → `audio-volume-muted-symbolic`;
1 → `…-high-symbolic`; >0.5 → `…-medium-symbolic`; else `…-low-symbolic`.
`mute_button_icon_cb`: muted → `…-muted-symbolic`, else `…-high-symbolic`.
`tooltip_text_cb`: `_("Muted")`, `_("Full Volume")`, else `C_("volume percentage", "%d %%")`.
These are blueprint `bind $cb(...)` closures with no Ruby-bindings equivalent;
the port reimplements them as `notify::` handlers. **Absent.**

### `src/waveform-scale.ts` → `lib/waveform_scale.rb` — the waveform seek bar

A hand-drawn `Gtk.Widget` subclass; no `.blp`.

| Facet | Value |
|---|---|
| Base | `Gtk.Widget`, `CssName: "waveform-scale"`, `accessible_role: SLIDER` |
| Properties | `position` (float 0…1), `paintable` (`APWaveformBarChart`, readable), `height-mul` (float 0…1, animation target) |
| Signals emitted | `position-changed` (double) |
| Controllers | `Gtk.GestureClick` (`pressed` → set position, emit), `Gtk.GestureDrag` (`drag-begin` claims the sequence, `drag-update` → set position, emit) |
| Animation | `Adw.TimedAnimation` 0→1 over 250 ms, `Adw.PropertyAnimationTarget` on `height-mul`, easing `EASE_IN_QUAD`, played on `notify::peaks` |
| Drawing | `vfunc_snapshot`: caches the bar chart to a paintable, pushes a `Gsk.MaskMode.ALPHA` mask, paints played part in the accent colour and the rest in the dimmed current colour, then a 2 px slider line |
| Colours | `Adw.StyleManager` accent colour via `Adw.accent_color_to_standalone_rgba`; current colour alpha × 0.9 (high contrast) or × 0.55; recomputed in `vfunc_css_changed` |
| Other vfuncs | `vfunc_size_allocate` invalidates the cache; accessibility `VALUE_MIN`/`VALUE_MAX`/`VALUE_NOW` updated via `Gtk.AccessibleProperty` |

**Absent.**

### `src/waveform-bar-chart.ts` → `lib/waveform_bar_chart.rb` — the bar chart paintable

| Facet | Value |
|---|---|
| Base | `GObject.Object` implementing `Gdk.Paintable` |
| Properties | `color` (boxed `Gdk.RGBA`), `bar-width` (float), `bar-padding` (float), `peaks` (boxed array), `mipmap-bias` (float) |
| Signals consumed by the scale | `invalidate-contents`, `notify::peaks` |
| Interface vfuncs | `vfunc_snapshot`, `vfunc_get_intrinsic_width`/`_height`/`_aspect_ratio` |

**Absent.**

### `src/waveform-generator.ts` → `lib/waveform_generator.rb` — peak extraction

| Facet | Value |
|---|---|
| Base | `GObject.Object` |
| Property | `peaks` (boxed array of floats) |
| Behaviour | `generate_peaks_async(uri)` runs a GStreamer `Gst.Bin` pipeline with a bus watch, collecting level peaks |

Not a widget, but the waveform is empty without it. **Absent.**

### `src/stream.ts` → `lib/media_stream.rb` (+ `lib/play_signal_adapter.rb`) — the playback model

| Facet | Value |
|---|---|
| Classes | `APPlaySignalAdapter` (`GObject.Object`, wraps `GstPlay` bus messages as GObject signals) and `APMediaStream` (`Gtk.MediaStream` subclass) |
| Properties | `buffering`, `media_info`, `file`, `tags`, `title`, `artist`, `rate` (0.5…3, default 1) |
| Signals | `error` (`GLib.Error`), `loaded` |
| Action group (`player`, inserted on the window) | `player.play`, `player.pause`, `player.play-pause`, `player.skip-seconds` (parameter `i`), `player.toggle-mute` (a `Gio.PropertyAction` on `muted`) |
| Helpers | `get_linear_volume` / `get_cubic_volume` via `GstAudio.stream_volume_convert_volume`, `get_safe_duration` |
| Discovery | `GstPbUtils.Discoverer`; error strings `_("File uses a format that cannot be played. Additional media codecs may be required.")`, `_("An error happened while trying to get information about the file. Please try again.")`, `_("File uses an invalid URI")`, `_("Reading the file’s information timed out. Please try again.")`, `_("The selected file doesn’t contain any audio")`, `_("Unknown File")` |

Not a widget, but it owns the `player.*` actions every control in the player
page targets, so no player control works without it. **Absent.**

### `src/mpris.ts` → `lib/mpris.rb` — MPRIS D-Bus integration

| Facet | Value |
|---|---|
| Classes | `DBusInterface` (generic introspection/properties/method dispatch helper) and `MPRIS` |
| Interfaces | `org.freedesktop.DBus.Introspectable`, `org.freedesktop.DBus.Properties`, `org.mpris.MediaPlayer2`, `org.mpris.MediaPlayer2.Player` |
| Behaviour | `switch_stream(stream)` / `start()`, metadata (`mpris:trackid`, `mpris:length`, `xesam:*`), `Raise` brings the window to the front, emits `Seeked` and `PropertiesChanged` |

Not a widget; it is why the app appears in the shell's media controls, and the
`Raise` method is a user-facing entry point into the window. **Absent.**

### `data/shortcuts-dialog.blp` → `lib/shortcuts_dialog.rb` — keyboard shortcuts dialog

A standalone blueprint object with no backing source file.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ShortcutsDialog` `shortcuts_dialog` | 1 | — | — | root; no source file loads it, so libadwaita 1.8's automatic lookup is what presents it for `app.shortcuts` |
| `Adw.ShortcutsSection` | 3 | — | — | `C_("shortcut window", "General")`, `…"Player"`, `…"Playback Rate"` |
| `Adw.ShortcutsItem` | 10 | — | — | see below |

| Section | Item | Accelerator / action |
|---|---|---|
| General | Show Shortcuts | `action-name: app.shortcuts` |
| General | New Window | `action-name: app.new-window` |
| General | Quit | `action-name: app.quit` |
| Player | Open File | `action-name: win.open-file` |
| Player | Pause/Play | `space` |
| Player | Go Back 10 Seconds | `Left` |
| Player | Go Forward 10 Seconds | `Right` |
| Playback Rate | Increase Playback Rate | `<Ctrl>plus plus` |
| Playback Rate | Decrease Playback Rate | `<Ctrl>minus minus` |
| Playback Rate | Reset Playback Rate | `<Ctrl>0 0` |

**Present** as `lib/shortcuts_dialog.rb`. The `adwaita` gem does expose
`ShortcutsDialog`, `ShortcutsSection` and `ShortcutsItem`; `ShortcutsItem.new`
takes `(title, accelerator)` positionally, and items that name an action are
built with an empty accelerator and get `action_name=` afterwards. `app.shortcuts`
is installed explicitly, since nothing upstream installs it.

### `data/style.css` → `lib/style.rb` — stylesheet

Three classes, all applied from the code above:

| Class | Declaration | Applied by |
|---|---|---|
| `drag-overlay-status-page` | accent background mix, accent fg, 32 px padding | `data/drag-overlay.blp` |
| `blurred` | `filter: blur(6px)` | `src/drag-overlay.ts`, dynamically |
| `drag-overlay` | `box-shadow: none` | `data/drag-overlay.blp` |

**Present** as `lib/style.rb`: all three rules inline in the class, pushed onto
the default display with `Gtk::StyleContext.add_provider_for_display` at
`startup`.

## Non-widget parity surfaces

| Surface | Upstream | State of the port |
|---|---|---|
| Custom icons | `data/icons/scalable/actions/`: `no-sound-symbolic`, `pause-large-symbolic`, `play-large-symbolic`, `skip-backwards-10-symbolic`, `skip-forward-10-symbolic`, `speedometer-symbolic` | **present** — all six under `data/icons/hicolor/scalable/actions/`, reached through `Gtk::IconTheme#add_search_path` at startup instead of a GResource |
| App icons | `org.gnome.Decibels.svg`, `-symbolic.svg`, `.Devel.svg` | **present** for the port's own id: `data/icons/hicolor/scalable/apps/org.rubygtkproject.Decibels.svg` and `.../symbolic/apps/org.rubygtkproject.Decibels-symbolic.svg`, plus an `index.theme`. No `.Devel` variant, so there is no Devel build and no `devel` CSS class |
| Desktop entry | `org.gnome.Decibels.desktop.in.in` — `Name=Audio Player`, keywords, `DBusActivatable`, `X-SingleMainWindow`, 24 audio MIME types | **present** as `data/org.rubygtkproject.Decibels.desktop` |
| AppStream metainfo | `org.gnome.Decibels.metainfo.xml.in.in` | **present** as `data/org.rubygtkproject.Decibels.metainfo.xml`; also the data source `lib/about_dialog.rb` reads |
| D-Bus service file | `org.gnome.Decibels.service.in` | **present** as `data/org.rubygtkproject.Decibels.service` |
| GSettings schema | none upstream | n/a — there are no preferences and no preferences dialog in this app |
| Translations | `po/` with 57 languages, `po/POTFILES.in` listing 10 `.blp`/data files and 7 `.ts` files; `_()` and `C_()` throughout; `C_("shortcut window", …)` and `C_("volume percentage", "%d %%")` contexts | **absent** — no `po/`, no gettext wiring, every string a bare Ruby literal. This is the one parity surface that has not been started |

## Blockers and open questions

Resolved since the first survey:

- `Adwaita::ShortcutsDialog`, `ShortcutsSection` and `ShortcutsItem` all exist in the `adwaita` gem (`ShortcutsItem.new` is positional).
- `Adwaita::ApplicationWindow` can be *instantiated* but not usefully subclassed, so `lib/window.rb` composes it and hands the pages callbacks. Every page class does subclass `Adwaita::Bin` successfully.
- The About dialog works without appdata in a GResource by reading the shipped metainfo XML directly.
- The stylesheet works through `Gtk::CssProvider#load_from_string` plus `Gtk::StyleContext.add_provider_for_display`.

Still open, all of them in the unported playback half:

1. **GStreamer bindings.** `src/stream.ts` and `src/waveform-generator.ts` need `Gst`, `GstPlay`, `GstPbUtils` and `GstAudio`. Confirm what the fork's `nix develop` shell provides before planning the player; this gates `lib/media_stream.rb`, `lib/waveform_generator.rb`, `lib/player_state.rb` and both popover buttons, since every control targets a `player.*` action the stream installs.
2. **`Gtk::MediaStream` subclassing.** `APMediaStream` subclasses `Gtk.MediaStream` and overrides its vfuncs. Ruby-bindings support for overriding GObject vfuncs on a GTK class needs verifying before `lib/media_stream.rb` is designed.
3. **`Gdk::Paintable` implementation.** `APWaveformBarChart` implements a GInterface and overrides four of its vfuncs. Implementing GInterfaces from Ruby is the least certain part of this port.
4. **Custom-drawn widget.** `APWaveformScale` overrides `vfunc_snapshot`, `vfunc_size_allocate` and `vfunc_css_changed`, and uses `Gsk` mask nodes and `Graphene`. If `Gsk`/snapshot is not reachable from Ruby, the waveform needs a Cairo `Gtk::DrawingArea` design instead, which changes the component's shape.
5. **Blueprint closures.** `data/volume-button.blp` computes `icon-name` and `tooltip-text` with `bind $cb(...) as <string>` expressions. There is no declarative equivalent in the port; these become `notify::` handlers, and the inventory above records the logic so nothing is lost.
6. **MPRIS over D-Bus from Ruby.** `src/mpris.ts` hand-rolls introspection XML and a method dispatcher. Confirm `Gio::DBusNodeInfo` and `register_object` are usable from the Ruby bindings.
7. **Gettext.** 57 catalogues and three message contexts upstream, nothing in the port. Decide whether the port adopts `gettext` (and a `po/` of its own) or accepts untranslated strings as a documented parity gap, before the remaining files add more literals.
8. **Keyboard parity depends on the player.** `key_pressed_cb`, the `<Control><Shift>leftarrow` managed `Gtk::ShortcutController` and seven of the ten shortcuts-dialog items all act on the stream, so the shortcuts dialog currently lists shortcuts that do nothing.
