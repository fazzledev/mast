# system/mast, the root helper that does the actual blocking, run against a
# temporary prefix instead of /etc and /var: MAST_PREFIX. systemd is a pair of
# fakes on PATH that write down what they were asked to do, so the timers can
# be checked without arming any.
#
# What this cannot cover: pkexec and the polkit rule, and whether a browser
# really stops. Those need root and a desktop.

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

class HelperTest < Minitest::Test
  HELPER = File.expand_path("../../system/mast", __dir__)
  # What a hosts file has in it besides Mast's sections, and must keep.
  ORIGINAL_HOSTS = "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 omarchy\n"

  def setup
    @prefix = Dir.mktmpdir("mast-system-test")
    FileUtils.mkdir_p(File.join(@prefix, "etc"))
    File.write(hosts_path, ORIGINAL_HOSTS)
    fake_systemd
  end

  def teardown = FileUtils.rm_rf(@prefix)

  # ------------------------------------------------------------- the fakes

  def fake_systemd
    @bin = File.join(@prefix, "fakebin")
    FileUtils.mkdir_p(@bin)
    %w[systemctl systemd-run resolvectl omarchy-shell].each do |name|
      path = File.join(@bin, name)
      File.write(path, "#!/bin/sh\necho \"#{name} $*\" >>\"$MAST_PREFIX/systemd.log\"\nexit 0\n")
      FileUtils.chmod(0o755, path)
    end
    # runuser needs root, but it must still run what it is handed -- otherwise
    # whatever the command does, or fails to do, never shows here.
    runuser = <<~SH
      #!/bin/sh
      echo "runuser $*" >>"$MAST_PREFIX/systemd.log"
      shift 3
      exec "$@"
    SH
    File.write(File.join(@bin, "runuser"), runuser)
    FileUtils.chmod(0o755, File.join(@bin, "runuser"))
  end

  def systemd_log = File.exist?(log_path) ? File.read(log_path) : ""
  def log_path = File.join(@prefix, "systemd.log")

  # The install asks which sites to block with `gum choose`; this answers.
  def fake_gum(*choices)
    File.write(File.join(@bin, "gum"), "#!/bin/sh\necho \"#{choices.join("\n")}\"\nexit 0\n")
    FileUtils.chmod(0o755, File.join(@bin, "gum"))
  end

  # ------------------------------------------------------------ the helper

  def mast(*args)
    env = { "MAST_PREFIX" => @prefix, "MAST_BIN" => HELPER, "PATH" => "#{@bin}:#{ENV["PATH"]}" }
    out = IO.popen(env, ["bash", HELPER, *args], err: [:child, :out], &:read)
    [out, $?.success?]
  end

  def run!(*args)
    out, ok = mast(*args)
    assert ok, "mast #{args.join(" ")} failed: #{out}"
    out
  end

  def refute_run(*args)
    out, ok = mast(*args)
    refute ok, "mast #{args.join(" ")} should have failed: #{out}"
    out
  end

  # --------------------------------------------------------------- the files

  def hosts_path = File.join(@prefix, "etc", "hosts")
  def hosts = File.read(hosts_path)
  def policy_path = File.join(@prefix, "etc", "chromium", "policies", "managed", "mast.json")
  def chrome_policy_path = File.join(@prefix, "etc", "opt", "chrome", "policies", "managed", "mast.json")
  def blocklist = JSON.parse(File.read(policy_path)).fetch("URLBlocklist")
  def until_path(site) = File.join(@prefix, "var", "lib", "mast", "#{site}.until")
  def relock_at(site) = File.read(until_path(site)).to_i

  def status = run!("status").lines.map { |l| l.chomp.split("\t") }
  def blocked_sites = status.select { |f| f[2] == "1" }.map(&:first)

  # ------------------------------------------------------------------ status

  def test_status_lists_every_site_it_knows
    names = status.map(&:first)
    assert_includes names, "youtube"
    assert_equal names.uniq, names
    assert(status.all? { |f| f.length == 4 }, "every line is name, label, blocked, relock")
    assert_equal [], blocked_sites
  end

  # --------------------------------------------------------------------- on

  def test_blocking_a_site_writes_hosts_and_the_browser_policy
    run!("on", "youtube")
    assert_includes hosts, "# >>> mast:youtube >>>"
    assert_includes hosts, "0.0.0.0 www.youtube.com"
    assert_includes hosts, ":: www.youtube.com"
    assert_includes hosts, "# <<< mast:youtube <<<"
    assert_equal ["youtube"], blocked_sites
    assert_includes blocklist, "youtube.com"
    assert File.exist?(chrome_policy_path), "Chrome gets the same policy as Chromium"
  end

  def test_blocking_leaves_the_rest_of_the_hosts_file_alone
    run!("on", "youtube")
    run!("on", "reddit")
    ORIGINAL_HOSTS.lines.each { |line| assert_includes hosts, line }
    run!("off", "youtube")
    run!("off", "reddit")
    assert_equal ORIGINAL_HOSTS, hosts
  end

  def test_blocking_twice_changes_nothing
    run!("on", "youtube")
    once = hosts
    run!("on", "youtube")
    assert_equal once, hosts
    assert_equal 1, hosts.scan("# >>> mast:youtube >>>").length
  end

  def test_a_hosts_file_without_a_final_newline_is_not_mangled
    File.write(hosts_path, "127.0.0.1 localhost")
    run!("on", "youtube")
    assert_equal "127.0.0.1 localhost", hosts.lines.first.chomp
    assert_includes hosts, "\n# >>> mast:youtube >>>"
    assert_equal ["youtube"], blocked_sites
  end

  def test_all_blocks_everything_it_knows
    run!("on", "all")
    assert_equal status.map(&:first), blocked_sites
    assert_includes blocklist, "reddit.com"
  end

  def test_an_unknown_site_is_refused
    assert_match(/unknown site/, refute_run("on", "myspace"))
    assert_match(/name a site/, refute_run("on"))
    assert_equal ORIGINAL_HOSTS, hosts
  end

  # -------------------------------------------------------------------- off

  def test_unblocking_arms_a_relock_and_says_when
    run!("on", "youtube")
    before = Time.now.to_i
    run!("off", "youtube", "5")
    assert_equal [], blocked_sites
    refute File.exist?(policy_path), "with nothing blocked there is no policy to keep"
    assert_in_delta before + 300, relock_at("youtube"), 5
    assert_match(/systemd-run .*--on-active=300s/, systemd_log)
    assert_match(/#{Regexp.escape(HELPER)} on youtube/, systemd_log)
    assert_equal relock_at("youtube").to_s, status.find { |f| f[0] == "youtube" }[3]
  end

  def test_unblocking_without_a_length_uses_the_default
    run!("on", "youtube")
    before = Time.now.to_i
    run!("off", "youtube")
    assert_in_delta before + 15 * 60, relock_at("youtube"), 5
  end

  def test_an_unblock_cannot_outlast_the_cap
    run!("on", "youtube")
    assert_match(/minutes must be 1-60/, refute_run("off", "youtube", "90"))
    assert_match(/minutes must be 1-60/, refute_run("off", "youtube", "0"))
    assert_match(/minutes must be 1-60/, refute_run("off", "youtube", "abc"))
    assert_equal ["youtube"], blocked_sites, "a refused unblock leaves the block alone"
  end

  def test_unblocking_one_site_leaves_the_others_blocked
    run!("on", "all")
    run!("off", "youtube", "5")
    refute_includes blocked_sites, "youtube"
    assert_includes blocked_sites, "reddit"
    refute_includes blocklist, "youtube.com"
    assert_includes blocklist, "reddit.com"
  end

  # ------------------------------------------------------- on again, forget

  def test_blocking_again_drops_the_pending_relock
    run!("on", "youtube")
    run!("off", "youtube", "5")
    run!("on", "youtube")
    refute File.exist?(until_path("youtube"))
    assert_match(/systemctl stop mast-relock-youtube\.timer/, systemd_log)
    assert_equal "0", status.find { |f| f[0] == "youtube" }[3]
  end

  def test_forget_drops_a_relock_but_refuses_a_blocked_site
    run!("on", "youtube")
    assert_match(/is blocked; unblock it first/, refute_run("forget", "youtube"))
    run!("off", "youtube", "5")
    run!("forget", "youtube")
    refute File.exist?(until_path("youtube"))
    assert_match(/forget takes one site/, refute_run("forget", "all"))
  end

  # ---------------------------------------------------------------- restore

  def test_restore_blocks_what_ran_out_while_the_machine_was_off
    run!("on", "youtube")
    run!("off", "youtube", "5")
    FileUtils.mkdir_p(File.dirname(until_path("youtube")))
    File.write(until_path("youtube"), (Time.now.to_i - 60).to_s)
    run!("restore")
    assert_equal ["youtube"], blocked_sites
    refute File.exist?(until_path("youtube"))
  end

  def test_restore_re_arms_what_is_still_running
    run!("on", "youtube")
    run!("off", "youtube", "30")
    # Ten minutes in, as a reboot would leave it.
    File.write(until_path("youtube"), (Time.now.to_i + 20 * 60).to_s)
    File.truncate(log_path, 0)
    run!("restore")
    assert_equal [], blocked_sites
    seconds = systemd_log[/--on-active=(\d+)s/, 1].to_i
    assert_in_delta 20 * 60, seconds, 5, "the time it has left, not the whole 30 min"
  end

  def test_restore_does_nothing_for_a_site_with_no_deadline
    run!("on", "youtube")
    File.truncate(log_path, 0)
    run!("restore")
    assert_equal ["youtube"], blocked_sites
    refute_match(/systemd-run/, systemd_log)
  end

  # ---------------------------------------------------------------- install

  def test_installing_puts_the_helper_the_rule_and_the_boot_service_in_place
    install
    assert File.executable?(installed_bin), "the helper is copied, not symlinked into the plugin"
    assert_match(/polkit.addRule/, File.read(rule_path))
    assert_match(/mast on \[a-z\]\+/, File.read(rule_path), "only `mast on <site>` skips the prompt")
    assert_match(/#{Regexp.escape(ENV["USER"])}/, File.read(rule_path), "for this user at the seat")
    assert_match(%r{ExecStart=/usr/local/bin/mast restore}, File.read(unit_path))
    assert_match(/systemctl enable mast-restore\.service/, systemd_log)
  end

  def test_installing_blocks_the_sites_it_is_given_and_nothing_else
    install("youtube")
    assert_equal ["youtube"], blocked_sites
  end

  def test_installing_twice_leaves_the_blocks_as_they_are
    install("youtube")
    once = hosts
    install
    assert_equal once, hosts
    assert_equal ["youtube"], blocked_sites
  end

  # The last thing a person sees, so not the tab-separated status the widget
  # parses.
  def test_installing_ends_with_something_readable
    out = install("youtube")
    assert_match(/Blocked now/, out)
    assert_match(/^  YouTube$/, out)
    assert_match(/8 more sites are a switch away/, out)
    refute_match(/youtube\tYouTube/, out)
  end

  def test_installing_says_so_when_nothing_is_blocked
    out = install
    assert_match(/Nothing is blocked yet/, out)
    assert_match(/9 more sites are a switch away/, out)
  end

  # Picking sites at install should decide which switches the bar shows.
  def test_the_picked_sites_are_sent_to_the_widget
    fake_gum("reddit", "twitch")
    install(ask: "yes")
    assert_match(/dev\.fazzle\.mast\.setup sites reddit,twitch/, systemd_log)
  end

  def test_picking_nothing_leaves_the_switches_alone
    fake_gum("")
    install(ask: "yes")
    refute_match(/mast\.setup sites/, systemd_log)
  end

  # A bar still running an older Mast has not registered the target yet, so
  # the call fails however long it is given.
  def test_it_says_what_to_do_when_the_widget_cannot_be_told
    fake_gum("reddit")
    deaf_shell = <<~SH
      #!/bin/sh
      echo "omarchy-shell $*" >>"$MAST_PREFIX/systemd.log"
      case "$*" in *setup*) exit 1 ;; esac
      exit 0
    SH
    File.write(File.join(@bin, "omarchy-shell"), deaf_shell)
    FileUtils.chmod(0o755, File.join(@bin, "omarchy-shell"))
    out = install(ask: "yes")
    assert_match(/omarchy restart shell/, out)
    assert_equal ["reddit"], blocked_sites, "the block itself still happened"
  end

  # Blocking a site while a video is playing should close it, the way the
  # switch in the bar does.
  def test_installing_closes_windows_for_what_it_blocked
    fake_gum("youtube")
    # A Hyprland instance to find, inside the prefix: the real session must
    # never be touched by a test.
    FileUtils.mkdir_p(File.join(@prefix, "run", "user", Process.uid.to_s, "hypr", "abc123"))
    File.write(File.join(@bin, "hyprctl"), "#!/bin/sh\necho \"hyprctl $*\" >>\"$MAST_PREFIX/systemd.log\"\necho '[]'\n")
    FileUtils.chmod(0o755, File.join(@bin, "hyprctl"))
    install(ask: "yes")
    assert_match(/close-open youtube/, systemd_log)
    assert_match(/hyprctl clients/, systemd_log, "it really ran, rather than only being asked for")
  end

  def test_installing_leaves_windows_alone_when_nothing_was_picked
    fake_gum("")
    FileUtils.mkdir_p(File.join(@prefix, "run", "user", Process.uid.to_s, "hypr", "abc123"))
    install(ask: "yes")
    refute_match(/close-open/, systemd_log)
  end

  # The panel that showed the install line is still open on it.


  def test_installing_asks_the_shell_to_open_the_panel
    install
    assert_match(/omarchy-shell -q dev\.fazzle\.mast open/, systemd_log)
  end

  # Rather than assuming the two the widget ships switches for.
  def test_installing_asks_which_sites_to_block
    fake_gum("reddit", "twitch")
    out = install(ask: "yes")
    assert_match(/Which sites should Mast block\?/, out)
    assert_equal %w[reddit twitch], blocked_sites
  end

  def test_picking_nothing_blocks_nothing
    fake_gum("")
    install(ask: "yes")
    assert_equal [], blocked_sites
  end

  def test_it_does_not_ask_again_once_something_is_blocked
    fake_gum("reddit")
    install(ask: "yes")
    fake_gum("twitch")
    out = install(ask: "yes")
    refute_match(/Which sites/, out)
    assert_equal ["reddit"], blocked_sites, "a re-run leaves the blocks as they are"
  end

  def test_sites_named_as_arguments_are_taken_instead_of_asking
    fake_gum("reddit")
    out = install("youtube", ask: "yes")
    refute_match(/Which sites/, out)
    assert_equal ["youtube"], blocked_sites
  end

  # -------------------------------------------------------------- uninstall

  def uninstall
    script(File.expand_path("../../system/uninstall.sh", __dir__))
  end

  def install(*sites, ask: "no")
    script(File.expand_path("../../system/install.sh", __dir__), *sites, ask: ask)
  end

  def script(path, *args, ask: "no")
    env = { "MAST_PREFIX" => @prefix, "MAST_BIN" => HELPER, "PATH" => "#{@bin}:#{ENV["PATH"]}",
            "SUDO_USER" => ENV["USER"], "MAST_ASK" => ask }
    out = IO.popen(env, ["bash", path, *args], err: [:child, :out], &:read)
    assert $?.success?, "#{File.basename(path)} failed: #{out}"
    out
  end

  def installed_bin = File.join(@prefix, "usr", "local", "bin", "mast")
  def rule_path = File.join(@prefix, "etc", "polkit-1", "rules.d", "50-mast.rules")
  def unit_path = File.join(@prefix, "etc", "systemd", "system", "mast-restore.service")

  def test_uninstalling_lifts_every_block_and_removes_the_helper
    install
    run!("on", "all")
    uninstall
    assert_equal ORIGINAL_HOSTS, hosts
    refute File.exist?(policy_path)
    refute File.exist?(installed_bin)
    refute File.exist?(File.join(@prefix, "var", "lib", "mast"))
  end

  # The widget stays on the bar and offers to put the helper back, so the
  # script must not claim otherwise.
  def test_uninstalling_says_what_is_left_behind
    out = uninstall
    assert_match(/nothing is blocked/, out)
    assert_match(/bar widget stays/, out)
    refute_match(/hides itself/, out)
  end
end
