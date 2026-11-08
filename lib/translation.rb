# frozen_string_literal: true

# Translation helpers.
#
# Upstream (src/*.ts, data/*.blp) wraps every user-facing string in
# gettext's `_()`, and shortcut-window titles in the context-qualified
# `C_("shortcut window", ...)`. There is no bundled gettext wiring for a
# Ruby GTK4 app the way GJS gets it for free, so this module wraps
# ruby-gettext directly: `_()` is plain gettext, `p_()` is
# msgctxt-qualified gettext (pgettext) — the only two entry points
# upstream's strings actually use; decibels has no plural strings to port.
# `p_` rather than upstream's own `C_` spelling is ruby-gettext's own
# `rxgettext` extractor's hardcoded msgctxt keyword (alongside `pgettext`
# itself) — a string behind any other method name is invisible to it, so
# po/decibels.pot would silently stop covering the shortcut-window titles
# and the volume tooltip's "%d %%" the moment a name it doesn't recognize
# got used instead.
#
# `include Translation` pulls in both: the instance methods `_`/`p_` for
# ordinary method bodies, and (via `.included`) the same two as singleton
# methods on the class itself, so a frozen class-body constant such as
# `TITLE = _('Audio Player')` — evaluated while `self` is the class, not
# an instance — resolves the same way. That only translates correctly
# because `Translation.bind_text_domain` runs (from lib/main.rb) before
# any of those constants are loaded; the locale is fixed for the process's
# whole lifetime anyway, so there is no later point where it would matter.
module Translation
  GETTEXT_PACKAGE = 'decibels'

  # The checkout's own po/ directory: this is LOCALEDIR for a port that
  # runs straight from its source tree rather than an installed one.
  LOCALEDIR = File.expand_path('../po', __dir__)

  def self.included(base) = base.extend(self)

  class << self
    def bind_text_domain
      @bound = catalogue? && bind!
    end

    def bound? = @bound == true

    def backend
      @backend ||= begin
        require 'gettext'
        Object.new.tap { |obj| obj.singleton_class.include(GetText) }
      end
    end

    private

      def bind!
        backend.bindtextdomain(GETTEXT_PACKAGE, path: LOCALEDIR)
        true
      rescue LoadError
        false
      end

      # A catalogue directory with at least one compiled .mo file in it.
      # Without one there is nothing for the backend to look up, and
      # loading the gem would only cost startup time.
      def catalogue?
        Dir.exist?(LOCALEDIR) && !Dir.glob(File.join(LOCALEDIR, '**', "#{GETTEXT_PACKAGE}.mo")).empty?
      end
  end

  def _(msgid) = Translation.bound? ? Translation.backend.gettext(msgid) : msgid

  def p_(context, msgid) = Translation.bound? ? Translation.backend.pgettext(context, msgid) : msgid
end
