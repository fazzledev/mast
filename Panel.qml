import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar toggle for the YouTube block in ~/.dotfiles/system/block-youtube.
//
// Reading the state needs no privileges; flipping it goes through pkexec, so
// every toggle raises the shell's polkit dialog. That is deliberate -- a block
// you can lift with one stray click is not much of a block.
Panel {
  id: root
  moduleName: "fazzledev.youtube-block"
  ipcTarget: "fazzledev.youtube-block"

  readonly property string helper: "/usr/local/bin/block-youtube"

  // Unknown until the first status read; the widget stays hidden until then,
  // and for good if the helper is not installed.
  property bool installed: false
  property bool blocked: false
  property string lastError: ""
  readonly property bool busy: toggleProc.running

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Blocked is the resting state, so it recedes; unblocked stands out as a
  // reminder that it is still off.
  readonly property color barIconColor: blocked ? Qt.darker(barForeground, 1.55) : urgent

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setBlocked(on) {
    if (!installed || busy) return
    lastError = ""
    toggleProc.command = ["pkexec", root.helper, on ? "on" : "off"]
    toggleProc.running = true
  }

  function applyStatus(raw) {
    var match = String(raw || "").match(/^blocked\t([01])$/m)
    if (!match) return
    installed = true
    blocked = match[1] === "1"
  }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    // Through sh so a missing helper is a quiet non-zero exit rather than a
    // failed-to-start warning in the journal every poll.
    command: ["sh", "-c", "[ -x \"$1\" ] || exit 127; exec \"$1\" status", "sh", root.helper]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.installed = false }
  }

  Process {
    id: toggleProc
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // 126 is pkexec's "dismissed the dialog" -- not worth an error line.
      if (exitCode !== 0 && exitCode !== 126) {
        root.lastError = String(toggleStderr.text || "").trim() || ("Failed (exit " + exitCode + ")")
      }
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗃"
    foreground: root.barIconColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(200))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.setBlocked(!root.blocked)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight

          PanelHero {
            id: hero
            width: parent.width
            title: "YouTube"
            meta: root.busy ? "Waiting for authentication…" : (root.blocked ? "Blocked on this computer" : "Not blocked")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰗃"
                color: root.blocked ? root.dim : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            // `root` inside this component resolves to PanelHero, not this
            // Panel, so panel state is reached through `header`.
            trailingControl: Component {
              ToggleSwitch {
                id: blockSwitch
                checked: header.isBlocked
                busy: header.isBusy
                foreground: hero.foreground
                onToggled: header.flip()

                PanelToolTip {
                  visible: blockSwitch.containsMouse
                  text: header.isBlocked ? "Unblock YouTube" : "Block YouTube"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          readonly property bool isBlocked: root.blocked
          readonly property bool isBusy: root.busy
          function flip() { root.setBlocked(!root.blocked) }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
