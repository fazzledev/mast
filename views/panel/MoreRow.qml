import QtQuick
import qs.Commons
import qs.Ui

// Expands and collapses the list of sites not in the setting.
CursorSurface {
  id: moreRow
  // The widget this belongs to: every one of these reads its state. Not
  // called `root`, which an id of that name would shadow at the call site.
  required property var widget
  hasCursor: widget.cursorActive && widget.cursorIndex === widget.moreIndex
  foreground: widget.foreground
  implicitHeight: moreContent.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      widget.cursorActive = true
      widget.cursorIndex = widget.moreIndex
    }
    onClicked: widget.moreExpanded = !widget.moreExpanded
  }

  Row {
    id: moreContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.space(10)

    Text {
      id: chevron
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.heading * 1.4
      horizontalAlignment: Text.AlignHCenter
      text: widget.moreExpanded ? "󰅀" : "󰅂"
      color: widget.dim
      font.family: widget.fontFamily
      font.pixelSize: Style.font.heading
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "More sites (" + widget.hiddenSites.length + ")"
      color: widget.dim
      font.family: widget.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
