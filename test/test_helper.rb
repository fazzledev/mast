# Tests run in the test environment, with data and cache directories of their
# own that are thrown away afterwards, and a fresh database for every test.
#
# Minitest and rake are bundled gems, not part of the standard library, so
# these run on a Ruby that has them (mise's does; Arch's system Ruby does
# not). The plugin itself needs neither.

require "minitest/autorun"
require "tmpdir"

ENV["MAST_ENV"] = "test"
TEST_HOME = Dir.mktmpdir("mast-test")
ENV["XDG_DATA_HOME"] = File.join(TEST_HOME, "data")
ENV["XDG_CACHE_HOME"] = File.join(TEST_HOME, "cache")
Minitest.after_run { FileUtils.rm_rf(TEST_HOME) }

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "mast"
require "mast/cli"
require "mast/passages"

class Mast::TestCase < Minitest::Test
  def setup
    FileUtils.rm_f(Dir["#{Mast.database_path}*"])
    Mast.reset_db!
  end

  # Plays events through the controller the way the widget sends them; `at`
  # is in seconds here, for readability.
  def event(type, at: nil, **fields)
    params = fields.transform_keys(&:to_s).merge("type" => type)
    params["at"] = (at * 1000).round if at
    Mast::EventsController.dispatch(params)
  end

  # A whole attempt: one passage, typed out, then the given outcome.
  def attempt(id, outcome:, site: "youtube", at: Time.now.to_f - 600, reason: nil, text: "Passage #{id}")
    event("start", attempt: id, site: site, label: site.capitalize, at: at)
    event("passage", attempt: id, seq: 0, text: text, source: "", url: "", at: at + 1)
    unless outcome == "walked_away"
      event("typed", attempt: id, seq: 0, chars: 900, typing_ms: 240_000, wpm: 45, peak_wpm: 60, typos: 2, at: at + 241)
    end
    event("end", attempt: id, outcome: outcome, reason: reason, at: at + 260)
  end
end
