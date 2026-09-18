import QtQuick
import qs.Commons
import qs.Ui

// One passage in the history tab: where it is from, how it opens, how it has
// fared, and the eye that hides it or brings it back.
Column {
  id: passageRow
  // The widget whose record this is.
  required property var widget
  required property var passage
  readonly property string summary: [passageTitle.text, opening.text, record.text].join(" | ")
  spacing: Style.space(3)
  readonly property bool hidden: {
    var score = (widget.stats.passages || {})[passage.id]
    return score ? score.hidden : passage.hidden
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
      text: (passageRow.hidden ? "Hidden  ·  " : "") + (passageRow.passage.source || "Your paragraph")
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
      onClicked: widget.setPassageHidden(passageRow.passage, !passageRow.hidden)
    }
  }

  Text {
    id: opening
    width: parent.width
    textFormat: Text.PlainText
    text: "\"" + passage.opening + "\""
    color: widget.dim
    font.family: widget.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Text {
    id: record
    width: parent.width
    textFormat: Text.StyledText
    text: "<font color='" + widget.green + "'>won " + (passage.walked_away + passage.kept_blocked) + "</font>"
      + "  ·  <font color='" + widget.urgent + "'>lost " + passage.unblocked + "</font>"
      + "  ·  shown " + passage.shown + "  ·  skipped " + passage.skipped
    color: widget.dim
    font.family: widget.fontFamily
    font.pixelSize: Style.font.caption
  }
}
