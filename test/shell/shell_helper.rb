# End-to-end tests against the running Omarchy shell, through the widget's
# test mode (the dev.fazzle.mast.test IPC target in BarWidget.qml). They cover what
# the unit tests cannot: that the QML loads, opens the overlay and the
# settings screen, and sends the right events to the database.
#
# Nothing here touches the keyboard or mouse: typing is fed in over IPC, the
# windows take no keyboard focus, and "yes" unblocks nothing. The overlay does
# cover the screen while a test runs.
#
#   rake test:shell
#
# Needs the shell running and unlocked, with this checkout as the plugin and
# the widget on the bar. A shell started before the last QML change is
# restarted first, so the tests never pass against old code.

require "minitest/autorun"
require "json"
require "open3"
require "time"

module ShellTest
  ROOT = File.expand_path("../..", __dir__)
  PLUGIN = File.expand_path("~/.config/omarchy/plugins/dev.fazzle.mast")
  TARGET = "dev.fazzle.mast.test"
  DB = File.join(ENV["XDG_DATA_HOME"] || File.expand_path("~/.local/share"), "fazzledev-mast", "test.sqlite3")

  module_function

  def abort!(message) = abort("test:shell: #{message}")

  def locked? = system("omarchy-hyprland-session-locked", out: File::NULL, err: File::NULL)

  def shell_pid = `pgrep -xo quickshell`.strip.then { |pid| pid.empty? ? nil : pid }

  def shell_started_at(pid) = Time.parse(`ps -o lstart= -p #{pid}`.strip)

  def qml_changed_at
    Dir[File.join(ROOT, "**", "*.{qml,js}")].reject { |f| f.include?("/tmp/") }.map { |f| File.mtime(f) }.max
  end

  def ipc(fn, *args, target: TARGET)
    out, status = Open3.capture2e("omarchy-shell", target, fn, *args.map(&:to_s))
    raise "omarchy-shell #{target} #{fn} #{args.join(" ")}: #{out.strip}" unless status.success?
    out.strip
  end

  def reachable?
    ipc("state")
    true
  rescue RuntimeError
    false
  end

  def wait(what, timeout: 10)
    deadline = Time.now + timeout
    until (result = yield)
      raise "timed out after #{timeout}s waiting for #{what}" if Time.now > deadline
      sleep 0.1
    end
    result
  end

  def prepare!
    abort! "the screen is locked" if locked?
    abort! "#{PLUGIN} is not this checkout" unless File.exist?(PLUGIN) && File.realpath(PLUGIN) == File.realpath(ROOT)
    pid = shell_pid or abort!("the shell is not running")
    if shell_started_at(pid) < qml_changed_at
      warn "test:shell: the shell predates the QML, restarting it"
      system("omarchy", "restart", "shell", out: File::NULL, err: File::NULL)
      wait("the shell to come back", timeout: 30) { shell_pid && shell_pid != pid && reachable? }
    end
    abort! "no #{TARGET} IPC target: is the Mast widget on the bar?" unless reachable?
  end
end

ShellTest.prepare!

class ShellTest::TestCase < Minitest::Test
  include ShellTest

  # The widget has one overlay, so the tests take turns.
  def self.run_order = :sorted

  # Every test starts with no attempt open, nothing waiting to be written,
  # an empty test database and the settings the tests assume.
  DEFAULTS = {
    allowSwitching: true, showWpm: true, reasonWords: 3, coolOffSeconds: 0,
    sourceParagraphs: true, sourceBooks: true, sourceNews: true, showWeekStats: true,
  }

  # Anything the shell complains about while a test runs -- a binding that
  # cannot see what it reads, a type that will not load, a mast-db that
  # failed -- fails that test. QML keeps going after an error, so without
  # this a broken panel still passes.
  def assert_no_shell_errors(since)
    lines = `journalctl --user --since "#{since.strftime("%Y-%m-%d %H:%M:%S")}" --output cat`.lines
    complaints = lines.grep(/dev\.fazzle\.mast|mast-db:/).grep(/Error|error:|is not a type|Unable to assign|Required property/)
    assert_empty complaints.map(&:strip).uniq.first(5), "the shell complained"
  end

  def setup
    @started_at = Time.now
    ipc("stop")
    wait("writes to finish") { state["dbPending"].zero? && !state["readsPending"] }
    FileUtils.rm_f(Dir["#{DB}*"])
    settings
  end

  def teardown
    ipc("stop")
    wait("writes to finish") { state["dbPending"].zero? }
    assert_no_shell_errors(@started_at)
  end

  def settings(**overrides)
    DEFAULTS.merge(overrides).each { |key, value| assert_equal "ok", ipc("setting", key, value) }
  end

  def state = JSON.parse(ipc("state"))

  # Opens an attempt and waits for the week's numbers from the fresh
  # database, which decide which passages are hidden.
  def start(site = "youtube")
    ipc("start", site)
    wait("the attempt to be recorded") { state["dbPending"].zero? && !state["readsPending"] }
    state
  end

  def type_passage
    ipc("type", 1)
    wait("the passage to be typed", timeout: 120) { state["asking"] }
    state
  end

  # What bin/mast-db serves the history tab, once the widget has written
  # everything.
  def history
    wait("writes to finish") { state["dbPending"].zero? }
    JSON.parse(Open3.capture2(RbConfig.ruby, File.join(ROOT, "bin", "mast-db"), "-e", "test", "history").first)
  end

  def helper_status = File.executable?("/usr/local/bin/mast") ? `/usr/local/bin/mast status` : ""
end
