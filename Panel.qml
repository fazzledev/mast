import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar toggles for the site block in ~/.dotfiles/system/site-block.
//
// Reading the state needs no privileges; flipping it goes through pkexec, so
// every toggle raises the shell's polkit dialog. That is deliberate -- a block
// you can lift with one stray click is not much of a block.
//
// The site list comes from the helper's status output, so adding a site there
// adds a switch here with no change to this file.
Panel {
  id: root
  moduleName: "fazzledev.site-block"
  ipcTarget: "fazzledev.site-block"

  readonly property string helper: "/usr/local/bin/site-block"

  // [{ name, label, blocked }]. Empty until the first status read; the widget
  // stays hidden until then, and for good if the helper is not installed.
  property var sites: []
  readonly property bool installed: sites.length > 0
  readonly property int blockedCount: sites.filter(function(s) { return s.blocked }).length
  readonly property bool allBlocked: installed && blockedCount === sites.length
  property string pendingSite: ""
  property string lastError: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Everything blocked is the resting state, so it recedes; anything unblocked
  // stands out as a reminder that it is still off.
  // Brand glyphs for the sites the helper knows; anything added there later
  // falls back to the shield until it gets one here. The font has no X logo,
  // so X keeps the bird.
  readonly property var siteGlyphs: ({ youtube: "󰗃", twitter: "󰕄" })
  function siteGlyph(name) { return siteGlyphs[name] || "󰕥" }
  // Unblocked sites show in their brand colour -- Twitter blue for the bird,
  // since that is the mark on screen. Unknown sites fall back to urgent.
  readonly property var siteColors: ({ youtube: "#ff0000", twitter: "#1da1f2" })
  function siteColor(name) { return siteColors[name] || root.urgent }

  readonly property string barGlyph: allBlocked ? "󰕥" : "󰦞"
  readonly property color barIconColor: allBlocked ? Qt.darker(barForeground, 1.55) : urgent

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setBlocked(site, on) {
    if (!site || toggleProc.running) return
    lastError = ""
    pendingSite = site.name
    toggleProc.command = ["pkexec", root.helper, on ? "on" : "off", site.name]
    toggleProc.running = true
  }

  function flip(index) {
    var site = sites[index]
    if (site) setBlocked(site, !site.blocked)
  }

  function applyStatus(raw) {
    var next = []
    String(raw || "").split("\n").forEach(function(line) {
      var f = line.split("\t")
      if (f.length === 3 && (f[2] === "0" || f[2] === "1")) {
        next.push({ name: f[0], label: f[1], blocked: f[2] === "1" })
      }
    })
    sites = next
    if (cursorIndex >= sites.length) cursorIndex = Math.max(0, sites.length - 1)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
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
    onExited: function(exitCode) { if (exitCode !== 0) root.sites = [] }
  }

  Process {
    id: toggleProc
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.pendingSite = ""
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
    text: root.barGlyph
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursorIndex = Math.max(0, Math.min(root.sites.length - 1, root.cursorIndex + dy))
      }
      onActivateRequested: if (root.cursorActive) root.flip(root.cursorIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Site Block"
          meta: root.blockedCount + " of " + root.sites.length + " blocked"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.barGlyph
              color: root.allBlocked ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.sites

            SiteRow {
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: index
            }
          }
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

  // Icon, name, state, switch. Not the kit's Toggle, which has no icon slot.
  component SiteRow: CursorSurface {
    id: siteRow
    property var site: null
    property int rowIndex: 0
    readonly property bool pending: site !== null && root.pendingSite === site.name
    readonly property bool blocked: site !== null && site.blocked

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: siteContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = siteRow.rowIndex
      }
      onClicked: root.flip(siteRow.rowIndex)
    }

    Row {
      id: siteContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        id: siteIcon
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.heading * 1.4
        horizontalAlignment: Text.AlignHCenter
        text: root.siteGlyph(siteRow.site ? siteRow.site.name : "")
        // Blocked recedes; unblocked stands out in the site's own colour.
        color: siteRow.blocked ? root.dim : root.siteColor(siteRow.site ? siteRow.site.name : "")
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - siteIcon.width - siteSwitch.width - parent.spacing * 2
        spacing: Style.spacing.xs

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: siteRow.site ? siteRow.site.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: siteRow.pending ? "Waiting for authentication…" : (siteRow.blocked ? "Blocked" : "Not blocked")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // The row owns the click, so the switch is presentation only.
      ToggleSwitch {
        id: siteSwitch
        anchors.verticalCenter: parent.verticalCenter
        checked: siteRow.blocked
        busy: siteRow.pending
        interactive: false
        foreground: root.foreground
      }
    }
  }
}
