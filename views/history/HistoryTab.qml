import QtQuick
import qs.Commons
import qs.Ui

// The history tab: the week in tiles, the attempts behind it, and how each
// passage has fared -- all of it from bin/mast-db history.
Column {
  id: historyTab
  // The widget whose record this is.
  required property var widget

  // What the rows show, for `omarchy-shell dev.fazzle.mast.test history`.
  function rows() {
    var read = function(repeater) {
      var list = []
      for (var i = 0; i < repeater.count; i++) {
        var row = repeater.itemAt(i)
        if (row) list.push(row.summary)
      }
      return list
    }
    return { tiles: read(tilesRepeater), attempts: read(attemptsRepeater), passages: read(passagesRepeater) }
  }

  // Up and down scroll the attempts, which is the long list.
  function scroll(steps) {
    attemptsFlick.contentY = Math.max(0, Math.min(attemptsFlick.contentHeight - attemptsFlick.height,
                                                  attemptsFlick.contentY + steps * Style.space(80)))
  }

  spacing: Style.space(20)

  readonly property var week: (widget.historyData.stats && widget.historyData.stats.week) || {}

  Row {
    id: historyTiles
    width: parent.width
    spacing: Style.space(16)

    Repeater {
      id: tilesRepeater
      model: [
        { value: (historyTab.week.stayed || 0) + " of " + (historyTab.week.attempts || 0), label: "unblock battles won this week" },
        { value: String(historyTab.week.unblocked || 0), label: (historyTab.week.unblocked === 1 ? "unblock" : "unblocks") + " this week, " + Math.round((historyTab.week.unblocked_seconds || 0) / 60) + " min open" },
        { value: widget.averageWpm() > 0 ? widget.averageWpm() + " wpm" : "--", label: "average typing speed, recent attempts" }
      ]

      WeekTile {
        required property var modelData
        tile: modelData
        widget: historyTab.widget
        width: (historyTiles.width - historyTiles.spacing * 2) / 3
      }
    }
  }

  Row {
    width: parent.width
    height: parent.height - historyTiles.height - parent.spacing
    spacing: Style.space(32)

    // Recent attempts, newest first.
    Column {
      width: (parent.width - parent.spacing) * 0.55
      height: parent.height
      spacing: Style.space(8)

      PanelSectionHeader {
        id: attemptsHeading
        text: "RECENT ATTEMPTS"
        foreground: Color.menu.text
        fontFamily: widget.fontFamily
      }

      Flickable {
        id: attemptsFlick
        width: parent.width
        height: parent.height - attemptsHeading.height - parent.spacing
        contentHeight: attemptsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: attemptsColumn
          width: attemptsFlick.width
          spacing: Style.space(14)

          Text {
            visible: widget.historyData.attempts.length === 0
            textFormat: Text.PlainText
            text: "No attempts yet."
            color: widget.dim
            font.family: widget.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: attemptsRepeater
            model: widget.historyData.attempts

            AttemptRow {
              required property var modelData
              attempt: modelData
              widget: historyTab.widget
              width: attemptsColumn.width
            }
          }
        }
      }
    }

    // Passages, the ones that won most often first.
    Column {
      width: (parent.width - parent.spacing) * 0.45
      height: parent.height
      spacing: Style.space(8)

      PanelSectionHeader {
        id: passagesHeading
        text: "PASSAGES"
        foreground: Color.menu.text
        fontFamily: widget.fontFamily
      }

      Flickable {
        width: parent.width
        height: parent.height - passagesHeading.height - parent.spacing
        contentHeight: passagesColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: passagesColumn
          width: parent.width
          spacing: Style.space(14)

          Text {
            visible: widget.historyData.passages.length === 0
            textFormat: Text.PlainText
            text: "No passages shown yet."
            color: widget.dim
            font.family: widget.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: passagesRepeater
            model: widget.historyData.passages

            PassageRow {
              required property var modelData
              passage: modelData
              widget: historyTab.widget
              width: passagesColumn.width
            }
          }
        }
      }
    }
  }
}
