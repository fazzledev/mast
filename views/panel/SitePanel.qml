import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The dropdown behind the bar icon: the hero with the week's tally, a row
// per site, and the collapsed list of the ones not in the setting.
KeyboardPanel {
  id: sitePanel
  // The widget whose sites these are.
  required property var widget

  // Puts the install line on the clipboard, since it is long and nobody
  // should have to retype it. Said so for a moment afterwards.
  property bool copied: false
  function copyInstallCommand() {
    widget.copyCommand(widget.installCommand)
    copied = true
    copiedFor.restart()
  }


  // What the panel is saying about tabs left open, for test mode.
  readonly property string notice: stillOpenNotice.visible ? stillOpenNotice.text : ""

  // The panel's rows, for test mode, and where the keys go when it opens.
  readonly property alias rows: siteRepeater
  function focusKeys() { keyCatcher.forceActiveFocus() }

  focusTarget: keyCatcher
  contentWidth: sitePanel.fittedContentWidth(Style.space(320))
  contentHeight: sitePanel.fittedContentHeight(column.implicitHeight, Style.space(760))

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onMoveRequested: function(dx, dy) {
      if (!widget.cursorActive) { widget.cursorActive = true; return }
      widget.cursorIndex = Math.max(0, Math.min(widget.cursorCount - 1, widget.cursorIndex + dy))
    }
    onActivateRequested: if (widget.cursorActive) widget.activate(widget.cursorIndex)
    onDeleteRequested: if (widget.cursorActive && widget.cursorIndex < widget.shownSites.length) widget.removeSite(widget.shownSites[widget.cursorIndex])
    onCloseRequested: widget.close()
    onTabRequested: function(direction) { widget.switchPanel(direction) }
    onTextKey: function(key) { if (key === "s" || key === "S") widget.openSettings("settings") }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(12)

      PanelHero {
        id: siteBlockHero
        width: parent.width
        title: "Mast"
        // Inside the hero's own components `widget` is the hero, so they
        // reach this panel through the hero's id.
        readonly property var panelRoot: sitePanel.widget
        trailingControl: Component {
          Row {
            spacing: Style.space(2)

            PanelActionButton {
              iconText: "\u{F02DA}"
              tooltipText: "History"
              foreground: siteBlockHero.foreground
              fontFamily: siteBlockHero.fontFamily
              onClicked: siteBlockHero.panelRoot.openSettings("history")
            }

            PanelActionButton {
              iconText: "\u{F0493}"
              tooltipText: "Settings (S)"
              foreground: siteBlockHero.foreground
              fontFamily: siteBlockHero.fontFamily
              onClicked: siteBlockHero.panelRoot.openSettings("settings")
            }
          }
        }
        meta: widget.helperMissing ? "helper not installed" : widget.blockedCount + " of " + widget.shownSites.length + " sites blocked"
        foreground: widget.foreground
        fontFamily: widget.fontFamily
        iconComponent: Component {
          Text {
            text: widget.barGlyph
            color: widget.barIconColor
            font.family: widget.fontFamily
            font.pixelSize: Style.font.display
          }
        }
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: widget.cfg("showWeekStats") && widget.stats.week && widget.stats.week.attempts > 0
          ? widget.battlesText() + " this week" : ""
        color: widget.foreground
        font.family: widget.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Column {
        visible: !widget.helperMissing
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          id: siteRepeater
          model: widget.helperMissing ? [] : widget.shownSites

          SiteRow {

            widget: sitePanel.widget
            required property var modelData
            required property int index
            width: parent.width
            site: modelData
            rowIndex: index
          }
        }

        MoreRow {

          widget: sitePanel.widget
          visible: widget.hiddenSites.length > 0
          width: parent.width
        }

        Repeater {
          model: widget.moreExpanded ? widget.hiddenSites : []

          HiddenSiteRow {

            widget: sitePanel.widget
            required property var modelData
            required property int index
            width: parent.width
            site: modelData
            rowIndex: widget.moreIndex + 1 + index
          }
        }
      }

      // A page already loaded keeps working until it is reloaded, and nothing
      // but you can reload it without taking the screen away.
      Text {
        id: stillOpenNotice
        textFormat: Text.PlainText
        visible: widget.stillOpen.length > 0
        width: parent.width
        text: widget.stillOpenLabels() + " is still open in a browser tab. Reload it (F5) and the block takes hold."
        color: widget.urgent
        font.family: widget.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      // A fresh install has the widget but not the helper, which is what does
      // the blocking. Saying so beats an empty panel.
      Column {
        visible: widget.helperMissing
        width: parent.width
        spacing: Style.space(8)

        Timer {
          id: copiedFor
          interval: 2500
          onTriggered: sitePanel.copied = false
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Mast needs its helper before it can block anything. It edits /etc/hosts and the Chrome policy, and only root may do that."
          color: widget.foreground
          font.family: widget.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Item {
          width: parent.width
          height: Math.max(installLine.implicitHeight, copyButton.height)

          Text {
            id: installLine
            anchors.left: parent.left
            anchors.right: copyButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: sitePanel.copied ? "Copied. Paste it into a terminal." : widget.installCommand
            color: sitePanel.copied ? widget.foreground : widget.dim
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          PanelActionButton {
            id: copyButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: sitePanel.copied ? "\u{F012C}" : "\u{F018F}"
            tooltipText: "Copy the install command"
            foreground: widget.foreground
            fontFamily: widget.fontFamily
            onClicked: sitePanel.copyInstallCommand()
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Then this panel fills with your sites."
          color: widget.dim
          font.family: widget.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: widget.lastError !== ""
        width: parent.width
        text: widget.lastError
        color: widget.urgent
        font.family: widget.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }
}
