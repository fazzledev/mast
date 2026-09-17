import QtQuick
import qs.Commons
import qs.Ui

// A site not in the setting: its mark, its name, and a click to show it.
CursorSurface {
  id: hiddenRow
  // The widget this belongs to: every one of these reads its state. Not
  // called `root`, which an id of that name would shadow at the call site.
  required property var widget
  property var site: null
  property int rowIndex: 0

  hasCursor: widget.cursorActive && widget.cursorIndex === rowIndex
  foreground: widget.foreground
  implicitHeight: hiddenContent.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      widget.cursorActive = true
      widget.cursorIndex = hiddenRow.rowIndex
    }
    onClicked: widget.showSite(hiddenRow.site)
  }

  Row {
    id: hiddenContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.space(10)

    Text {
      id: hiddenIcon
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.heading * 1.4
      horizontalAlignment: Text.AlignHCenter
      text: widget.siteGlyph(hiddenRow.site ? hiddenRow.site.name : "")
      color: widget.dim
      font.family: widget.fontFamily
      font.pixelSize: Style.font.heading
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - hiddenIcon.width - addLabel.width - parent.spacing * 2
      textFormat: Text.PlainText
      text: hiddenRow.site ? hiddenRow.site.label : ""
      color: widget.foreground
      font.family: widget.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: addLabel
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Add"
      color: hiddenRow.hasCursor ? widget.foreground : widget.dim
      font.family: widget.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
