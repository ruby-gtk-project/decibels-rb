# frozen_string_literal: true

# Drives the application's open handler — the path a file manager or a command
# line argument takes into the app — by running it with a file argument.
#
#   nix develop --command xvfb-run -a ruby test/drive_open.rb [FILE…]

require_relative '../lib/main'

App.new.tap do |app|
  app.build

  GLib::Timeout.add(1200) do
    warn "windows: #{app.windows.size}"
    app.windows.each_with_index do |window, index|
      warn "window #{index}: file=#{window.file&.basename.inspect} page=#{window.stack.visible_child_name}"
    end

    app.quit
    false
  end

  ARGV.push('data/org.rubygtkproject.Decibels.desktop').then do |paths|
    app.app.run([$PROGRAM_NAME, *paths])
  end
end
