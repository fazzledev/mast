import QtQuick
import qs.Commons
import qs.Ui

// The dropdown behind the bar icon: the hero with the week's tally, a row
// per site, and the collapsed list of the ones not in the setting.
KeyboardPanel {
  id: sitePanel
  // The widget whose sites these are.
  required property var widget

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
        meta: widget.blockedCount + " of " + widget.shownSites.length + " sites blocked"
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
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          id: siteRepeater
          model: widget.shownSites

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
