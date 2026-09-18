import QtQuick
import Quickshell
import Quickshell.Io

// The passages to type: the ones written by hand in config/paragraphs.txt and
// the ones that ship in config/passages.json, watched on disk so editing
// either shows up without a restart.
//
// Which pools are in play, and what each passage has won and lost, belong to
// the widget; this keeps the passages themselves, and picks one.
Item {
  id: pool

  // { paragraphs, books, news }: the pools the settings have switched on.
  property var sources: ({ paragraphs: true, books: true, news: true })
  // { id: { won, lost, hidden } }, from the record.
  property var scores: ({})

  // The hand-written ones, with no source and an id from their text...
  property var written: []
  // ...and the excerpts, each with its source, link and licence.
  property var shipped: []
  readonly property var all: written.concat(shipped)

  // Which pool a passage came from. Only The Conversation's have its host.
  function kind(passage) {
    return !passage.url ? "paragraphs" : passage.url.indexOf("theconversation.com") !== -1 ? "news" : "books"
  }

  function count(which) {
    return all.filter(function(p) { return kind(p) === which }).length
  }

  // The pools that are on, less the hidden ones. Turning every pool off, or
  // hiding everything, must not take the challenge away with it.
  readonly property var available: {
    var on = sources
    var hidden = scores || {}
    var list = all.filter(function(p) { return on[kind(p)] && !(hidden[p.id] && hidden[p.id].hidden) })
    return list.length > 0 ? list : all
  }

  // How likely a passage is to come up: its battles won against lost, with
  // one of each assumed so a new passage starts even and no passage ever
  // drops to nothing.
  function weight(passage) {
    var score = (scores || {})[passage.id]
    return score ? (score.won + 1) / (score.won + score.lost + 2) : 0.5
  }

  // A random index into `available`, weighted towards winners, never the text
  // already on screen when there is a choice.
  function randomIndex(exceptText) {
    if (available.length === 0) return -1
    var total = 0
    var weights = available.map(function(p) {
      var w = available.length > 1 && p.text === exceptText ? 0 : weight(p)
      total += w
      return w
    })
    var roll = Math.random() * total
    for (var i = 0; i < weights.length; i++) {
      roll -= weights[i]
      if (roll < 0) return i
    }
    return weights.length - 1
  }

  // Line wrapping in the files is not something anyone should have to type.
  function flatten(text) { return String(text || "").replace(/\s+/g, " ").trim() }

  FileView {
    path: String(Qt.resolvedUrl("config/paragraphs.txt")).replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: pool.written = String(text() || "").split(/\n\s*\n/)
      .map(function(p) { return pool.flatten(p) })
      .filter(function(p) { return p !== "" })
      .map(function(p) { return { id: "paragraph-" + Qt.md5(p), text: p, source: "", url: "" } })
    onLoadFailed: pool.written = []
  }

  FileView {
    path: String(Qt.resolvedUrl("config/passages.json")).replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var list = []
      try { list = JSON.parse(text() || "[]") } catch (e) {}
      pool.shipped = (Array.isArray(list) ? list : []).filter(function(p) {
        return p && p.id && typeof p.text === "string" && p.text.trim() !== ""
      }).map(function(p) {
        return { id: String(p.id), text: pool.flatten(p.text), source: String(p.source || ""), url: String(p.url || ""),
                 license: String(p.license || ""), licenseUrl: String(p.license_url || "") }
      })
    }
    onLoadFailed: pool.shipped = []
  }
}
