# frozen_string_literal: true

require 'adwaita'

# Style installs the application stylesheet.
#
# Ported from upstream's data/style.css. Upstream ships that file inside its
# GResource bundle and lets Adw.Application load it from the resource base
# path; this port has no resource bundle, so the rules live here and go onto
# the default display through a Gtk::CssProvider.
class Style
  CSS = <<~CSS
    .drag-overlay-status-page {
      background-color: color-mix(in srgb, var(--accent-bg-color), transparent);
      color: var(--accent-fg-color);
      padding: 32px;
    }

    .blurred {
      filter: blur(6px);
    }

    .drag-overlay {
      box-shadow: none;
    }
  CSS

  def load
    tap do
      Gtk::StyleContext.add_provider_for_display(
        Gdk::Display.default,
        provider,
        Gtk::StyleProvider::PRIORITY_APPLICATION,
      )
    end
  end

  def provider
    @provider ||= Gtk::CssProvider.new.tap { |css| css.load_from_string(CSS) }
  end
end
