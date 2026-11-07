# frozen_string_literal: true

# Starts the app, loads a file, brings MPRIS up and then just idles so a
# separate `gdbus call` (run from another process, so this process's own
# main loop stays free to service it) can be driven against it.
#
#   nix develop --command xvfb-run -a ruby test/drive_mpris_server.rb /path/to/file.wav

require_relative '../lib/main'

file_path = ARGV.fetch(0, '/tmp/test.wav')

App.new.tap do |app|
  app.build

  GLib::Timeout.add(500) do
    window = app.windows.first
    window.load_file(Gio::File.new_for_path(file_path))
    warn "window: #{window.window.class}"
    false
  end

  GLib::Timeout.add(2000) do
    warn "mpris started: #{app.mpris.started}, bus_name: #{app.mpris.bus_name}"
    false
  end

  GLib::Timeout.add(60_000) do
    app.quit
    false
  end

  app.app.run([])
end
