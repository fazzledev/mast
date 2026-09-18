import QtQuick
import qs.Commons
import qs.Ui

// Icon, name, state, switch. Not the kit's Toggle, which has no icon slot.
CursorSurface {
  id: siteRow
  // The widget this belongs to: every one of these reads its state. Not
  // called `root`, which an id of that name would shadow at the call site.
  required property var widget
  property var site: null
  property int rowIndex: 0
  readonly property bool pending: site !== null && widget.pendingSite === site.name
  readonly property bool blocked: site !== null && site.blocked
  // What is on screen, for `omarchy-shell dev.fazzle.mast.test panel`.
  readonly property string label: siteLabel.text
  readonly property string stateText: siteState.text
  readonly property string icon: siteIcon.text
  readonly property color iconColor: siteIcon.color
  readonly property color labelColor: siteLabel.color

  hasCursor: widget.cursorActive && widget.cursorIndex === rowIndex
  foreground: widget.foreground
  implicitHeight: siteContent.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      widget.cursorActive = true
      widget.cursorIndex = siteRow.rowIndex
    }
    onClicked: widget.flip(siteRow.rowIndex)
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
      text: widget.siteGlyph(siteRow.site ? siteRow.site.name : "")
      // Blocked recedes; unblocked stands out in the site's own colour.
      color: siteRow.blocked ? widget.dim : widget.siteColor(siteRow.site ? siteRow.site.name : "")
      font.family: widget.fontFamily
      font.pixelSize: Style.font.heading
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - siteIcon.width - siteSwitch.width - parent.spacing * 2
        - (removeButton.visible ? removeButton.width + parent.spacing : 0)
      spacing: Style.spacing.xs

      Text {
        id: siteLabel
        textFormat: Text.PlainText
        width: parent.width
        text: siteRow.site ? siteRow.site.label : ""
        color: widget.foreground
        font.family: widget.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: siteState
        textFormat: Text.PlainText
        width: parent.width
        readonly property string reason: siteRow.site ? (widget.siteStats(siteRow.site.name).open_reason || "") : ""
        text: siteRow.pending ? (widget.pendingBlock ? "Blocking…" : "Waiting for authentication…") : (siteRow.blocked ? "Blocked" : (siteRow.site && siteRow.site.relockAt > 0 ? widget.relockText(siteRow.site) + (reason !== "" ? " -- " + reason : "") : "Not blocked"))
        color: widget.dim
        font.family: widget.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // Shown under the cursor only, so the resting panel stays a column of
    // switches. Delete does the same from the keyboard.
    PanelActionButton {
      id: removeButton
      anchors.verticalCenter: parent.verticalCenter
      visible: siteRow.hasCursor && widget.removable(siteRow.site)
      iconText: "󰅖"
      tooltipText: "Remove from list"
      foreground: widget.foreground
      hoverColor: widget.urgent
      fontFamily: widget.fontFamily
      onClicked: widget.removeSite(siteRow.site)
    }

    // The row owns the click, so the switch is presentation only.
    ToggleSwitch {
      id: siteSwitch
      anchors.verticalCenter: parent.verticalCenter
      checked: siteRow.blocked
      busy: siteRow.pending
      interactive: false
      foreground: widget.allBlocked && widget.cfg("greenWhenBlocked") ? widget.green : widget.foreground
      accent: widget.allBlocked && widget.cfg("greenWhenBlocked") ? widget.green : Color.accent
    }
  }
}
