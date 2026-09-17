require_relative "shell_helper"

# The dropdown itself: the rows the switches live on, which the unblock flow
# never touches.
class PanelTest < ShellTest::TestCase
  def panel
    wait("the panel's rows") do
      p = JSON.parse(ipc("panel"))
      p["rows"].length == blocked_sites.length ? p : nil
    end
  end

  # The sites the helper reports, which are the rows the panel shows.
  def blocked_sites
    `/usr/local/bin/mast status`.lines.map { |l| l.split("\t") }.select { |f| f[2].to_i == 1 }
  end

  def test_a_row_for_every_blocked_site
    p = panel
    assert p["opened"]
    assert_equal blocked_sites.map { |f| f[1] }, p["rows"].map { |r| r["label"] }
    p["rows"].each { |row| assert_equal "Blocked", row["state"] }
  end

  # Every one of these reads the widget, so a row that cannot see it shows
  # black text and no mark at all.
  def test_rows_are_drawn_in_the_widget_s_colours
    p = panel
    p["rows"].each do |row|
      assert_equal p["foreground"], row["labelColor"], "#{row["label"]} label"
      assert_equal p["dim"], row["iconColor"], "#{row["label"]} icon, blocked so dim"
      refute_empty row["icon"], "#{row["label"]} has no mark"
    end
  end

  def test_the_week_is_summed_up
    assert_match(/\A\d+ of \d+ unblock battles? won\z/, panel["battles"])
  end
end
