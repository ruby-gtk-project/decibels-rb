# frozen_string_literal: true

require_relative '../main'

module Decibels
  # The gem-facing name for the application object. The port itself lives in
  # lib/main.rb, one file per upstream source, so this is only the handle
  # `require "decibels"` hands back.
  Application = App
end
