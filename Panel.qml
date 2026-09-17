import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Mast: bar toggles for the site block in ~/.dotfiles/system/site-block. Named
// for Ulysses, who had himself tied to the mast before the Sirens could sing.
//
// Reading the state needs no privileges; flipping it goes through pkexec.
// Blocking is let straight through by a polkit rule the installer adds.
// Unblocking first opens a full-screen overlay where you type out a passage
// of around 190 words -- roughly five minutes, long enough for most urges to
// peak and pass -- then asks once more, plainly, whether you still want it
// unblocked, and only on a yes raises the shell's polkit dialog. A block you
// can lift with one stray click is not much of a block.
//
// Passages come from two pools mixed together: the hand-written ones in
// config/paragraphs.txt, and excerpts that bin/fetch-passages pulls from books,
// blogs and news articles and keeps in a cache, each shown with its source
// and a link. The script refreshes that cache once a week; this widget just
// runs it every few hours and it returns at once until the week is up.
//
// Before the yes/no, the question page shows the passage again with how the
// typing went, and asks why you want the site. Each attempt -- the passages
// shown, how far each got, the answer, and how it ended -- goes to a SQLite
// record through bin/mast-db, which also serves the week's numbers shown
// here and lets you look back at your reasons from a terminal. The Ruby side
// is laid out like a Rails app, without the gems: see lib/mast.rb.
//
// Most of this can be tuned from a settings screen (the gear in the panel
// header, or S): passage switching, the live wpm, how many words the why
// needs, a wait before yes, how long an unblock lasts, which passage sources
// are used and whether Claude ranks them, and the display extras. They are
// ordinary widget settings, declared in manifest.json and saved to shell.json.
// The same screen has a History tab: the week's numbers, recent attempts with
// their reasons, and how each passage has fared.
//
// Every unblock is temporary: the helper arms a systemd timer that blocks the
// site again, and each row counts down to it.
//
// Blocking only stops new requests, so whenever a site turns blocked -- from
// the switch or from that timer -- bin/close-open closes its web app windows
// and reloads browser windows showing it. Otherwise a video that is already
// playing plays on.
//
// The site list comes from the helper's status output. Only the ones named in
// this widget's `sites` setting get a row -- the rest sit under a collapsed
// "More sites", where one click adds a site to the setting, and an unblocked
// row carries a remove button that takes it back out -- plus any that are blocked or
// counting down, so taking a site out of the setting never hides a block you
// would then forget about, nor lifts one.
Panel {
  id: root
  moduleName: "fazzledev.mast"
  ipcTarget: "fazzledev.mast"

  readonly property string helper: "/usr/local/bin/site-block"

  // [{ name, label, blocked }]. Empty until the first status read; the widget
  // stays hidden until then, and for good if the helper is not installed.
  property var sites: []
  readonly property bool installed: sites.length > 0
  // Names from the `sites` setting (see manifest.json).
  readonly property var enabledNames: {
    var v = setting("sites", ["youtube", "twitter"])
    return Array.isArray(v) ? v : String(v).split(/[,\s]+/)
  }
  // Adds and removes whose settings write has not landed yet ({ name: bool }),
  // so a row comes and goes on the click rather than a moment later.
  property var listOverrides: ({})
  readonly property var listedNames: {
    var names = enabledNames.filter(function(n) { return n && listOverrides[n] !== false })
    for (var n in listOverrides) if (listOverrides[n] === true && names.indexOf(n) === -1) names.push(n)
    return names
  }
  readonly property var shownSites: sites.filter(function(s) {
    return s.blocked || s.relockAt > 0 || listedNames.indexOf(s.name) !== -1
  })
  readonly property var hiddenSites: sites.filter(function(s) { return shownSites.indexOf(s) === -1 })
  property bool moreExpanded: false

  // One cursor runs down the site rows, the "More sites" row, then -- when it
  // is open -- the hidden sites.
  readonly property int moreIndex: hiddenSites.length > 0 ? shownSites.length : -1
  readonly property int cursorCount: shownSites.length + (hiddenSites.length > 0 ? 1 + (moreExpanded ? hiddenSites.length : 0) : 0)
  readonly property int blockedCount: shownSites.filter(function(s) { return s.blocked }).length
  readonly property bool allBlocked: installed && blockedCount === shownSites.length
  property string pendingSite: ""
  property bool pendingBlock: false
  property string lastError: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  // The site being unblocked in the overlay (null when it is closed), and the
  // paragraph drawn for it.
  property var confirmingSite: null
  // Index into `passages` of the one on screen; the prev and next buttons
  // step from it.
  property int confirmIndex: -1
  property string confirmPhrase: ""
  property string confirmSource: ""
  property string confirmUrl: ""
  // Typing done; the overlay is on its yes/no question.
  property bool confirmAsking: false
  // The attempt being recorded, the number of the passage view within it,
  // and the typing figures once a passage is finished:
  // { seconds, words, wpm, peakWpm, typos }.
  property string attemptId: ""
  property int viewSeq: -1
  property var typedSummary: null
  // The attempt waiting on the password prompt, and its answer to why.
  property string authAttempt: ""
  property string authReason: ""
  // Set when yes is chosen before the why is answered.
  property bool reasonMissing: false
  // `mast-db stats`: the last seven days, overall and per site, as
  // { attempts, stayed, unblocked, unblocked_seconds, open_reason }.
  property var stats: ({ week: {}, sites: {} })

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Brand glyphs for the sites the helper knows; anything added there later
  // falls back to the shield until it gets one here. The font has no X logo,
  // so X keeps the bird.
  // TikTok has no mark in the font either, so it gets a music note.
  readonly property var siteGlyphs: ({
    youtube: "󰗃", twitter: "󰕄", instagram: "󰋾", facebook: "󰈌",
    tiktok: "󰝚", reddit: "󰑍", twitch: "󰕃", netflix: "󰝆", hackernews: "\uf1d4"
  })
  function siteGlyph(name) { return siteGlyphs[name] || "󰕥" }
  // Unblocked sites show in their brand colour -- Twitter blue for the bird,
  // since that is the mark on screen. Unknown sites fall back to urgent.
  readonly property var siteColors: ({
    youtube: "#ff0000", twitter: "#1da1f2", instagram: "#e1306c", facebook: "#1877f2",
    tiktok: "#ff0050", reddit: "#ff4500", twitch: "#9146ff", netflix: "#e50914", hackernews: "#ff6600"
  })
  function siteColor(name) { return siteColors[name] || root.urgent }

  // The theme's terminal green from colors.toml, which the shell's Color does
  // not expose. Everything blocked shows in it; anything unblocked stands out
  // in urgent as a reminder that it is still off.
  property color green: "#4caf50"
  readonly property string barGlyph: allBlocked ? "󰕥" : "󰦞"
  readonly property color barIconColor: allBlocked ? (cfg("greenWhenBlocked") ? green : Qt.darker(barForeground, 1.55)) : urgent

  // [{ text, source, url }]. Blank-line separated paragraphs from
  // config/paragraphs.txt, whitespace collapsed so line wrapping in the file never
  // has to be typed, with no source...
  property var paragraphs: []
  // ...and the fetched excerpts, which have one.
  property var fetchedPassages: []
  readonly property var allPassages: paragraphs.concat(fetchedPassages)
  // Which source a passage came from, going by its link.
  function passageKind(p) {
    if (!p.url) return "paragraphs"
    if (p.url.indexOf("gutenberg.org") !== -1) return "books"
    if (p.url.indexOf("theconversation.com") !== -1) return "news"
    return "blogs"
  }
  readonly property var passages: {
    var on = { paragraphs: cfg("sourceParagraphs"), books: cfg("sourceBooks"), blogs: cfg("sourceBlogs"), news: cfg("sourceNews") }
    var list = allPassages.filter(function(p) { return on[passageKind(p)] })
    // Turning every source off must not take the challenge away with it.
    return list.length > 0 ? list : allPassages
  }
  readonly property string passageCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/fazzledev-mast/passages.json"

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function normalise(text) {
    return String(text || "").replace(/\s+/g, " ")
  }

  function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // A random index, never the passage on screen when there is a choice.
  function randomPassageIndex() {
    if (passages.length === 0) return -1
    var next = Math.floor(Math.random() * passages.length)
    if (passages.length > 1 && passages[next].text === confirmPhrase) return randomPassageIndex()
    return next
  }

  // Switching passage starts the typing over, so hunting for an easier one
  // costs whatever was already typed.
  function showPassage(index) {
    var passage = passages[index]
    if (!passage) return
    if (attemptId !== "" && viewSeq >= 0) {
      record({ type: "leave", attempt: attemptId, seq: viewSeq, chars: phraseField.lastGood })
    }
    confirmIndex = index
    confirmPhrase = passage.text
    confirmSource = passage.source
    confirmUrl = passage.url
    phraseField.text = ""
    phraseField.lastText = ""
    phraseField.lastGood = 0
    phraseField.progressLog = []
    phraseField.startedAt = 0
    phraseField.wpm = 0
    phraseField.peakWpm = 0
    phraseField.typos = 0
    phraseField.wasOnTrack = true
    phraseField.forceActiveFocus()
    if (attemptId !== "") {
      viewSeq += 1
      record({ type: "passage", attempt: attemptId, seq: viewSeq, text: passage.text, source: passage.source, url: passage.url })
    }
  }

  function stepPassage(delta) {
    if (!cfg("allowSwitching") || passages.length < 2) return
    showPassage((confirmIndex + delta + passages.length) % passages.length)
  }

  function shufflePassage() {
    if (cfg("allowSwitching") && passages.length > 1) showPassage(randomPassageIndex())
  }

  readonly property string dbScript: String(Qt.resolvedUrl("bin/mast-db")).replace(/^file:\/\//, "")
  // [{ json, db }]; the database is fixed when the event is queued.
  property var dbQueue: []

  // Test mode (see the `fazzledev.mast.test` IPC target below) runs in the
  // test environment, which keeps its attempts in a database of their own.
  property bool testMode: false
  function dbArgs() {
    return testMode ? ["ruby", dbScript, "-e", "test"] : ["ruby", dbScript]
  }

  // Events are stamped here and written one process at a time, so they land
  // in the order they happened.
  function record(event) {
    event.at = Date.now()
    dbQueue.push({ json: JSON.stringify(event), args: dbArgs() })
    drainDb()
  }

  function drainDb() {
    if (dbProc.running || dbQueue.length === 0) return
    var next = dbQueue.shift()
    dbProc.command = next.args.concat(["record", next.json])
    dbProc.running = true
  }

  function refreshStats() {
    if (statsProc.running) return
    statsProc.command = dbArgs().concat(["stats"])
    statsProc.running = true
  }

  function siteStats(name) {
    return (stats.sites && stats.sites[name]) || { attempts: 0, stayed: 0, unblocked: 0, unblocked_seconds: 0 }
  }

  function formatDuration(seconds) {
    seconds = Math.round(seconds)
    if (seconds < 60) return seconds + "s"
    if (seconds < 3600) return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    return Math.floor(seconds / 3600) + "h " + Math.floor(seconds % 3600 / 60) + "m"
  }

  // Every attempt that did not end in an unblock is a battle won.
  function battlesText() {
    var all = stats.week || {}
    return all.stayed + " of " + all.attempts + " unblock " + (all.attempts === 1 ? "battle" : "battles") + " won"
  }

  // The week so far, as a reminder on both overlay pages.
  function weekText(site) {
    if (!site || !cfg("showWeekStats")) return ""
    var here = siteStats(site.name)
    var all = stats.week || {}
    var parts = []
    if (here.unblocked > 0) {
      parts.push("You unblocked " + site.label + " " + (here.unblocked === 1 ? "once" : here.unblocked + " times")
        + " in the last week, for " + Math.round(here.unblocked_seconds / 60) + " min.")
    }
    if (all.attempts > 0) parts.push(battlesText() + " this week.")
    return parts.join(" ")
  }

  function reasonGiven() {
    var need = cfg("reasonWords")
    return need <= 0 || reasonField.text.trim().split(/\s+/).filter(function(w) { return w !== "" }).length >= need
  }

  // The wait before yes: when it ends, and a clock that ticks until then.
  property real yesAt: 0
  property real askClock: 0
  readonly property int coolOffLeft: Math.ceil(Math.max(0, yesAt - askClock) / 1000)

  Timer {
    interval: 250
    repeat: true
    running: root.confirmAsking && root.coolOffLeft > 0
    onTriggered: root.askClock = Date.now()
  }

  // Seconds since the epoch, ticking while anything is counting down.
  property real now: Date.now() / 1000

  function relockText(site) {
    var left = Math.max(0, site.relockAt - now)
    if (left < 60) return "Blocks again in under a minute"
    return "Blocks again in " + Math.ceil(left / 60) + " min"
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setBlocked(site, on) {
    if (!site || toggleProc.running) return
    lastError = ""
    pendingSite = site.name
    pendingBlock = on
    toggleProc.command = on
      ? ["pkexec", root.helper, "on", site.name]
      : ["pkexec", root.helper, "off", site.name, String(cfg("relockMinutes"))]
    toggleProc.running = true
  }

  function activate(index) {
    if (index < shownSites.length) flip(index)
    else if (index === moreIndex) moreExpanded = !moreExpanded
    else showSite(hiddenSites[index - moreIndex - 1])
  }

  // Save settings in-process, the way the clock widget saves its format. Not
  // `omarchy bar set`: its IPC hop splits arguments on commas, which breaks any
  // JSON array longer than one element. updateEntryInline replaces the whole
  // bar entry, so every other setting -- including changes still on their way
  // -- is carried over. The shell writes shell.json through its symlink, so
  // the change lands in dotfiles.
  function saveSettings(patch) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") {
      lastError = "Could not save settings: this bar does not allow widget settings writes."
      return
    }
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var pending in settingOverrides) entry[pending] = settingOverrides[pending]
    for (var changed in patch) entry[changed] = patch[changed]
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveSites(names) { saveSettings({ sites: names }) }

  // ------------------------------------------------------------ settings
  // Defaults match manifest.json. Changes show at once through the overrides
  // and reach shell.json a moment later.
  readonly property var settingDefaults: ({
    allowSwitching: true, showWpm: true, reasonWords: 3, coolOffSeconds: 0, relockMinutes: 15,
    sourceParagraphs: true, sourceBooks: true, sourceBlogs: true, sourceNews: true, rankWithClaude: true,
    greenWhenBlocked: true, showWeekStats: true
  })
  property var settingOverrides: ({})

  function cfg(key) {
    if (settingOverrides[key] !== undefined) return settingOverrides[key]
    return setting(key, settingDefaults[key])
  }

  function setCfg(key, value) {
    var next = Object.assign({}, settingOverrides)
    next[key] = value
    settingOverrides = next
    var patch = {}
    patch[key] = value
    saveSettings(patch)
  }

  // The settings popover's rows. `section` rows are headings; the rest take
  // the cursor, in order.
  readonly property var settingsRows: [
    { section: "Typing challenge" },
    { key: "allowSwitching", type: "bool", label: "Switch passages", description: "Previous, next and shuffle on the unblock screen" },
    { key: "showWpm", type: "bool", label: "Live typing speed", description: "Words per minute while you type" },
    { key: "reasonWords", type: "int", min: 0, max: 20, step: 1, unit: " words", label: "Why needs", description: "Words the why answer needs before yes works; 0 makes it optional" },
    { key: "coolOffSeconds", type: "int", min: 0, max: 300, step: 15, unit: "s", label: "Wait before yes", description: "After the passage is typed" },
    { section: "Relock" },
    { key: "relockMinutes", type: "int", min: 1, max: 60, step: 1, unit: " min", label: "Unblock lasts", description: "Then the site blocks itself again. The helper caps it at 60." },
    { section: "Passages" },
    { key: "sourceParagraphs", type: "bool", kind: "paragraphs", label: "Your paragraphs", description: "config/paragraphs.txt" },
    { key: "sourceBooks", type: "bool", kind: "books", label: "Books", description: "Seneca, William James, Bennett, Thoreau, Marcus Aurelius, Epictetus" },
    { key: "sourceBlogs", type: "bool", kind: "blogs", label: "Blogs", description: "Cal Newport, James Clear" },
    { key: "sourceNews", type: "bool", kind: "news", label: "News", description: "Researchers writing in The Conversation" },
    { key: "rankWithClaude", type: "bool", label: "Rank with Claude", description: "Keep only fetched passages claude -p scores as convincing; off keeps keyword picks" },
    { action: "refreshPassages", type: "action", label: "Refresh passages now", description: "Fetch a new pool; takes a few minutes with ranking" },
    { section: "Display" },
    { key: "greenWhenBlocked", type: "bool", label: "Green when all blocked", description: "Bar icon and switches" },
    { key: "showWeekStats", type: "bool", label: "Week stats", description: "Unblock battles won, in the panel and the unblock screen" }
  ]
  readonly property var settingsItems: settingsRows.filter(function(r) { return !r.section })

  // The two columns of the settings tab: up to Passages, and from there.
  readonly property int settingsSplit: {
    for (var i = 0; i < settingsRows.length; i++) if (settingsRows[i].section === "Passages") return i
    return settingsRows.length
  }

  property bool settingsOpen: false
  property string settingsTab: "settings"  // or "history"
  property int settingsCursor: 0
  property bool settingsCursorActive: false

  // `mast-db history`: { stats, attempts: [...], passages: [...] }.
  property var historyData: ({ stats: {}, attempts: [], passages: [] })

  function openSettings(tab) {
    close()
    settingsTab = tab || "settings"
    settingsCursorActive = false
    settingsCursor = 0
    settingsOpen = true
    refreshHistory()
  }

  function refreshHistory() {
    if (historyProc.running) return
    historyProc.command = dbArgs().concat(["history"])
    historyProc.running = true
  }

  function switchSettingsTab() {
    settingsTab = settingsTab === "settings" ? "history" : "settings"
    if (settingsTab === "history") refreshHistory()
  }

  readonly property var outcomeLabels: ({
    walked_away: "Walked away", kept_blocked: "Kept blocked", auth_dismissed: "Closed the password prompt",
    failed: "Unblock failed", unblocked: "Unblocked", interrupted: "Interrupted", in_progress: "In progress"
  })
  function outcomeWon(outcome) { return ["walked_away", "kept_blocked", "auth_dismissed", "failed", "interrupted"].indexOf(outcome) !== -1 }
  function outcomeColor(outcome) { return outcome === "unblocked" ? urgent : outcomeWon(outcome) ? green : dim }

  function averageWpm() {
    var typed = historyData.attempts.filter(function(a) { return a.wpm > 0 })
    if (typed.length === 0) return 0
    return Math.round(typed.reduce(function(sum, a) { return sum + a.wpm }, 0) / typed.length)
  }

  function settingDescription(item) {
    if (item.action === "refreshPassages" && fetchProc.running) return "Fetching" + (cfg("rankWithClaude") ? " and ranking" : "") + "… this takes a few minutes"
    if (!item.kind) return item.description
    var count = allPassages.filter(function(p) { return passageKind(p) === item.kind }).length
    return item.description + "  ·  " + count + (count === 1 ? " passage" : " passages")
  }

  function adjustSetting(item, direction) {
    if (!item || item.type !== "int") return
    setCfg(item.key, Math.max(item.min, Math.min(item.max, cfg(item.key) + direction * item.step)))
  }

  function activateSetting(item) {
    if (!item) return
    if (item.type === "bool") setCfg(item.key, !cfg(item.key))
    else if (item.action === "refreshPassages") fetchPassages(true)
  }

  function fetchPassages(force) {
    if (fetchProc.running) return
    fetchProc.command = ["ruby", String(Qt.resolvedUrl("bin/fetch-passages")).replace(/^file:\/\//, "")]
      .concat(cfg("rankWithClaude") ? [] : ["--no-rank"])
      .concat(force ? ["--force"] : [])
    fetchProc.running = true
  }

  // Add a site to, or take one out of, the `sites` setting.
  function setListed(site, listed) {
    if (!site) return
    // Worked out here rather than read back from listedNames, which may not
    // have re-evaluated yet.
    var names = listedNames.filter(function(n) { return n !== site.name })
    if (listed) names.push(site.name)
    var next = Object.assign({}, listOverrides)
    next[site.name] = listed
    listOverrides = next
    saveSites(names)
    if (hiddenSites.length === 0) moreExpanded = false
    cursorIndex = Math.max(0, Math.min(cursorIndex, cursorCount - 1))
  }

  function showSite(site) { setListed(site, true) }

  // Only an unblocked site: a blocked one stays on screen regardless, and
  // removing it must never be a way round a block.
  function removable(site) { return !!site && !site.blocked }

  // A site counting down to its relock would stay on screen until the relock
  // fired and then be blocked for good, so its relock is dropped first. That
  // is root work outside the polkit rule, so it asks for auth -- the same
  // price as the unblock that started the countdown.
  function removeSite(site) {
    if (!removable(site) || forgetProc.running) return
    if (!(site.relockAt > 0)) {
      setListed(site, false)
      return
    }
    lastError = ""
    forgetProc.site = site
    forgetProc.command = ["pkexec", root.helper, "forget", site.name]
    forgetProc.running = true
  }

  function flip(index) {
    var site = shownSites[index]
    if (!site || toggleProc.running) return
    if (!site.blocked) {
      setBlocked(site, true)
      return
    }
    beginAttempt(site)
    close()
  }

  // Opens the overlay on a new attempt to unblock `site`.
  function beginAttempt(site) {
    var index = randomPassageIndex()
    if (index < 0) {
      lastError = "No passages to type -- config/paragraphs.txt is missing or empty, and nothing has been fetched."
      return false
    }
    attemptId = Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
    viewSeq = -1
    typedSummary = null
    record({ type: "start", attempt: attemptId, site: site.name, label: site.label })
    showPassage(index)
    confirmAsking = false
    confirmingSite = site
    refreshStats()
    return true
  }

  // Esc while typing is walking away; no on the question keeps the block,
  // with whatever was written as the reason.
  function cancelConfirm() {
    if (attemptId !== "") {
      if (confirmAsking) {
        record({ type: "end", attempt: attemptId, outcome: "kept_blocked", reason: reasonField.text })
      } else {
        record({ type: "leave", attempt: attemptId, seq: viewSeq, chars: phraseField.lastGood })
        record({ type: "end", attempt: attemptId, outcome: "walked_away" })
      }
    }
    attemptId = ""
    confirmingSite = null
    confirmAsking = false
  }

  function askConfirm() {
    var f = phraseField
    var ms = Math.max(1000, Date.now() - f.startedAt)
    var wpm = Math.round(f.lastGood / 5 / (ms / 60000))
    typedSummary = {
      seconds: ms / 1000,
      words: confirmPhrase.split(" ").length,
      wpm: wpm,
      peakWpm: Math.max(f.peakWpm, wpm),
      typos: f.typos
    }
    record({ type: "typed", attempt: attemptId, seq: viewSeq, chars: f.lastGood, typing_ms: ms,
             wpm: wpm, peak_wpm: typedSummary.peakWpm, typos: f.typos })
    reasonField.text = ""
    reasonMissing = false
    askClock = Date.now()
    yesAt = askClock + cfg("coolOffSeconds") * 1000
    confirmAsking = true
    // No is the default: Enter from the buttons straight away keeps the block.
    askKeys.yesSelected = false
    Qt.callLater(function() { reasonField.forceActiveFocus() })
  }

  // A reason of a few words is the price of yes.
  function finishConfirm() {
    if (!reasonGiven()) {
      reasonMissing = true
      reasonField.forceActiveFocus()
      return
    }
    var site = confirmingSite
    authAttempt = attemptId
    authReason = reasonField.text.trim()
    attemptId = ""
    confirmingSite = null
    confirmAsking = false
    if (testMode) {
      // Nothing is unblocked and no password prompt appears; the record
      // shows what a successful unblock would have written.
      record({ type: "end", attempt: authAttempt, reason: authReason, outcome: "unblocked" })
      authAttempt = ""
      return
    }
    setBlocked(site, false)
  }

  function applyStatus(raw) {
    var next = []
    String(raw || "").split("\n").forEach(function(line) {
      var f = line.split("\t")
      if (f.length >= 3 && (f[2] === "0" || f[2] === "1")) {
        next.push({ name: f[0], label: f[1], blocked: f[2] === "1", relockAt: parseInt(f[3] || "0", 10) || 0 })
      }
    })
    // Sites that were open last time we looked and are blocked now. Nothing
    // fires on the first read, when there is no "last time" to compare with.
    var closing = []
    next.forEach(function(site) {
      var before = sites.filter(function(s) { return s.name === site.name })[0]
      if (!before) return
      if (!before.blocked && site.blocked) {
        closing.push(site.name)
        record({ type: "blocked_again", site: site.name })
      } else if (before.blocked && !site.blocked && site.relockAt > 0) {
        record({ type: "relock", site: site.name, relock_at: site.relockAt })
      }
    })
    if (closing.length > 0) {
      Quickshell.execDetached(["bash", String(Qt.resolvedUrl("bin/close-open")).replace(/^file:\/\//, "")].concat(closing))
    }
    sites = next
    if (cursorIndex >= shownSites.length) cursorIndex = Math.max(0, shownSites.length - 1)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    moreExpanded = false
    refresh()
    refreshStats()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Test mode, for checking the overlay end to end without a real unblock:
  //
  //   omarchy-shell fazzledev.mast.test start youtube   open an attempt
  //   omarchy-shell fazzledev.mast.test type 12          type the passage, 12 ms a character
  //   omarchy-shell fazzledev.mast.test reason "..."     answer why
  //   omarchy-shell fazzledev.mast.test answer no        or yes, or esc
  //   omarchy-shell fazzledev.mast.test state            what the overlay shows, as JSON
  //   omarchy-shell fazzledev.mast.test stop             close it and leave test mode
  //
  // Typing is fed into the field from here, never through the keyboard. The
  // overlay takes no keyboard focus, says TEST MODE, writes to a throwaway
  // database in $XDG_RUNTIME_DIR, and "yes" unblocks nothing.
  IpcHandler {
    target: "fazzledev.mast.test"

    function start(site: string): string {
      if (root.confirmingSite !== null && !root.testMode) return "a real attempt is open"
      root.testMode = true
      var found = root.sites.filter(function(s) { return s.name === site })[0]
      root.beginAttempt(found || { name: site, label: site, blocked: true, relockAt: 0 })
      return root.confirmPhrase
    }

    function type(msPerChar: int): string {
      if (!root.testMode || root.confirmingSite === null || root.confirmAsking) return "not typing"
      testTyper.interval = Math.max(1, msPerChar)
      testTyper.start()
      return "typing " + (root.confirmPhrase.length - phraseField.lastGood) + " characters"
    }

    function reason(text: string): string {
      if (!root.testMode || !root.confirmAsking) return "not asking"
      reasonField.text = text
      return "ok"
    }

    function answer(choice: string): string {
      if (!root.testMode || root.confirmingSite === null) return "no test attempt"
      testTyper.stop()
      if (choice === "yes") root.finishConfirm()
      else root.cancelConfirm()
      return root.confirmingSite === null ? "closed" : "still open: " + (root.reasonMissing ? "reason missing" : root.coolOffLeft > 0 ? "yes available in " + root.coolOffLeft + "s" : "?")
    }

    function state(): string {
      return JSON.stringify({
        testMode: root.testMode,
        open: root.confirmingSite !== null,
        asking: root.confirmAsking,
        progress: phraseField.lastGood + "/" + root.confirmPhrase.length,
        wpm: phraseField.wpm,
        typos: phraseField.typos,
        summary: root.typedSummary,
        reasonMissing: root.reasonMissing,
        stats: root.stats
      })
    }

    function stop(): string {
      testTyper.stop()
      if (root.testMode && root.confirmingSite !== null) root.cancelConfirm()
      root.testMode = false
      root.refreshStats()
      return "ok"
    }
  }

  // Test mode's typist: one character a tick, through the same onTextChanged
  // path a keystroke takes.
  Timer {
    id: testTyper
    repeat: true
    onTriggered: {
      if (!root.testMode || root.confirmingSite === null || root.confirmAsking) { stop(); return }
      var typed = phraseField.text
      phraseField.text = typed + root.confirmPhrase.charAt(root.normalise(typed).length)
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = String(text() || "").match(/^\s*green\s*=\s*"(#[0-9a-fA-F]{6,8})"/m)
      if (m) root.green = m[1]
    }
  }

  FileView {
    path: String(Qt.resolvedUrl("config/paragraphs.txt")).replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.paragraphs = String(text() || "").split(/\n\s*\n/)
      .map(function(p) { return root.normalise(p).trim() })
      .filter(function(p) { return p !== "" })
      .map(function(p) { return { text: p, source: "", url: "" } })
    onLoadFailed: root.paragraphs = []
  }

  FileView {
    id: passageFile
    path: root.passageCache
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var list = []
      try { list = JSON.parse(text() || "[]") } catch (e) {}
      root.fetchedPassages = (Array.isArray(list) ? list : []).filter(function(p) {
        return p && typeof p.text === "string" && p.text.trim() !== ""
      }).map(function(p) {
        return { text: root.normalise(p.text).trim(), source: String(p.source || ""), url: String(p.url || "") }
      })
    }
    onLoadFailed: root.fetchedPassages = []
  }

  // Every few hours, so a missed week (asleep, offline) is caught up soon.
  Timer {
    interval: 6 * 3600 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.fetchPassages(false)
  }

  Process {
    id: fetchProc
    // The watch misses the cache being created for the first time.
    onExited: passageFile.reload()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.blockedCount < root.shownSites.length
    onTriggered: {
      root.now = Date.now() / 1000
      // Pick up the relock as soon as it is due rather than on the next poll.
      if (root.sites.some(function(s) { return !s.blocked && s.relockAt > 0 && s.relockAt <= root.now })) root.refresh()
    }
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
      if (root.authAttempt !== "") {
        root.record({ type: "end", attempt: root.authAttempt, reason: root.authReason,
                      outcome: exitCode === 0 ? "unblocked" : exitCode === 126 ? "auth_dismissed" : "failed" })
        root.authAttempt = ""
      }
      // 126 is pkexec's "dismissed the dialog" -- not worth an error line.
      if (exitCode !== 0 && exitCode !== 126) {
        root.lastError = String(toggleStderr.text || "").trim() || ("Failed (exit " + exitCode + ")")
      }
      root.refresh()
    }
  }

  Process {
    id: dbProc
    stderr: StdioCollector { id: dbStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("mast-db: " + String(dbStderr.text || "").trim())
      if (root.dbQueue.length > 0) root.drainDb()
      else {
        root.refreshStats()
        if (root.settingsOpen) root.refreshHistory()
      }
    }
  }

  Process {
    id: statsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.stats = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.historyData = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Component.onCompleted: refreshStats()

  Process {
    id: forgetProc
    property var site: null
    stderr: StdioCollector { id: forgetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.setListed(forgetProc.site, false)
      else if (exitCode !== 126) root.lastError = String(forgetStderr.text || "").trim() || ("Failed (exit " + exitCode + ")")
      forgetProc.site = null
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursorIndex = Math.max(0, Math.min(root.cursorCount - 1, root.cursorIndex + dy))
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.cursorIndex)
      onDeleteRequested: if (root.cursorActive && root.cursorIndex < root.shownSites.length) root.removeSite(root.shownSites[root.cursorIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(key) { if (key === "s" || key === "S") root.openSettings("settings") }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: siteBlockHero
          width: parent.width
          title: "Mast"
          // Inside the hero's own components `root` is the hero, so they
          // reach this panel through the hero's id.
          readonly property var panelRoot: root
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
          meta: root.blockedCount + " of " + root.shownSites.length + " sites blocked"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.barGlyph
              color: root.barIconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.cfg("showWeekStats") && root.stats.week && root.stats.week.attempts > 0
            ? root.battlesText() + " this week" : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.shownSites

            SiteRow {
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: index
            }
          }

          MoreRow {
            visible: root.hiddenSites.length > 0
            width: parent.width
          }

          Repeater {
            model: root.moreExpanded ? root.hiddenSites : []

            HiddenSiteRow {
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: root.moreIndex + 1 + index
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

  // ------------------------------------------------------ settings and history
  // `omarchy-shell fazzledev.mast.settings open` (or `history`), for a
  // keybinding.
  IpcHandler {
    target: "fazzledev.mast.settings"
    function open(): void { root.openSettings("settings") }
    function history(): void { root.openSettings("history") }
    function close(): void { root.settingsOpen = false }
    function toggle(): void { if (root.settingsOpen) root.settingsOpen = false; else root.openSettings("settings") }
  }

  PanelWindow {
    id: settingsWindow
    visible: root.settingsOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "fazzledev-mast-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) Qt.callLater(function() { settingsKeys.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // Nothing is at stake here, unlike the unblock screen: a click beside the
    // card closes it.
    MouseArea {
      anchors.fill: parent
      onClicked: root.settingsOpen = false
    }

    BorderSurface {
      id: settingsCard
      anchors.centerIn: parent
      width: Math.min(Style.space(1080), settingsWindow.width - Style.gapsOut * 4)
      height: Math.min(Style.space(860), settingsWindow.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding * 1.5

      // Keeps clicks on the card from reaching the scrim.
      MouseArea { anchors.fill: parent }

      Item {
        id: settingsKeys
        anchors.fill: parent
        anchors.topMargin: settingsCard.contentTopInset
        anchors.rightMargin: settingsCard.contentRightInset
        anchors.bottomMargin: settingsCard.contentBottomInset
        anchors.leftMargin: settingsCard.contentLeftInset
        focus: true

        Keys.onPressed: function(event) {
          var onSettings = root.settingsTab === "settings"
          var key = event.key
          if (key === Qt.Key_Escape) root.settingsOpen = false
          else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) root.switchSettingsTab()
          else if (event.text === "1") { root.settingsTab = "settings" }
          else if (event.text === "2") { root.settingsTab = "history"; root.refreshHistory() }
          else if (key === Qt.Key_Down || key === Qt.Key_Up || event.text === "j" || event.text === "k") {
            var dy = key === Qt.Key_Down || event.text === "j" ? 1 : -1
            if (!onSettings) {
              attemptsFlick.contentY = Math.max(0, Math.min(attemptsFlick.contentHeight - attemptsFlick.height, attemptsFlick.contentY + dy * Style.space(80)))
            } else if (!root.settingsCursorActive) {
              root.settingsCursorActive = true
            } else {
              root.settingsCursor = Math.max(0, Math.min(root.settingsItems.length - 1, root.settingsCursor + dy))
              leftSettings.reveal()
              rightSettings.reveal()
            }
          } else if (key === Qt.Key_Left || key === Qt.Key_Right || event.text === "h" || event.text === "l") {
            if (onSettings && root.settingsCursorActive) {
              root.adjustSetting(root.settingsItems[root.settingsCursor], key === Qt.Key_Right || event.text === "l" ? 1 : -1)
            }
          } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (onSettings && root.settingsCursorActive) root.activateSetting(root.settingsItems[root.settingsCursor])
          } else {
            return
          }
          event.accepted = true
        }

        // Title, tabs, close.
        Item {
          id: settingsHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(settingsTitle.implicitHeight, settingsTabs.implicitHeight)

          Row {
            id: settingsTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.barGlyph
              color: root.barIconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Mast"
              color: Color.menu.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          Row {
            id: settingsTabs
            anchors.centerIn: parent
            spacing: Style.space(8)

            Button {
              text: "Settings"
              bordered: true
              selected: root.settingsTab === "settings"
              foreground: Color.menu.text
              fontFamily: root.fontFamily
              onClicked: root.settingsTab = "settings"
            }

            Button {
              text: "History"
              bordered: true
              selected: root.settingsTab === "history"
              foreground: Color.menu.text
              fontFamily: root.fontFamily
              onClicked: { root.settingsTab = "history"; root.refreshHistory() }
            }
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0156}"
            tooltipText: "Close (Esc)"
            foreground: Color.menu.text
            fontFamily: root.fontFamily
            onClicked: root.settingsOpen = false
          }
        }

        Text {
          id: settingsFooter
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: root.settingsTab === "settings"
            ? "Tab switches tabs  ·  Up/Down moves  ·  Enter toggles  ·  Left/Right adjusts  ·  Esc closes"
            : "Tab switches tabs  ·  Up/Down scrolls  ·  Esc closes  ·  From a terminal: bin/mast-db reasons | attempts | passages"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- settings tab
        Row {
          visible: root.settingsTab === "settings"
          anchors.top: settingsHeader.bottom
          anchors.topMargin: Style.space(20)
          anchors.bottom: settingsFooter.top
          anchors.bottomMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(32)

          SettingsColumn {
            id: leftSettings
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            rows: root.settingsRows.slice(0, root.settingsSplit)
          }

          SettingsColumn {
            id: rightSettings
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            rows: root.settingsRows.slice(root.settingsSplit)
          }
        }

        // ---- history tab
        Column {
          id: historyTab
          visible: root.settingsTab === "history"
          anchors.top: settingsHeader.bottom
          anchors.topMargin: Style.space(20)
          anchors.bottom: settingsFooter.top
          anchors.bottomMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(20)

          readonly property var week: (root.historyData.stats && root.historyData.stats.week) || {}

          Row {
            id: historyTiles
            width: parent.width
            spacing: Style.space(16)

            Repeater {
              model: [
                { value: (historyTab.week.stayed || 0) + " of " + (historyTab.week.attempts || 0), label: "unblock battles won this week" },
                { value: String(historyTab.week.unblocked || 0), label: (historyTab.week.unblocked === 1 ? "unblock" : "unblocks") + " this week, " + Math.round((historyTab.week.unblocked_seconds || 0) / 60) + " min open" },
                { value: root.averageWpm() > 0 ? root.averageWpm() + " wpm" : "--", label: "average typing speed, recent attempts" }
              ]

              BorderSurface {
                required property var modelData
                width: (historyTiles.width - historyTiles.spacing * 2) / 3
                height: tileColumn.implicitHeight + Style.space(28)
                radius: Style.cornerRadius
                color: "transparent"
                borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

                Column {
                  id: tileColumn
                  anchors.centerIn: parent
                  width: parent.width - Style.space(28)
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.value
                    color: Color.menu.text
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            height: parent.height - historyTiles.height - parent.spacing
            spacing: Style.space(32)

            // Recent attempts, newest first.
            Column {
              width: (parent.width - parent.spacing) * 0.55
              height: parent.height
              spacing: Style.space(8)

              PanelSectionHeader {
                id: attemptsHeading
                text: "RECENT ATTEMPTS"
                foreground: Color.menu.text
                fontFamily: root.fontFamily
              }

              Flickable {
                id: attemptsFlick
                width: parent.width
                height: parent.height - attemptsHeading.height - parent.spacing
                contentHeight: attemptsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                  id: attemptsColumn
                  width: attemptsFlick.width
                  spacing: Style.space(14)

                  Text {
                    visible: root.historyData.attempts.length === 0
                    textFormat: Text.PlainText
                    text: "No attempts yet."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Repeater {
                    model: root.historyData.attempts

                    Column {
                      required property var modelData
                      width: attemptsColumn.width
                      spacing: Style.space(3)

                      Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: root.escapeHtml(Qt.formatDateTime(new Date(modelData.started_at * 1000), "ddd d MMM HH:mm")
                                + "  ·  " + modelData.label + "  ·  ")
                          + "<font color='" + root.outcomeColor(modelData.outcome) + "'>"
                          + root.escapeHtml(root.outcomeLabels[modelData.outcome] || modelData.outcome) + "</font>"
                        color: Color.menu.text
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: !!modelData.reason
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Why: " + (modelData.reason || "")
                        color: Color.menu.text
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WordWrap
                      }

                      Text {
                        readonly property var facts: [
                          modelData.wpm ? modelData.wpm + " wpm" : "",
                          modelData.typing_seconds ? root.formatDuration(modelData.typing_seconds) + " typing" : "",
                          modelData.shown > 1 ? modelData.shown + " passages" : "",
                          modelData.open_seconds !== null && modelData.open_seconds !== undefined ? Math.round(modelData.open_seconds / 60) + " min open" : ""
                        ].filter(function(f) { return f !== "" })
                        visible: facts.length > 0 || !!modelData.passage_opening
                        width: parent.width
                        textFormat: Text.PlainText
                        text: facts.concat(modelData.passage_opening
                          ? [(modelData.passage_source ? modelData.passage_source + ": " : "") + "\"" + modelData.passage_opening + "\""]
                          : []).join("  ·  ")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                      }
                    }
                  }
                }
              }
            }

            // Passages, the ones that won most often first.
            Column {
              width: (parent.width - parent.spacing) * 0.45
              height: parent.height
              spacing: Style.space(8)

              PanelSectionHeader {
                id: passagesHeading
                text: "PASSAGES"
                foreground: Color.menu.text
                fontFamily: root.fontFamily
              }

              Flickable {
                width: parent.width
                height: parent.height - passagesHeading.height - parent.spacing
                contentHeight: passagesColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                  id: passagesColumn
                  width: parent.width
                  spacing: Style.space(14)

                  Text {
                    visible: root.historyData.passages.length === 0
                    textFormat: Text.PlainText
                    text: "No passages shown yet."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Repeater {
                    model: root.historyData.passages

                    Column {
                      required property var modelData
                      width: passagesColumn.width
                      spacing: Style.space(3)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: modelData.source || "Your paragraph"
                        color: Color.menu.text
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "\"" + modelData.opening + "\""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: "<font color='" + root.green + "'>won " + (modelData.walked_away + modelData.kept_blocked) + "</font>"
                          + "  ·  <font color='" + root.urgent + "'>lost " + modelData.unblocked + "</font>"
                          + "  ·  shown " + modelData.shown + "  ·  skipped " + modelData.skipped
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------ unblock overlay
  PanelWindow {
    id: overlay
    visible: root.confirmingSite !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "fazzledev-mast"
    WlrLayershell.layer: WlrLayer.Overlay
    // Test mode must never take the keyboard from whatever you are doing.
    WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // showPassage has already cleared the field; focus only lands once the
    // window is mapped.
    onVisibleChanged: if (visible) Qt.callLater(function() { phraseField.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // Swallow clicks on the scrim. Walking away should be a decision -- Esc --
    // not a stray click beside the card.
    MouseArea {
      anchors.fill: parent
      onClicked: root.confirmAsking ? askKeys.forceActiveFocus() : phraseField.forceActiveFocus()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(760), overlay.width - Style.gapsOut * 4)
      height: cardBody.implicitHeight + contentTopInset + contentBottomInset
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding * 1.5

      readonly property color text: Color.menu.text
      readonly property color faint: Qt.darker(Color.menu.text, 1.6)
      readonly property string siteName: root.confirmingSite ? root.confirmingSite.name : ""

      Column {
        id: cardBody
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(16)

        Row {
          spacing: Style.space(14)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.siteGlyph(card.siteName)
            color: root.siteColor(card.siteName)
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: (root.testMode ? "TEST MODE -- " : "") + "Unblock " + (root.confirmingSite ? root.confirmingSite.label : "") + "?"
              color: card.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.confirmAsking
                ? "You typed it all out. Two questions before you decide."
                : "Type this out first. Take your time -- the urge will pass while you do."
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Text {
          readonly property string week: root.weekText(root.confirmingSite)
          visible: week !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: week
          color: card.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // What is typed so far in full colour, the rest faint. Styled text is
        // not selectable, so the paragraph cannot be copied into the field.
        Text {
          visible: !root.confirmAsking
          width: parent.width
          textFormat: Text.StyledText
          text: {
            var done = phraseField.progress
            return "<font color='" + card.text + "'>" + root.escapeHtml(root.confirmPhrase.slice(0, done)) + "</font>"
              + "<font color='" + card.faint + "'>" + root.escapeHtml(root.confirmPhrase.slice(done)) + "</font>"
          }
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          lineHeight: 1.35
          wrapMode: Text.WordWrap
        }

        // Where the passage is from, and buttons to swap it for another.
        Item {
          visible: !root.confirmAsking
          width: parent.width
          height: Math.max(sourceColumn.implicitHeight, passageControls.implicitHeight)

          // The link opens behind this overlay, to read once you are done here.
          Column {
            id: sourceColumn
            visible: root.confirmSource !== ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - passageControls.width - Style.space(16)
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "-- " + root.confirmSource
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.confirmUrl !== ""
              textFormat: Text.PlainText
              width: parent.width
              text: root.confirmUrl
              color: sourceLink.containsMouse ? card.text : card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.underline: true
              elide: Text.ElideMiddle

              MouseArea {
                id: sourceLink
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Qt.openUrlExternally(root.confirmUrl)
                  phraseField.forceActiveFocus()
                }
              }
            }
          }

          Row {
            id: passageControls
            visible: root.cfg("allowSwitching") && root.passages.length > 1
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒮"
              tooltipText: "Previous passage (Alt+Left)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.stepPassage(-1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (root.confirmIndex + 1) + " / " + root.passages.length
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒭"
              tooltipText: "Next passage (Alt+Right)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.stepPassage(1)
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒝"
              tooltipText: "Random passage (Alt+S)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.shufflePassage()
            }
          }
        }

        TextArea {
          id: phraseField
          // A typo is still shown, just in red, so it can be fixed; progress
          // holds at the last point the text was right.
          property string lastText: ""
          property int lastGood: 0
          // Typing speed over the last few seconds, in the usual five
          // characters to a word, counting only text that matches. From the
          // first keystroke until the window fills, it is over the time so far.
          readonly property int wpmWindow: 10000
          property var progressLog: [] // [{ t, chars }], plus the last entry before the window
          property real startedAt: 0
          property int wpm: 0
          // Past the first few seconds, when the figure has settled.
          property int peakWpm: 0
          // Times the text went from matching to not.
          property int typos: 0
          property bool wasOnTrack: true

          function logProgress() {
            var now = Date.now()
            if (startedAt === 0) startedAt = now
            progressLog.push({ t: now, chars: lastGood })
            while (progressLog.length > 1 && progressLog[1].t < now - wpmWindow) progressLog.shift()
          }

          function updateWpm() {
            var now = Date.now()
            var from = Math.max(now - wpmWindow, startedAt)
            var base = 0
            progressLog.forEach(function(e) { if (e.t <= from) base = e.chars })
            // A floor on the time keeps the first keystrokes from reading as
            // a burst of hundreds.
            var minutes = Math.max(now - from, 2000) / 60000
            wpm = Math.max(0, Math.round((lastGood - base) / 5 / minutes))
            if (now - startedAt >= 5000) peakWpm = Math.max(peakWpm, wpm)
          }

          // Ticks so the figure falls off when typing stops, not only when a
          // key moves it.
          Timer {
            interval: 500
            repeat: true
            running: overlay.visible && !root.confirmAsking && phraseField.startedAt > 0
            onTriggered: phraseField.updateWpm()
          }
          readonly property string typed: root.normalise(text)
          readonly property bool onTrack: root.confirmPhrase.indexOf(typed) === 0
          readonly property int progress: onTrack ? typed.length : lastGood

          visible: !root.confirmAsking
          width: parent.width
          height: Math.max(Style.space(120), implicitHeight)
          wrapMode: TextArea.Wrap
          placeholderText: "Start typing…"
          color: onTrack ? card.text : root.urgent
          placeholderTextColor: card.faint
          selectionColor: Style.selectionFillFor(card.text, Color.accent)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          padding: Style.space(10)
          background: BorderSurface {
            color: "transparent"
            borderSpec: Border.controlSpec(phraseField.activeFocus ? "focus" : "normal", card.text, Color.accent)
            radius: Style.cornerRadius
          }

          onTextChanged: {
            // More than a few characters arriving at once is a paste --
            // middle-click included -- so put the text back.
            if (text.length - lastText.length > 3) {
              text = lastText
              cursorPosition = text.length
              return
            }
            lastText = text
            // Worked out here rather than read from the bindings above, which
            // are not guaranteed to have caught up with this change yet.
            var now = root.normalise(text)
            var matches = root.confirmPhrase.indexOf(now) === 0
            if (matches) lastGood = now.length
            if (wasOnTrack && !matches) typos += 1
            wasOnTrack = matches
            if (text !== "") logProgress()
            if (now.trim() === root.confirmPhrase) root.askConfirm()
          }
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) {
              event.accepted = true
            } else if (event.modifiers & Qt.AltModifier) {
              if (event.key === Qt.Key_Left) root.stepPassage(-1)
              else if (event.key === Qt.Key_Right) root.stepPassage(1)
              else if (event.key === Qt.Key_S) root.shufflePassage()
              else return
              event.accepted = true
            }
          }
          Keys.onReturnPressed: function(event) { event.accepted = true }
          Keys.onEnterPressed: function(event) { event.accepted = true }
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            root.cancelConfirm()
          }
        }

        Item {
          visible: !root.confirmAsking
          width: parent.width
          height: progressText.implicitHeight

          Text {
            id: progressText
            textFormat: Text.PlainText
            anchors.left: parent.left
            readonly property int wordsDone: phraseField.progress === 0 ? 0 : root.confirmPhrase.slice(0, phraseField.progress).trim().split(" ").length
            readonly property int wordsTotal: root.confirmPhrase.split(" ").length
            text: phraseField.onTrack
              ? wordsDone + " of " + wordsTotal + " words" + (root.cfg("showWpm") && phraseField.startedAt > 0 ? "  ·  " + phraseField.wpm + " wpm" : "")
              : "Typo -- fix it to keep going"
            color: phraseField.onTrack ? card.faint : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: "Esc to keep it blocked"
            color: card.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // The question page: the passage again with how the typing went, why
        // you want the site, then yes or no.
        Column {
          visible: root.confirmAsking
          width: parent.width
          spacing: Style.space(16)

          Text {
            visible: root.typedSummary !== null
            width: parent.width
            textFormat: Text.PlainText
            text: root.typedSummary
              ? root.typedSummary.words + " words in " + root.formatDuration(root.typedSummary.seconds)
                + "  ·  " + root.typedSummary.wpm + " wpm average"
                + "  ·  " + root.typedSummary.peakWpm + " wpm peak"
                + "  ·  " + root.typedSummary.typos + (root.typedSummary.typos === 1 ? " typo" : " typos")
              : ""
            color: card.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.confirmPhrase
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.25
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.confirmSource !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: "-- " + root.confirmSource
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Why do you want to unblock " + (root.confirmingSite ? root.confirmingSite.label : "") + "?"
              color: card.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            TextArea {
              id: reasonField
              width: parent.width
              height: Math.max(Style.space(72), implicitHeight)
              wrapMode: TextArea.Wrap
              placeholderText: "What are you going there for?"
              color: card.text
              placeholderTextColor: card.faint
              selectionColor: Style.selectionFillFor(card.text, Color.accent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              padding: Style.space(10)
              background: BorderSurface {
                color: "transparent"
                borderSpec: Border.controlSpec(reasonField.activeFocus ? "focus" : "normal",
                                               root.reasonMissing ? root.urgent : card.text, Color.accent)
                radius: Style.cornerRadius
              }

              onTextChanged: if (root.reasonGiven()) root.reasonMissing = false
              // Enter and Tab move on to the buttons; Shift+Enter is a new line.
              Keys.onReturnPressed: function(event) {
                if (event.modifiers & Qt.ShiftModifier) return
                event.accepted = true
                askKeys.forceActiveFocus()
              }
              Keys.onEnterPressed: function(event) {
                event.accepted = true
                askKeys.forceActiveFocus()
              }
              Keys.onTabPressed: function(event) {
                event.accepted = true
                askKeys.forceActiveFocus()
              }
              Keys.onEscapePressed: function(event) {
                event.accepted = true
                root.cancelConfirm()
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.reasonMissing
                ? "Answer this first -- at least " + root.cfg("reasonWords") + (root.cfg("reasonWords") === 1 ? " word" : " words") + " -- to unblock."
                : (root.cfg("reasonWords") > 0 ? "" : "Optional. ")
                  + "Saved with this attempt whatever you decide, so you can look back at your reasons later: bin/mast-db reasons"
              color: root.reasonMissing ? root.urgent : card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // The yes/no. Keys live on this item so the buttons stay plain.
          Item {
            id: askKeys
            width: parent.width
            height: askColumn.implicitHeight

            property bool yesSelected: false

            Keys.onPressed: function(event) {
              switch (event.key) {
              case Qt.Key_Left:
              case Qt.Key_Right:
              case Qt.Key_Tab:
                askKeys.yesSelected = !askKeys.yesSelected
                break
              case Qt.Key_Up:
              case Qt.Key_Backtab:
                reasonField.forceActiveFocus()
                break
              case Qt.Key_Return:
              case Qt.Key_Enter:
              case Qt.Key_Space:
                if (askKeys.yesSelected) root.finishConfirm()
                else root.cancelConfirm()
                break
              case Qt.Key_Y:
                root.finishConfirm()
                break
              case Qt.Key_N:
              case Qt.Key_Escape:
                root.cancelConfirm()
                break
              default:
                return
              }
              event.accepted = true
            }

            Column {
              id: askColumn
              width: parent.width
              spacing: Style.space(12)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Do you still want to unblock " + (root.confirmingSite ? root.confirmingSite.label : "") + "? It blocks itself again after a while."
                color: card.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.space(10)

                Button {
                  text: "No, keep it blocked"
                  bordered: true
                  hasCursor: askKeys.activeFocus && !askKeys.yesSelected
                  foreground: card.text
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) askKeys.yesSelected = false }
                  onClicked: root.cancelConfirm()
                }

                Button {
                  text: root.coolOffLeft > 0 ? "Yes, unblock (" + root.coolOffLeft + "s)" : "Yes, unblock"
                  bordered: true
                  hasCursor: askKeys.activeFocus && askKeys.yesSelected
                  foreground: card.text
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) askKeys.yesSelected = true }
                  onClicked: root.finishConfirm()
                }
              }

              Text {
                textFormat: Text.PlainText
                text: askKeys.activeFocus
                  ? "Y / N  ·  Up to edit the reason  ·  Esc keeps it blocked"
                  : "Enter to go to the buttons  ·  Esc keeps it blocked"
                color: card.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  // One column of the settings tab: section headings and setting rows, which
  // scroll if the screen is short.
  component SettingsColumn: Flickable {
    id: settingsColumnFlick
    property var rows: []

    contentHeight: settingsColumnBody.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Scrolls the cursor's row into view, if it is in this column.
    function reveal() {
      var index = rows.indexOf(root.settingsItems[root.settingsCursor])
      if (index < 0) return
      var row = settingsColumnRepeater.itemAt(index)
      if (!row) return
      var y = row.mapToItem(settingsColumnBody, 0, 0).y
      if (y < contentY) contentY = y
      else if (y + row.height > contentY + height) contentY = y + row.height - height
    }

    Column {
      id: settingsColumnBody
      width: settingsColumnFlick.width
      spacing: Style.space(6)

      Repeater {
        id: settingsColumnRepeater
        model: settingsColumnFlick.rows

        Loader {
          id: settingLoader
          required property var modelData
          width: settingsColumnBody.width
          sourceComponent: modelData.section ? sectionHeading : settingRow

          Component {
            id: sectionHeading
            PanelSectionHeader {
              width: settingsColumnBody.width
              topPadding: Style.space(6)
              bottomPadding: Style.space(2)
              text: settingLoader.modelData.section.toUpperCase()
              foreground: Color.menu.text
              fontFamily: root.fontFamily
            }
          }

          Component {
            id: settingRow
            SettingRow {
              width: settingsColumnBody.width
              item: settingLoader.modelData
              cursorIndex: root.settingsItems.indexOf(settingLoader.modelData)
            }
          }
        }
      }
    }
  }

  // One row of the settings screen: label and description, and a switch,
  // a stepper, or a run glyph on the right.
  component SettingRow: CursorSurface {
    id: settingRowItem
    property var item: ({})
    property int cursorIndex: 0
    readonly property var value: item.key ? root.cfg(item.key) : null

    hasCursor: root.settingsCursorActive && root.settingsCursor === cursorIndex
    foreground: root.foreground
    implicitHeight: settingContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: settingRowItem.item.type === "int" ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: {
        root.settingsCursorActive = true
        root.settingsCursor = settingRowItem.cursorIndex
      }
      onClicked: root.activateSetting(settingRowItem.item)
    }

    Row {
      id: settingContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - control.width - parent.spacing
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: settingRowItem.item.label || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.settingDescription(settingRowItem.item)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Item {
        id: control
        anchors.verticalCenter: parent.verticalCenter
        width: settingRowItem.item.type === "bool" ? toggle.width
          : settingRowItem.item.type === "int" ? stepper.width : runGlyph.width
        height: Math.max(toggle.height, stepper.height, runGlyph.height)

        ToggleSwitch {
          id: toggle
          visible: settingRowItem.item.type === "bool"
          anchors.verticalCenter: parent.verticalCenter
          checked: settingRowItem.value === true
          interactive: false
          foreground: root.foreground
        }

        Row {
          id: stepper
          visible: settingRowItem.item.type === "int"
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0374}"
            enabled: settingRowItem.value > settingRowItem.item.min
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.adjustSetting(settingRowItem.item, -1)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(64)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: settingRowItem.value + (settingRowItem.item.unit || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0415}"
            enabled: settingRowItem.value < settingRowItem.item.max
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.adjustSetting(settingRowItem.item, 1)
          }
        }

        Text {
          id: runGlyph
          visible: settingRowItem.item.type === "action"
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F0450}"
          color: fetchProc.running ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading

          RotationAnimator on rotation {
            running: fetchProc.running && runGlyph.visible
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
          }
        }
      }
    }
  }

  // Expands and collapses the list of sites not in the setting.
  component MoreRow: CursorSurface {
    id: moreRow
    hasCursor: root.cursorActive && root.cursorIndex === root.moreIndex
    foreground: root.foreground
    implicitHeight: moreContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = root.moreIndex
      }
      onClicked: root.moreExpanded = !root.moreExpanded
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
        text: root.moreExpanded ? "󰅀" : "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "More sites (" + root.hiddenSites.length + ")"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // A site not in the setting: its mark, its name, and a click to show it.
  component HiddenSiteRow: CursorSurface {
    id: hiddenRow
    property var site: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: hiddenContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = hiddenRow.rowIndex
      }
      onClicked: root.showSite(hiddenRow.site)
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
        text: root.siteGlyph(hiddenRow.site ? hiddenRow.site.name : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - hiddenIcon.width - addLabel.width - parent.spacing * 2
        textFormat: Text.PlainText
        text: hiddenRow.site ? hiddenRow.site.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: addLabel
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Add"
        color: hiddenRow.hasCursor ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
          - (removeButton.visible ? removeButton.width + parent.spacing : 0)
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
          readonly property string reason: siteRow.site ? (root.siteStats(siteRow.site.name).open_reason || "") : ""
          text: siteRow.pending ? (root.pendingBlock ? "Blocking…" : "Waiting for authentication…") : (siteRow.blocked ? "Blocked" : (siteRow.site && siteRow.site.relockAt > 0 ? root.relockText(siteRow.site) + (reason !== "" ? " -- " + reason : "") : "Not blocked"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Shown under the cursor only, so the resting panel stays a column of
      // switches. Delete does the same from the keyboard.
      PanelActionButton {
        id: removeButton
        anchors.verticalCenter: parent.verticalCenter
        visible: siteRow.hasCursor && root.removable(siteRow.site)
        iconText: "󰅖"
        tooltipText: "Remove from list"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        onClicked: root.removeSite(siteRow.site)
      }

      // The row owns the click, so the switch is presentation only.
      ToggleSwitch {
        id: siteSwitch
        anchors.verticalCenter: parent.verticalCenter
        checked: siteRow.blocked
        busy: siteRow.pending
        interactive: false
        foreground: root.allBlocked && root.cfg("greenWhenBlocked") ? root.green : root.foreground
        accent: root.allBlocked && root.cfg("greenWhenBlocked") ? root.green : Color.accent
      }
    }
  }
}
