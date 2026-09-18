import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The history tab lives with the rest of the record's screens.
import "../history"

// The full-screen settings and history screen: what the gear in the panel
// opens, and `omarchy-shell fazzledev.mast.settings open`. Everything it
// shows and changes lives on the widget (Panel.qml), which it is given as
// `root`.
PanelWindow {
  id: settingsWindow
  // The widget whose settings and record these are.
  required property var widget
  // The history tab, for the test IPC.
  readonly property alias historyTab: historyTabView
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
            historyTabView.scroll(dy)
          } else if (!widget.settingsCursorActive) {
            widget.settingsCursorActive = true
          } else {
            widget.settingsCursor = Math.max(0, Math.min(widget.settingsItems.length - 1, widget.settingsCursor + dy))
            settingsTabView.reveal()
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

// ---- the tabs themselves
SettingsTab {
  id: settingsTabView
  visible: widget.settingsTab === "settings"
  widget: settingsWindow.widget
  anchors.top: settingsHeader.bottom
  anchors.topMargin: Style.space(20)
  anchors.bottom: settingsFooter.top
  anchors.bottomMargin: Style.space(12)
  anchors.left: parent.left
  anchors.right: parent.right
}

HistoryTab {
  id: historyTabView
  visible: widget.settingsTab === "history"
  widget: settingsWindow.widget
  anchors.top: settingsHeader.bottom
  anchors.topMargin: Style.space(20)
  anchors.bottom: settingsFooter.top
  anchors.bottomMargin: Style.space(12)
  anchors.left: parent.left
  anchors.right: parent.right
}

    }
  }
}
