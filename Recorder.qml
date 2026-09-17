import QtQuick
import Quickshell
import Quickshell.Io

// Everything that reaches the record, through bin/mast-db: the events the
// widget sends, the week's numbers it shows, and the history screen's read.
//
// One process at a time writes, so events land in the order they happened,
// and a refresh asked for while one is under way runs when that one ends.
// In test mode it all goes to the test database instead.
Item {
  id: recorder

  // The test environment keeps its attempts in a database of its own.
  property bool testMode: false
  // While the history screen is open, it is read again after every write.
  property bool keepHistoryFresh: false

  // `mast-db stats`: the last seven days, overall and per site, as
  // { attempts, stayed, unblocked, unblocked_seconds, open_reason }.
  property var stats: ({ week: {}, sites: {} })
  // `mast-db history`: { stats, attempts: [...], passages: [...] }.
  property var historyData: ({ stats: {}, attempts: [], passages: [] })

  // Events still to be written, the one being written included.
  readonly property int pending: queue.length + (writing ? 1 : 0)
  readonly property bool reading: statsReading || historyReading || statsAgain || historyAgain

  readonly property string script: String(Qt.resolvedUrl("bin/mast-db")).replace(/^file:\/\//, "")
  // [{ json, args }]; the database is fixed when the event is queued.
  property var queue: []
  // Set from start to exit: a Process's `running` lags the assignment.
  property bool writing: false
  property bool statsReading: false
  property bool historyReading: false
  // A refresh asked for while one is under way, run when it ends.
  property bool statsAgain: false
  property bool historyAgain: false

  function args() {
    return testMode ? ["ruby", script, "-e", "test"] : ["ruby", script]
  }

  // Events are stamped here, where they happen.
  function record(event) {
    event.at = Date.now()
    queue.push({ json: JSON.stringify(event), args: args() })
    drain()
  }

  function drain() {
    if (writing || queue.length === 0) return
    var next = queue.shift()
    writing = true
    writeProc.command = next.args.concat(["record", next.json])
    writeProc.running = true
  }

  function refreshStats() {
    if (statsReading) {
      statsAgain = true
      return
    }
    statsReading = true
    statsProc.command = args().concat(["stats"])
    statsProc.running = true
  }

  function refreshHistory() {
    if (historyReading) {
      historyAgain = true
      return
    }
    historyReading = true
    historyProc.command = args().concat(["history"])
    historyProc.running = true
  }

  Process {
    id: writeProc
    stderr: StdioCollector { id: writeStderr; waitForEnd: true }
    onExited: function(exitCode) {
      recorder.writing = false
      if (exitCode !== 0) console.warn("mast-db: " + String(writeStderr.text || "").trim())
      if (recorder.queue.length > 0) recorder.drain()
      else {
        recorder.refreshStats()
        if (recorder.keepHistoryFresh) recorder.refreshHistory()
      }
    }
  }

  Process {
    id: statsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { recorder.stats = JSON.parse(text) } catch (e) {}
      }
    }
    onExited: function() {
      recorder.statsReading = false
      if (recorder.statsAgain) {
        recorder.statsAgain = false
        Qt.callLater(recorder.refreshStats)
      }
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { recorder.historyData = JSON.parse(text) } catch (e) {}
      }
    }
    onExited: function() {
      recorder.historyReading = false
      if (recorder.historyAgain) {
        recorder.historyAgain = false
        Qt.callLater(recorder.refreshHistory)
      }
    }
  }

  Component.onCompleted: refreshStats()
}
