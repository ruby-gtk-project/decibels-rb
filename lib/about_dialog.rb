# frozen_string_literal: true

require 'adwaita'

# AboutDialog is the application's About window.
#
# Ported from upstream's Application.show_about_dialog_cb in src/application.ts,
# which calls Adw.AboutDialog.new_from_appdata on the metainfo file inside its
# GResource bundle and then fills in the credits by hand. This port has no
# resource bundle, so the appdata is read from the installed
# data/<app-id>.metainfo.xml and the fields new_from_appdata would have
# populated are set from it.
#
# The reader below is deliberately narrow: it pulls named elements out of the
# one appstream file this port ships, which is why it needs no XML parser —
# Ruby 3.4 unbundled REXML and the runtime bundle carries only the GTK gems.
class AboutDialog < Adwaita::AboutDialog
  DEVELOPERS = [
    'Angelo Verlain https://vixalien.com',
    'David Keller https://gitlab.com/BlobCodes',
  ].freeze

  ARTISTS = ['kramo https://kramo.page'].freeze

  DESIGNERS = ['Allan Day'].freeze

  # project_license values that map onto a Gtk.License.
  LICENSES = {
    'GPL-3.0'          => :gpl_3_0,
    'GPL-3.0-or-later' => :gpl_3_0,
    'GPL-2.0'          => :gpl_2_0,
    'LGPL-3.0'         => :lgpl_3_0,
    'LGPL-2.1'         => :lgpl_2_1,
    'MIT'              => :mit_x11,
    'Apache-2.0'       => :apache_2_0,
  }.freeze

  # The <url type="…"> values new_from_appdata reads, and the dialog property
  # each one lands in.
  URLS = {
    'homepage'   => :website=,
    'bugtracker' => :issue_url=,
    'help'       => :support_url=,
  }.freeze

  ENTITIES = {
    '&lt;'   => '<',
    '&gt;'   => '>',
    '&quot;' => '"',
    '&apos;' => "'",
    '&amp;'  => '&',
  }.freeze

  def initialize(app_id, version)
    super()
    @app_id = app_id
    @version = version
  end

  def build
    tap do |dialog|
      dialog.application_name = element('name')
      dialog.application_icon = @app_id
      dialog.developer_name = appdata_developer
      dialog.version = @version
      dialog.license_type = LICENSES.fetch(element('project_license'), :unknown)
      dialog.developers = DEVELOPERS
      dialog.artists = ARTISTS
      dialog.designers = DESIGNERS

      urls.each { |setter, url| dialog.public_send(setter, url) }

      release.then do |version, notes|
        if version
          dialog.release_notes_version = version
          dialog.release_notes = notes
        end
      end
    end
  end

  def appdata_path
    @appdata_path ||= File.expand_path("../data/#{@app_id}.metainfo.xml", __dir__)
  end

  def appdata = @appdata ||= File.read(appdata_path)

  private

    def element(name)
      appdata[%r{<#{name}>(.*?)</#{name}>}m, 1].then do |value|
        unescape(value.to_s.strip)
      end
    end

    def appdata_developer
      appdata[%r{<developer[^>]*>.*?<name>(.*?)</name>}m, 1].then do |value|
        unescape(value.to_s.strip)
      end
    end

    def urls
      URLS.filter_map do |type, setter|
        appdata[%r{<url type="#{type}">(.*?)</url>}, 1].then do |url|
          if url
            [setter, unescape(url.strip)]
          end
        end
      end
    end

    # The newest release — the first one in the file — as its version and the
    # appstream markup of its notes, which is what the dialog renders.
    def release
      @release ||= appdata.match(%r{<release version="([^"]+)".*?</release>}m).then do |found|
        if found
          [found[1], found[0][%r{<description[^>]*>(.*?)</description>}m, 1].to_s.strip]
        else
          []
        end
      end
    end

    def unescape(value)
      value.gsub(/&(?:lt|gt|quot|apos|amp);/) { |entity| ENTITIES.fetch(entity) }
    end
end
