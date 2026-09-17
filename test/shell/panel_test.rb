require_relative "shell_helper"

# The dropdown itself: the rows the switches live on, which the unblock flow
# never touches.
#
# What a row should show depends on the theme and on what is blocked right
# now, so nothing here is written down: the colours are compared with the
# widget's own, and the rows with what the helper reports.
class PanelTest < ShellTest::TestCase
  def panel
    wait("the panel's rows") do
      p = JSON.parse(ipc("panel"))
      p["rows"].length >= sites.count { |s| s[:blocked] } && !p["rows"].empty? ? p : nil
    end
  end

  # [{ name, label, blocked }], as /usr/local/bin/mast status has it.
  def sites
    helper_status.lines.map { |line| line.split("\t") }
      .map { |f| { name: f[0], label: f[1], blocked: f[2].to_i == 1, relocking: f[3].to_i > 0 } }
  end

  def test_a_row_for_every_blocked_site
    p = panel
    assert p["opened"]
    blocked = sites.select { |s| s[:blocked] }.map { |s| s[:label] }
    assert_empty blocked - p["rows"].map { |r| r["label"] }, "blocked sites with no row"
  end

  def test_each_row_says_what_the_helper_says
    rows = panel["rows"].to_h { |r| [r["label"], r["state"]] }
    sites.each do |site|
      next unless rows.key?(site[:label])
      expected = site[:blocked] ? "Blocked" : site[:relocking] ? /Blocks again in/ : "Not blocked"
      assert_match expected, rows[site[:label]], site[:label]
    end
  end

  # Every one of these reads the widget, so a row that cannot see it shows
  # black text and no mark at all -- whatever the theme.
  def test_rows_are_drawn_in_the_widget_s_colours
    p = panel
    blocked = sites.select { |s| s[:blocked] }.map { |s| s[:label] }
    p["rows"].each do |row|
      assert_equal p["foreground"], row["labelColor"], "#{row["label"]} label"
      refute_empty row["icon"], "#{row["label"]} has no mark"
      # Blocked recedes; unblocked stands out in the site's own colour.
      if blocked.include?(row["label"])
        assert_equal p["dim"], row["iconColor"], "#{row["label"]} icon, blocked so dim"
      else
        refute_equal p["dim"], row["iconColor"], "#{row["label"]} icon, unblocked so its own colour"
      end
    end
  end

  def test_the_week_is_summed_up
    assert_match(/\A\d+ of \d+ unblock battles? won\z/, panel["battles"])
  end
end
