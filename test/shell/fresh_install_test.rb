require_relative "shell_helper"

# What a fresh install looks like: the plugin is on the bar but the root
# helper, which does the actual blocking, has not been installed yet.
#
# The widget used to hide itself entirely here, so `omarchy plugin add` looked
# like it had done nothing at all.
class FreshInstallTest < ShellTest::TestCase
  MISSING = "/nonexistent/mast"

  def with_no_helper
    ipc("helper", MISSING)
    wait("the widget to notice") { state["helperMissing"] ? state : nil }
  end

  # The real helper comes back when the test ends, not when this method
  # returns -- an ensure here would put it back before the test looked.
  def teardown
    ipc("helper", "real")
    super
  end

  def test_the_bar_still_shows_something_without_a_helper
    s = with_no_helper
    assert s["barVisible"], "the icon stays, so the plugin does not look like it failed to install"
    assert_equal "\u{F1AEF}", s["barGlyph"], "the boat is going down: nothing is blocked"
  end

  def test_the_panel_says_what_is_missing_and_how_to_fix_it
    s = with_no_helper
    assert_empty JSON.parse(ipc("panel"))["rows"], "there are no sites to show without the helper"
    assert_match %r{\Asudo bash /.*/system/install\.sh\z}, s["installCommand"]
  end

  def test_the_install_command_can_be_copied
    s = with_no_helper
    copied = ipc("copyInstall")
    assert_equal s["installCommand"], copied
    # wl-copy runs detached, so give the clipboard a moment.
    pasted = wait("the clipboard") do
      text = `wl-paste --no-newline 2>/dev/null`
      text == copied ? text : nil
    end
    assert_equal copied, pasted
  end

  # The settings row follows the helper: offering to remove something that is
  # not there read as nonsense on a fresh install.
  def test_the_settings_row_offers_the_install_when_there_is_no_helper
    with_no_helper
    row = JSON.parse(ipc("settingRow", "helper"))
    assert_equal "Install Mast's helper", row["label"]
    assert_match %r{system/install\.sh\z}, row["command"]
  end

  # Removing Mast is three things, and the helper is only the first.
  def test_the_settings_row_offers_the_whole_uninstall_once_it_is_there
    skip "the root helper is not installed" if helper_status.empty?
    row = JSON.parse(ipc("settingRow", "helper"))
    assert_equal "Remove Mast completely", row["label"]
    lines = row["command"].lines.map(&:strip)
    assert_equal 3, lines.length, "the helper, the widget, the record"
    assert_match %r{\Asudo bash /.*/system/uninstall\.sh}, lines[0]
    assert_match(/\Aomarchy plugin remove dev\.fazzle\.mast/, lines[1])
    assert_match %r{\Arm -rf .*fazzledev-mast}, lines[2]
  end

  # Either way it is copied, not run: a button that removed the helper would
  # lift every block in one click.
  def test_the_uninstall_command_can_be_copied
    copied = ipc("copyUninstall")
    assert_match %r{\Asudo bash /.*/system/uninstall\.sh\z}, copied
    pasted = wait("the clipboard") do
      text = `wl-paste --no-newline 2>/dev/null`
      text == copied ? text : nil
    end
    assert_equal copied, pasted
  end

  def test_the_helper_coming_back_restores_the_rows
    skip "the root helper is not installed" if helper_status.empty?
    with_no_helper
    ipc("helper", "real")
    wait("the sites to come back") { state["helperMissing"] ? nil : true }
    refute_empty JSON.parse(ipc("panel"))["rows"]
  end
end
