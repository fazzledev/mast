import QtQuick
import qs.Commons
import qs.Ui

// One attempt in the history tab: when it was, how it ended, why you wanted
// the site, and how the typing went.
Column {
  id: attemptRow
  // The widget whose record this is.
  required property var widget
  required property var attempt
  readonly property string summary: [headline.text, why.text, factsLine.text].filter(function(t) { return t !== "" }).join(" | ")
  spacing: Style.space(3)

  Text {
    id: headline
    width: parent.width
    textFormat: Text.StyledText
    text: widget.escapeHtml(Qt.formatDateTime(new Date(attempt.started_at * 1000), "ddd d MMM HH:mm")
            + "  ·  " + attempt.label + "  ·  ")
      + "<font color='" + widget.outcomeColor(attempt.outcome) + "'>"
      + widget.escapeHtml(widget.outcomeLabels[attempt.outcome] || attempt.outcome) + "</font>"
    color: Color.menu.text
    font.family: widget.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    id: why
    visible: !!attempt.reason
    width: parent.width
    textFormat: Text.PlainText
    text: "Why: " + (attempt.reason || "")
    color: Color.menu.text
    font.family: widget.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    id: factsLine
    readonly property var facts: [
      attempt.wpm ? attempt.wpm + " wpm" : "",
      attempt.typing_seconds ? widget.formatDuration(attempt.typing_seconds) + " typing" : "",
      attempt.shown > 1 ? attempt.shown + " passages" : "",
      attempt.open_seconds !== null && attempt.open_seconds !== undefined ? Math.round(attempt.open_seconds / 60) + " min open" : ""
    ].filter(function(f) { return f !== "" })
    visible: facts.length > 0 || !!attempt.passage_opening
    width: parent.width
    textFormat: Text.PlainText
    text: facts.concat(attempt.passage_opening
      ? [(attempt.passage_source ? attempt.passage_source + ": " : "") + "\"" + attempt.passage_opening + "\""]
      : []).join("  ·  ")
    color: widget.dim
    font.family: widget.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
