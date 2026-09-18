import QtQuick
import Quickshell
import Quickshell.Io

// Test mode: the widget driven over IPC, for test/shell. Nothing here is
// reachable in ordinary use -- it has its own IPC target -- and nothing in
// it touches the keyboard or the real record.
Item {
  id: harness
  // The widget under test.
  required property var widget

  // Test mode, for checking the overlay end to end without a real unblock:
  //
  //   omarchy-shell fazzledev.mast.test start youtube   open an attempt
  //   omarchy-shell fazzledev.mast.test type 12          type the passage, 12 ms a character
  //   omarchy-shell fazzledev.mast.test step 1           next passage (-1 previous)
  //   omarchy-shell fazzledev.mast.test shuffle          a random one
  //   omarchy-shell fazzledev.mast.test hide              never show this passage again
  //   omarchy-shell fazzledev.mast.test reason "..."     answer why
  //   omarchy-shell fazzledev.mast.test answer no        or yes, or esc
  //   omarchy-shell fazzledev.mast.test state            what the overlay shows, as JSON
  //   omarchy-shell fazzledev.mast.test setting coolOffSeconds 0   for this test run only
  //   omarchy-shell fazzledev.mast.test settings history  the settings screen, on test data
  //   omarchy-shell fazzledev.mast.test stop             close it and leave test mode
  //
  // Typing is fed into the field from here, never through the keyboard. The
  // overlay and settings screen take no keyboard focus, the overlay says TEST
  // MODE, everything is recorded in the test database, and "yes" unblocks
  // nothing. test/shell drives this end to end.
  IpcHandler {
    target: "fazzledev.mast.test"

    function start(site: string): string {
      if (widget.confirmingSite !== null && !widget.testMode) return "a real attempt is open"
      widget.testMode = true
      var found = widget.sites.filter(function(s) { return s.name === site })[0]
      widget.beginAttempt(found || { name: site, label: site, blocked: true, relockAt: 0 })
      return widget.confirmPhrase
    }

    function type(msPerChar: int): string {
      if (!widget.testMode || widget.confirmingSite === null || widget.confirmAsking) return "not typing"
      testTyper.interval = Math.max(1, msPerChar)
      testTyper.start()
      return "typing " + (widget.confirmPhrase.length - widget.overlayView.typed) + " characters"
    }

    function reason(text: string): string {
      if (!widget.testMode || !widget.confirmAsking) return "not asking"
      widget.overlayView.reasonText = text
      return "ok"
    }

    function step(delta: int): string {
      if (!widget.testMode || widget.confirmingSite === null || widget.confirmAsking) return "not typing"
      testTyper.stop()
      widget.stepPassage(delta)
      return widget.confirmId
    }

    function shuffle(): string {
      if (!widget.testMode || widget.confirmingSite === null || widget.confirmAsking) return "not typing"
      testTyper.stop()
      widget.shufflePassage()
      return widget.confirmId
    }

    // "true", "false" or a number.
    function setting(key: string, value: string): string {
      if (!(key in widget.settingDefaults)) return "no setting " + key
      var next = Object.assign({}, widget.testOverrides)
      next[key] = value === "true" ? true : value === "false" ? false : Number(value)
      widget.testOverrides = next
      return "ok"
    }

    function settings(tab: string): string {
      if (widget.confirmingSite !== null && !widget.testMode) return "a real attempt is open"
      widget.testMode = true
      widget.openSettings(tab)
      return "ok"
    }

    function hide(): string {
      if (!widget.testMode || widget.confirmingSite === null || widget.confirmAsking) return "not typing"
      var hidden = widget.confirmId
      widget.hideCurrentPassage()
      return "hid " + hidden + ", now " + widget.confirmId
    }

    function answer(choice: string): string {
      if (!widget.testMode || widget.confirmingSite === null) return "no test attempt"
      testTyper.stop()
      if (choice === "yes") widget.finishConfirm()
      else widget.cancelConfirm()
      return widget.confirmingSite === null ? "closed" : "still open: " + (widget.reasonMissing ? "reason missing" : widget.coolOffLeft > 0 ? "yes available in " + widget.coolOffLeft + "s" : "?")
    }

    // Points the widget at a helper that is not there, or back at the real
    // one, so the fresh-install state can be tested wherever this runs.
    function helper(path: string): string {
      widget.testMode = true
      widget.helper = path === "real" ? "/usr/local/bin/mast" : path
      widget.refresh()
      return widget.helper
    }

    // The uninstall line, copied the way the settings row copies it.
    function copyUninstall(): string {
      widget.testMode = true
      widget.copyCommand(widget.uninstallCommand)
      return widget.uninstallCommand
    }

    // A settings row as the screen would draw it, by key.
    function settingRow(key: string): string {
      var rows = widget.settingsRows.filter(function(r) { return r.key === key })
      return JSON.stringify(rows.length > 0 ? rows[0] : {})
    }

    // A tab left open on a site that has just been blocked.
    function stillOpen(names: string): string {
      widget.testMode = true
      // "none" clears it: an empty argument never reaches here.
      widget.stillOpen = names === "none" ? [] : String(names).split(",").filter(function(n) { return n !== "" })
      return String(widget.stillOpen.length)
    }

    // The copy button on the panel a fresh install shows.
    function copyInstall(): string {
      widget.testMode = true
      widget.open()
      widget.panelView.copyInstallCommand()
      return widget.installCommand
    }

    // What the history tab shows, once the settings screen is open on it.
    function history(): string {
      return JSON.stringify(widget.settingsView.visible ? widget.settingsView.historyTab.rows() : { tiles: [], attempts: [], passages: [] })
    }

    // The panel's own rows, which nothing else can see into.
    function panel(): string {
      widget.testMode = true
      widget.open()
      var rows = []
      for (var i = 0; i < widget.siteRows.count; i++) {
        var row = widget.siteRows.itemAt(i)
        if (!row) continue
        rows.push({ label: row.label, state: row.stateText, icon: row.icon,
                    iconColor: String(row.iconColor), labelColor: String(row.labelColor) })
      }
      return JSON.stringify({ opened: widget.opened, rows: rows, notice: widget.panelView.notice,
                              foreground: String(widget.foreground), dim: String(widget.dim),
                              green: String(widget.green), battles: widget.battlesText() })
    }

    function state(): string {
      return JSON.stringify({
        testMode: widget.testMode,
        helperMissing: widget.helperMissing,
        barVisible: widget.visible,
        barGlyph: widget.barGlyph,
        installCommand: widget.installCommand,
        open: widget.confirmingSite !== null,
        overlayVisible: widget.overlayView.visible,
        site: widget.confirmingSite ? widget.confirmingSite.name : null,
        attempt: widget.attemptId,
        asking: widget.confirmAsking,
        progress: widget.overlayView.typed + "/" + widget.confirmPhrase.length,
        passage: widget.confirmId,
        source: widget.confirmSource,
        url: widget.confirmUrl,
        license: widget.confirmLicense,
        coolOffLeft: widget.coolOffLeft,
        dbPending: db.pending,
        readsPending: db.reading,
        settingsOpen: widget.settingsOpen,
        settingsVisible: widget.settingsView.visible,
        settingsTab: widget.settingsTab,
        historyAttempts: widget.historyData.attempts.length,
        historyPassages: widget.historyData.passages.length,
        passages: widget.passages.length + " of " + widget.allPassages.length,
        wpm: widget.overlayView.wpm,
        typos: widget.overlayView.typos,
        summary: widget.typedSummary,
        reasonMissing: widget.reasonMissing,
        stats: widget.stats
      })
    }

    function stop(): string {
      testTyper.stop()
      if (widget.testMode && widget.confirmingSite !== null) widget.cancelConfirm()
      if (widget.testMode) {
        widget.helper = "/usr/local/bin/mast"
        widget.settingsOpen = false
        widget.close()
      }
      widget.testOverrides = {}
      widget.testMode = false
      widget.refreshStats()
      return "ok"
    }
  }

  // Test mode's typist: one character a tick, through the same onTextChanged
  // path a keystroke takes.
  Timer {
    id: testTyper
    repeat: true
    onTriggered: {
      if (!widget.testMode || widget.confirmingSite === null || widget.confirmAsking) { stop(); return }
      widget.overlayView.typeCharacter()
    }
  }
}
