# bin/close-open, against a fake Hyprland: a clients list it reads and a log of
# every dispatch it makes. Nothing here touches a real session.
#
# It had no tests, which is how it went unnoticed that its reload -- a
# synthetic F5 aimed at an unfocused window -- did nothing at all while
# Hyprland answered "ok" to every dispatch.

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

class CloseOpenTest < Minitest::Test
  SCRIPT = File.expand_path("../../bin/close-open", __dir__)

  def setup
    @dir = Dir.mktmpdir("mast-close-open-test")
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
  end

  def teardown = FileUtils.rm_rf(@dir)

  # The windows Hyprland will report, and a log of what it is asked to do.
  def hyprland(*clients)
    File.write(File.join(@dir, "clients.json"), JSON.generate(clients))
    fake = <<~SH
      #!/bin/sh
      if [ "$1" = "clients" ]; then cat "#{File.join(@dir, "clients.json")}"; exit 0; fi
      echo "$*" >>"#{File.join(@dir, "dispatch.log")}"
      echo ok
    SH
    File.write(File.join(@bin, "hyprctl"), fake)
    FileUtils.chmod(0o755, File.join(@bin, "hyprctl"))
  end

  def window(klass, title) = { "class" => klass, "title" => title, "address" => "0x#{klass.sum.to_s(16)}" }

  def close_open(*sites)
    out = IO.popen({ "PATH" => "#{@bin}:#{ENV["PATH"]}" }, ["bash", SCRIPT, *sites], err: [:child, :out], &:read)
    assert $?.success?, "close-open failed: #{out}"
    out
  end

  def dispatches = File.exist?(File.join(@dir, "dispatch.log")) ? File.read(File.join(@dir, "dispatch.log")) : ""

  def test_a_web_app_window_for_the_site_is_closed
    hyprland(window("chrome-www.youtube.com__-Profile_1", "YouTube"))
    close_open("youtube")
    assert_match(/window\.close/, dispatches)
    assert_match(/address:0x/, dispatches)
  end

  def test_a_browser_tab_on_the_site_is_reported_and_left_alone
    hyprland(window("google-chrome", "wtf is jev? - YouTube - Google Chrome"))
    assert_equal ["youtube"], close_open("youtube").split("\n")
    assert_empty dispatches, "the window is named, not touched"
  end

  def test_windows_that_merely_mention_the_site_are_left_alone
    hyprland(window("google-chrome", "How YouTube ruined my attention span | Some Blog - Google Chrome"),
             window("foot", "youtube.com notes"))
    assert_empty close_open("youtube")
    assert_empty dispatches
  end

  def test_other_sites_are_not_touched
    hyprland(window("google-chrome", "r/programming - Google Chrome"),
             window("chrome-www.reddit.com__-Profile_1", "Reddit"))
    assert_empty close_open("youtube")
    assert_empty dispatches
  end

  def test_several_sites_at_once
    hyprland(window("google-chrome", "Home / X - Google Chrome"),
             window("google-chrome", "Some video - YouTube - Google Chrome"),
             window("chrome-www.tiktok.com__-Profile_1", "TikTok"))
    assert_equal %w[youtube twitter], close_open("youtube", "twitter", "tiktok").split("\n").sort.reverse
    assert_match(/window\.close/, dispatches, "TikTok's app window still closes")
  end

  def test_nothing_open_says_nothing
    hyprland(window("foot", "fazzledev@omarchy:~"))
    assert_empty close_open("youtube")
    assert_empty dispatches
  end
end
