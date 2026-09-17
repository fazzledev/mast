import QtQuick
import qs.Commons
import qs.Ui

// The history tab: the week in tiles, the attempts behind it, and how each
// passage has fared -- all of it from bin/mast-db history.
Column {
  id: historyTab
  // The widget whose record this is.
  required property var widget

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
      model: [
        { value: (historyTab.week.stayed || 0) + " of " + (historyTab.week.attempts || 0), label: "unblock battles won this week" },
        { value: String(historyTab.week.unblocked || 0), label: (historyTab.week.unblocked === 1 ? "unblock" : "unblocks") + " this week, " + Math.round((historyTab.week.unblocked_seconds || 0) / 60) + " min open" },
        { value: widget.averageWpm() > 0 ? widget.averageWpm() + " wpm" : "--", label: "average typing speed, recent attempts" }
      ]

      BorderSurface {
        required property var modelData
        width: (historyTiles.width - historyTiles.spacing * 2) / 3
        height: tileColumn.implicitHeight + Style.space(28)
        radius: Style.cornerRadius
        color: "transparent"
        borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

        Column {
          id: tileColumn
          anchors.centerIn: parent
          width: parent.width - Style.space(28)
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.value
            color: Color.menu.text
            font.family: widget.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.label
            color: widget.dim
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
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
            model: widget.historyData.attempts

            Column {
              required property var modelData
              width: attemptsColumn.width
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.StyledText
                text: widget.escapeHtml(Qt.formatDateTime(new Date(modelData.started_at * 1000), "ddd d MMM HH:mm")
                        + "  ·  " + modelData.label + "  ·  ")
                  + "<font color='" + widget.outcomeColor(modelData.outcome) + "'>"
                  + widget.escapeHtml(widget.outcomeLabels[modelData.outcome] || modelData.outcome) + "</font>"
                color: Color.menu.text
                font.family: widget.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: !!modelData.reason
                width: parent.width
                textFormat: Text.PlainText
                text: "Why: " + (modelData.reason || "")
                color: Color.menu.text
                font.family: widget.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Text {
                readonly property var facts: [
                  modelData.wpm ? modelData.wpm + " wpm" : "",
                  modelData.typing_seconds ? widget.formatDuration(modelData.typing_seconds) + " typing" : "",
                  modelData.shown > 1 ? modelData.shown + " passages" : "",
                  modelData.open_seconds !== null && modelData.open_seconds !== undefined ? Math.round(modelData.open_seconds / 60) + " min open" : ""
                ].filter(function(f) { return f !== "" })
                visible: facts.length > 0 || !!modelData.passage_opening
                width: parent.width
                textFormat: Text.PlainText
                text: facts.concat(modelData.passage_opening
                  ? [(modelData.passage_source ? modelData.passage_source + ": " : "") + "\"" + modelData.passage_opening + "\""]
                  : []).join("  ·  ")
                color: widget.dim
                font.family: widget.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
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
            model: widget.historyData.passages

            Column {
              id: passageRow
              required property var modelData
              width: passagesColumn.width
              spacing: Style.space(3)
              readonly property bool hidden: {
                var score = (widget.stats.passages || {})[modelData.id]
                return score ? score.hidden : modelData.hidden
              }
              opacity: hidden ? 0.55 : 1

              Item {
                width: parent.width
                height: Math.max(passageTitle.implicitHeight, hideToggle.height)

                Text {
                  id: passageTitle
                  anchors.left: parent.left
                  anchors.right: hideToggle.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: (passageRow.hidden ? "Hidden  ·  " : "") + (passageRow.modelData.source || "Your paragraph")
                  color: Color.menu.text
                  font.family: widget.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  id: hideToggle
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: passageRow.hidden ? "\u{F0208}" : "\u{F0209}"
                  tooltipText: passageRow.hidden ? "Show this passage again" : "Never show this passage again"
                  foreground: Color.menu.text
                  fontFamily: widget.fontFamily
                  onClicked: widget.setPassageHidden(passageRow.modelData, !passageRow.hidden)
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "\"" + modelData.opening + "\""
                color: widget.dim
                font.family: widget.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.StyledText
                text: "<font color='" + widget.green + "'>won " + (modelData.walked_away + modelData.kept_blocked) + "</font>"
                  + "  ·  <font color='" + widget.urgent + "'>lost " + modelData.unblocked + "</font>"
                  + "  ·  shown " + modelData.shown + "  ·  skipped " + modelData.skipped
                color: widget.dim
                font.family: widget.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
