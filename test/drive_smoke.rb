# frozen_string_literal: true

# Drives the window, both stack pages and both dialogs under a virtual
# display, so the binding calls behind them are exercised without a user.
#
#   nix develop --command xvfb-run -a ruby test/drive_smoke.rb

require_relative '../lib/main'

App.new.tap do |app|
  app.build

  GLib::Timeout.add(800) do
    app.windows.first.tap do |window|
      warn "window: #{window.window.class}, page: #{window.stack.visible_child_name}"
      window.load_file(Gio::File.new_for_path(Dir.pwd))
      warn "after directory: #{window.stack.visible_child_name}"
      window.load_file(Gio::File.new_for_path('/definitely/missing.mp3'))
      warn "after missing: #{window.stack.visible_child_name}"
      window.load_file(Gio::File.new_for_path(File.expand_path('data/org.rubygtkproject.Decibels.desktop')))
      warn "after regular file: show-file enabled=#{window.show_file_action.enabled?}"
      window.stack.visible_child_name = 'empty'
      window.drag_overlay.revealer.reveal_child = true
    end

    Gtk::IconTheme.get_for_display(Gdk::Display.default).tap do |theme|
      %w[no-sound-symbolic play-large-symbolic pause-large-symbolic speedometer-symbolic
         skip-backwards-10-symbolic skip-forward-10-symbolic
         org.rubygtkproject.Decibels-symbolic
].each do |icon|
        warn "icon #{icon}: #{theme.has_icon?(icon)}"
      end
    end

    AboutDialog.new(App::APP_ID, App::VERSION).build.tap do |dialog|
      warn "about: #{dialog.application_name.inspect} by #{dialog.developer_name.inspect}"
      warn "about: license=#{dialog.license_type} website=#{dialog.website.inspect}"
      warn "about: issue_url=#{dialog.issue_url.inspect} notes_version=#{dialog.release_notes_version.inspect}"
      warn "about: notes=#{dialog.release_notes.to_s[0, 60].inspect}"
    end

    app.windows.first.empty_state.header_bar.tap do |bar|
      bar.title = 'Example.mp3'
      warn "header title widget: #{bar.header_bar.title_widget.class}"
      warn "menu items: #{bar.primary_menu.n_items}"
    end

    app.show_about_dialog
    warn 'about dialog presented'
    app.show_shortcuts_dialog
    warn 'shortcuts dialog presented'
    app.present_new_window
    warn "windows: #{app.windows.size}"

    GLib::Timeout.add(800) do
      app.quit
      false
    end

    false
  end

  app.app.run([])
end
