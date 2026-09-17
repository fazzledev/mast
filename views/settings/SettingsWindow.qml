import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The full-screen settings and history screen: what the gear in the panel
// opens, and `omarchy-shell fazzledev.mast.settings open`. Everything it
// shows and changes lives on the widget (Panel.qml), which it is given as
// `root`.
PanelWindow {
  id: settingsWindow
  // The widget whose settings and record these are.
  required property var widget
  visible: widget.settingsOpen
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "fazzledev-mast-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: widget.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  onVisibleChanged: if (visible) Qt.callLater(function() { settingsKeys.forceActiveFocus() })

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
  }

  // Nothing is at stake here, unlike the unblock screen: a click beside the
  // card closes it.
  MouseArea {
    anchors.fill: parent
    onClicked: widget.settingsOpen = false
  }

  BorderSurface {
    id: settingsCard
    anchors.centerIn: parent
    width: Math.min(Style.space(1080), settingsWindow.width - Style.gapsOut * 4)
    height: Math.min(Style.space(860), settingsWindow.height - Style.gapsOut * 4)
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding * 1.5

    // Keeps clicks on the card from reaching the scrim.
    MouseArea { anchors.fill: parent }

    Item {
      id: settingsKeys
      anchors.fill: parent
      anchors.topMargin: settingsCard.contentTopInset
      anchors.rightMargin: settingsCard.contentRightInset
      anchors.bottomMargin: settingsCard.contentBottomInset
      anchors.leftMargin: settingsCard.contentLeftInset
      focus: true

      Keys.onPressed: function(event) {
        var onSettings = widget.settingsTab === "settings"
        var key = event.key
        if (key === Qt.Key_Escape) widget.settingsOpen = false
        else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) widget.switchSettingsTab()
        else if (event.text === "1") { widget.settingsTab = "settings" }
        else if (event.text === "2") { widget.settingsTab = "history"; widget.refreshHistory() }
        else if (key === Qt.Key_Down || key === Qt.Key_Up || event.text === "j" || event.text === "k") {
          var dy = key === Qt.Key_Down || event.text === "j" ? 1 : -1
          if (!onSettings) {
            attemptsFlick.contentY = Math.max(0, Math.min(attemptsFlick.contentHeight - attemptsFlick.height, attemptsFlick.contentY + dy * Style.space(80)))
          } else if (!widget.settingsCursorActive) {
            widget.settingsCursorActive = true
          } else {
            widget.settingsCursor = Math.max(0, Math.min(widget.settingsItems.length - 1, widget.settingsCursor + dy))
            leftSettings.reveal()
            rightSettings.reveal()
          }
        } else if (key === Qt.Key_Left || key === Qt.Key_Right || event.text === "h" || event.text === "l") {
          if (onSettings && widget.settingsCursorActive) {
            widget.adjustSetting(widget.settingsItems[widget.settingsCursor], key === Qt.Key_Right || event.text === "l" ? 1 : -1)
          }
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
          if (onSettings && widget.settingsCursorActive) widget.activateSetting(widget.settingsItems[widget.settingsCursor])
        } else {
          return
        }
        event.accepted = true
      }

      // Title, tabs, close.
      Item {
        id: settingsHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(settingsTitle.implicitHeight, settingsTabs.implicitHeight)

        Row {
          id: settingsTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: widget.barGlyph
            color: widget.barIconColor
            font.family: widget.fontFamily
            font.pixelSize: Style.font.display
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Mast"
            color: Color.menu.text
            font.family: widget.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Row {
          id: settingsTabs
          anchors.centerIn: parent
          spacing: Style.space(8)

          Button {
            text: "Settings"
            bordered: true
            selected: widget.settingsTab === "settings"
            foreground: Color.menu.text
            fontFamily: widget.fontFamily
            onClicked: widget.settingsTab = "settings"
          }

          Button {
            text: "History"
            bordered: true
            selected: widget.settingsTab === "history"
            foreground: Color.menu.text
            fontFamily: widget.fontFamily
            onClicked: { widget.settingsTab = "history"; widget.refreshHistory() }
          }
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\u{F0156}"
          tooltipText: "Close (Esc)"
          foreground: Color.menu.text
          fontFamily: widget.fontFamily
          onClicked: widget.settingsOpen = false
        }
      }

      Text {
        id: settingsFooter
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: widget.settingsTab === "settings"
          ? "Tab switches tabs  ·  Up/Down moves  ·  Enter toggles  ·  Left/Right adjusts  ·  Esc closes"
          : "Tab switches tabs  ·  Up/Down scrolls  ·  Esc closes  ·  From a terminal: bin/mast-db reasons | attempts | passages"
        color: widget.dim
        font.family: widget.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // ---- settings tab
      Row {
        visible: widget.settingsTab === "settings"
        anchors.top: settingsHeader.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottom: settingsFooter.top
        anchors.bottomMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(32)

        SettingsColumn {
          id: leftSettings
          widget: settingsWindow.widget
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          rows: settingsWindow.widget.settingsRows.slice(0, settingsWindow.widget.settingsSplit)
        }

        SettingsColumn {
          id: rightSettings
          widget: settingsWindow.widget
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          rows: settingsWindow.widget.settingsRows.slice(settingsWindow.widget.settingsSplit)
        }
      }

      // ---- history tab
      Column {
        id: historyTab
        visible: widget.settingsTab === "history"
        anchors.top: settingsHeader.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottom: settingsFooter.top
        anchors.bottomMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
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
    }
  }
}
