#!/usr/bin/env ruby
# Fill the unblock overlay's passage pool from the internet.
#
# Three kinds of source, each passage carrying its author, title and a link:
#
#   - Public domain books from Project Gutenberg, limited to the chapters named
#     below -- the ones about time, habit and attention. A book is downloaded
#     once and kept.
#   - Cal Newport's and James Clear's blogs, searched by topic through their
#     WordPress APIs.
#   - The Conversation: researchers writing news pieces about social media,
#     attention and procrastination. Its topic feeds carry the full articles,
#     and its licence lets anyone republish them with credit.
#
# Cutting passages is mechanical: they start at a paragraph, end at a sentence,
# run roughly as long as the hand-written ones in paragraphs.txt, and are
# flattened to ASCII so everything in them can be typed. A keyword score then
# keeps the likeliest few from each source.
#
# Whether a passage would actually talk someone out of unblocking a site is not
# something keywords can judge, so the shortlist goes to `claude -p` to be
# scored, and only the passages that score well are kept. If that step fails
# the pool from last time stays as it is; keyword picks are used only when
# there is no earlier pool at all.
#
# Writes $XDG_CACHE_HOME/fazzledev-site-block/passages.json, a list of
# { text, source, url, family, score }, where family is the book, blog or site
# the passage came from. The widget runs this every few hours; it does nothing
# until the pool is a week old. A source that fails to download keeps its
# passages from last time.
#
#   fetch-passages.rb            refresh if the pool is older than a week
#   fetch-passages.rb --force    refresh now

require "fileutils"
require "json"
require "net/http"
require "open3"
require "rexml/document"
require "uri"

CACHE = File.join(ENV["XDG_CACHE_HOME"] || File.expand_path("~/.cache"), "fazzledev-site-block")
OUT = File.join(CACHE, "passages.json")
MAX_AGE = 7 * 24 * 3600
USER_AGENT = "fazzledev-site-block/1.0 (personal focus widget)"

MIN_WORDS = 150
MAX_WORDS = 240
# Candidates per source sent for scoring, drawn from twice as many top keyword
# scorers so each week's shortlist differs.
SHORTLIST = 16
# Passages kept per source, and the score they need.
KEEP_PER_SOURCE = 6
KEEP_SCORE = 7
RANK_MODEL = "sonnet"
RANK_BATCH = 40

# [gutenberg id, source line, [[start line regex, end line regex]]]. The last
# match of a start wins, so a table of contents never counts as the chapter.
BOOKS = [
  [16287, "William James, Talks to Teachers on Psychology (1899)",
   [['VIII\. THE LAWS OF HABIT', 'IX\. THE ASSOCIATION OF IDEAS']]],
  [2274, "Arnold Bennett, How to Live on 24 Hours a Day (1908)",
   [["THE DAILY MIRACLE", "End of Project Gutenberg"]]],
  [64576, "Seneca, On the Shortness of Life (tr. Aubrey Stewart, 1900)",
   [['OF THE SHORTNESS OF LIFE\.', "THE ELEVENTH BOOK"]]],
  [205, "Henry David Thoreau, Walden (1854)",
   [["Where I Lived, and What I Lived For", "Reading"],
    ["Conclusion", "ON THE DUTY OF CIVIL DISOBEDIENCE"]]],
  [2680, "Marcus Aurelius, Meditations (tr. Meric Casaubon)",
   [["THE SECOND BOOK", "APPENDIX"]]],
  [45109, "Epictetus, The Enchiridion (tr. T. W. Higginson)",
   [["THE ENCHIRIDION", "Footnotes"]]],
].freeze

BLOGS = [
  ["https://calnewport.com", "Cal Newport",
   ["distraction", "attention", "focus", "deep work", "smartphone", "social media",
    "solitude", "digital minimalism", "slow productivity"]],
  ["https://jamesclear.com", "James Clear",
   ["habits", "focus", "procrastination", "discipline", "distraction",
    "identity", "motivation", "environment", "deliberate practice"]],
].freeze

CONVERSATION_TOPICS = %w[
  social-media-addiction-53153 doomscrolling-118127 attention-span-23989
  attention-economy-79825 procrastination-7917 digital-detox-16181
  boredom-34884 screen-time-12193 social-media-109
].freeze

TOPIC = Regexp.new(
  '\b(attention|focus\w*|distract\w*|concentrat\w*|deep work|depth|phones?|smartphones?|' \
  'social media|scroll\w*|screens?|internet|online|feeds?|apps?|algorithm\w*|addict\w*|compuls\w*|' \
  'habits?|routine\w*|disciplin\w*|procrastinat\w*|postpon\w*|delay\w*|willpower|resol\w*|' \
  'identity|goals?|practice|deliberate|craft|meaningful|improve\w*|progress|solitude|boredom|' \
  'wast\w*|idle\w*|idleness|trifl\w*|leisure|busy|pleasures?|time|hours?|days?|minutes|years|' \
  'life|lives|work|labour|effort|character|desires?)\b', Regexp::IGNORECASE)
# Housekeeping that has no place in a passage about focus.
NOISE = Regexp.new(
  'subscribe|newsletter|podcast|episode|click|sign up|https?:|www\.|sponsor|affiliate|' \
  'pre-?order|book tour|webinar|coupon|discount|this article|(our|my) course|registration',
  Regexp::IGNORECASE)

RANK_PROMPT = <<~PROMPT
  Someone has blocked distracting websites (YouTube, X, Instagram, Reddit and
  the like) on their computer. To unblock one, they must first type out a
  passage of about 190 words, which takes several minutes. The passage is the
  last thing standing between them and the site, so it should make them stop
  and choose not to.

  Score each passage from 1 to 10 for how likely typing it out is to talk them
  out of unblocking.

  Score high a passage that:
  - speaks to the reader's own choice right now: their hours, their attention,
    the work or life they actually care about
  - makes the cost of distraction, scrolling or wasted time concrete, or the
    compounding payoff of focus and good habits
  - is evidence an adult would find sobering (research on compulsive phone and
    social media use, attention, wellbeing)
  - stands on its own, with no dangling references ("this study", "as I said",
    "the following", names introduced earlier)

  Score low a passage that:
  - is about something else: children, parenting, schools, regulation, company
    news, politics, AI, metaphysics, death rites, logic
  - is balanced reassurance that screens are fine, or a how-to for someone else
  - is promotional, autobiographical housekeeping, or mostly a list
  - is too archaic or allusive to follow while typing

  8 or more means it would genuinely give a reader pause.

  Passages:

PROMPT

RANK_SCHEMA = JSON.generate(
  type: "object",
  properties: { scores: { type: "array", items: {
    type: "object",
    properties: { id: { type: "integer" }, score: { type: "integer" } },
    required: %w[id score],
  } } },
  required: ["scores"],
)

def fetch(url, redirects = 5)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: 30, read_timeout: 30) do |http|
    http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT))
  end
  if res.is_a?(Net::HTTPRedirection) && redirects > 0
    return fetch(URI.join(url, res["location"]).to_s, redirects - 1)
  end
  raise "#{url}: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
  res.body.force_encoding("UTF-8").scrub
end

ASCII = {
  "‘" => "'", "’" => "'", "‚" => "'", "‛" => "'",
  "“" => '"', "”" => '"', "„" => '"',
  "—" => "--", "–" => "-", "‒" => "-", "‐" => "-", "‑" => "-",
  "…" => "...", " " => " ", " " => " ", " " => " ", " " => " ",
  "æ" => "ae", "Æ" => "Ae", "œ" => "oe", "Œ" => "Oe",
  "é" => "e", "è" => "e", "ê" => "e", "ë" => "e", "ï" => "i", "ö" => "o", "ü" => "u",
}.freeze

# Whitespace-collapsed ASCII, or nil if something untypeable is left.
def plain(text)
  text = text.each_char.map { |c| ASCII.fetch(c, c) }.join
  text = text.gsub(/\{\d+\}/, "")                        # Gutenberg page numbers
  text = text.gsub(/\[\d+\]/, "")                        # footnote markers
  text = text.gsub(/(?<=[a-z][.,;:!?"')]|[a-z][.!?]["')])\d+(?=\s|\z)/, "") # ...and superscript ones
  text = text.gsub(/(?<!\w)_(.+?)_(?!\w)/, '\1')         # _italics_
  text = text.gsub(/\s+/, " ").strip
  text.match?(/[^\x20-\x7e]/) ? nil : text
end

ENTITIES = {
  "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => " ",
  "hellip" => "...", "mdash" => "--", "ndash" => "-",
  "lsquo" => "'", "rsquo" => "'", "ldquo" => '"', "rdquo" => '"',
}.freeze

def html_text(fragment)
  text = fragment.gsub(/<[^>]+>/, "").gsub(/&(#x\h+|#\d+|\w+);/) do
    ref = Regexp.last_match(1)
    if ref.start_with?("#x") then ref[2..].to_i(16).chr(Encoding::UTF_8)
    elsif ref.start_with?("#") then ref[1..].to_i.chr(Encoding::UTF_8)
    else ENTITIES.fetch(ref, "&#{ref};")
    end
  end
  plain(text)
end

def html_paragraphs(html)
  html.scan(%r{<p[^>]*>(.*?)</p>}m).map(&:first)
end

SENTENCE_END = /(?<=[.!?]|[.!?]["')])\s+(?=["'(]?[A-Z])/

# [first, last, text] passages that start at a paragraph and end at a
# sentence, in range. A nil paragraph is a break no passage runs across.
def windows(paragraphs)
  sentences = [] # [sentence, starts a paragraph, run]
  run = 0
  paragraphs.each do |p|
    if p.nil?
      run += 1
      next
    end
    p.split(SENTENCE_END).map(&:strip).reject(&:empty?).each_with_index do |s, i|
      sentences << [s, i.zero?, run]
    end
  end

  out = []
  sentences.each_with_index do |(_, starts, run_of_start), i|
    next unless starts
    words = 0
    (i...sentences.length).each do |j|
      break if sentences[j][2] != run_of_start
      words += sentences[j][0].split.length
      break if words > MAX_WORDS
      # A passage leading into a quote or list has no ending.
      if words >= MIN_WORDS && !sentences[j][0].match?(/(:|--)\W*\z/)
        out << [i, j, sentences[i..j].map(&:first).join(" ")]
        break
      end
    end
  end
  out
end

def topic_score(text)
  text.scan(TOPIC).flatten.map(&:downcase).uniq.length
end

# The best non-overlapping spans by keyword score, sampled for variety.
def shortlist(spans, limit)
  picked = []
  spans.sort_by { |s| -topic_score(s[2]) }.each do |span|
    picked << span unless picked.any? { |p| span[0] <= p[1] && p[0] <= span[1] }
    break if picked.length >= limit * 2
  end
  picked.shuffle.first(limit).map { |s| s[2] }
end

def book_candidates(book_id, source, sections)
  FileUtils.mkdir_p(File.join(CACHE, "books"))
  path = File.join(CACHE, "books", "pg#{book_id}.txt")
  unless File.exist?(path)
    File.write("#{path}.tmp", fetch("https://www.gutenberg.org/cache/epub/#{book_id}/pg#{book_id}.txt"))
    File.rename("#{path}.tmp", path)
  end
  text = File.read(path, encoding: "UTF-8").delete("\r")

  paragraphs = []
  sections.each do |start, stop|
    starts = text.to_enum(:scan, /^\s*#{start}\s*$/).map { Regexp.last_match }
    raise "no section matching #{start.inspect}" if starts.empty?
    from = starts.last.end(0)
    to = text.index(/^\s*#{stop}\s*$/, from) || text.length
    text[from...to].split(/\n\s*\n/).each do |block|
      lines = block.split("\n").reject { |l| l.strip.empty? }
      # Verse and block quotes are indented; they read badly run together.
      next if lines.empty? || lines.count { |l| l.start_with?("  ") } > lines.length / 2.0
      p = plain(lines.join(" ").sub(/\A\s*[IVXLC]+\.\s+/, ""))
      # Headings and chapter numbers.
      next if p.nil? || p.split.length < 8 || p.upcase == p
      paragraphs << p
    end
    paragraphs << nil
  end

  url = "https://www.gutenberg.org/ebooks/#{book_id}"
  shortlist(windows(paragraphs), SHORTLIST).map do |t|
    { "text" => t, "source" => source, "url" => url, "family" => source }
  end
end

# Each article's best passage, then the best of those. `articles` is a list of
# [source, url, [raw <p> html]].
def article_candidates(family, articles, limit)
  best = articles.filter_map do |source, url, raw_paragraphs|
    paragraphs = raw_paragraphs.map do |raw|
      p = html_text(raw)
      # Short ones are subheadings and "~~~" dividers: breaks, not text.
      p && !p.match?(NOISE) && p.split.length >= 6 ? p : nil
    end
    top = windows(paragraphs).max_by { |s| topic_score(s[2]) }
    top && { "text" => top[2], "source" => source, "url" => url, "family" => family }
  end
  best.sort_by { |c| -topic_score(c["text"]) }.first(limit * 2).shuffle.first(limit)
end

def blog_candidates(base, author, terms)
  posts = {}
  terms.each do |term|
    query = URI.encode_www_form(search: term, per_page: 20, _fields: "link,title,content")
    JSON.parse(fetch("#{base}/wp-json/wp/v2/posts?#{query}")).each { |post| posts[post["link"]] = post }
  end
  articles = posts.filter_map do |link, post|
    title = html_text(post["title"]["rendered"])
    title && [%(#{author}, "#{title}"), link, html_paragraphs(post["content"]["rendered"])]
  end
  article_candidates(author, articles, SHORTLIST)
end

def conversation_candidates
  articles = {}
  CONVERSATION_TOPICS.each do |topic|
    feed = REXML::Document.new(fetch("https://theconversation.com/topics/#{topic}/articles.atom"))
    feed.root.each_element("entry") do |entry|
      link = entry.elements["link"]&.attributes&.[]("href")
      title = plain(entry.elements["title"]&.text.to_s)
      # Names come with their affiliation: "Jane Doe, Lecturer, University of X".
      authors = entry.get_elements("author").filter_map { |a| plain(a.elements["name"]&.text.to_s.split(",").first.to_s) }
      authors.reject!(&:empty?)
      next if link.nil? || title.nil? || authors.empty?
      byline = authors.first + (authors.length > 1 ? " et al." : "")
      # Everything from the disclosure footer on is boilerplate.
      content = entry.elements["content"]&.text.to_s.split('<p class="fine-print"').first.to_s
      articles[link] = [%(#{byline}, "#{title}" (The Conversation)), link, html_paragraphs(content)]
    end
  end
  article_candidates("The Conversation", articles.values, SHORTLIST * 2)
end

def find_claude
  on_path = ENV.fetch("PATH", "").split(":").map { |d| File.join(d, "claude") }
  # The shell that runs this may not have the login PATH.
  fallbacks = %w[~/.local/bin/claude ~/.local/share/mise/shims/claude ~/.claude/local/claude].map { |p| File.expand_path(p) }
  (on_path + fallbacks).find { |p| File.executable?(p) && !File.directory?(p) }
end

# Scores from claude -p, in candidate order. Raises on any failure.
def rank(candidates)
  claude = find_claude or raise "claude not found"
  scores = Array.new(candidates.length, 0)
  candidates.each_slice(RANK_BATCH).with_index do |batch, b|
    listing = batch.each_with_index.map { |c, i| "[#{i}] (#{c["source"]})\n#{c["text"]}" }.join("\n\n")
    stdout, stderr, status = Open3.capture3(
      "timeout", "600", claude, "-p", "--model", RANK_MODEL, "--tools", "", "--no-session-persistence",
      "--setting-sources", "", "--strict-mcp-config", "--output-format", "json", "--json-schema", RANK_SCHEMA,
      stdin_data: RANK_PROMPT + listing, chdir: CACHE)
    raise "claude exited #{status.exitstatus}: #{stderr.strip[-300..] || stderr.strip}" unless status.success?
    result = JSON.parse(stdout)
    if result["is_error"] || !result["structured_output"]
      raise "claude gave no scores: #{result["result"].to_s[0, 300]}"
    end
    result["structured_output"]["scores"].each do |item|
      scores[b * RANK_BATCH + item["id"]] = item["score"] if item["id"].between?(0, batch.length - 1)
    end
  end
  scores
end

def main
  force = ARGV.include?("--force")
  return 0 if !force && File.exist?(OUT) && Time.now - File.mtime(OUT) < MAX_AGE
  FileUtils.mkdir_p(CACHE)

  previous = begin
    JSON.parse(File.read(OUT))
  rescue StandardError
    []
  end

  jobs = BOOKS.map { |b| [b[1], -> { book_candidates(*b) }] }
  jobs += BLOGS.map { |b| [b[1], -> { blog_candidates(*b) }] }
  jobs << ["The Conversation", -> { conversation_candidates }]

  candidates = []
  kept = []
  jobs.each do |family, job|
    got = job.call
    raise "no passages" if got.empty?
    candidates.concat(got)
  rescue StandardError => e
    warn "#{family}: #{e.message}"
    kept.concat(previous.select { |p| p["family"] == family })
  end

  scores = begin
    rank(candidates)
  rescue StandardError => e
    warn "ranking: #{e.message}"
    return 1 unless previous.empty?
    # Nothing to fall back on: keyword picks beat an empty pool.
    Array.new(candidates.length, KEEP_SCORE)
  end

  pool = kept.dup
  per_family = Hash.new(0)
  scores.zip(candidates).sort_by { |score, _| -score }.each do |score, c|
    # The Conversation is many writers, so it gets a bigger share.
    cap = KEEP_PER_SOURCE * (c["family"] == "The Conversation" ? 2 : 1)
    next if score < KEEP_SCORE || per_family[c["family"]] >= cap
    per_family[c["family"]] += 1
    pool << c.merge("score" => score)
  end

  if pool.empty?
    warn "no passages scored high enough; keeping the old pool"
    return 1
  end
  File.write("#{OUT}.tmp", JSON.pretty_generate(pool))
  File.rename("#{OUT}.tmp", OUT)
  warn "#{pool.length} passages from #{candidates.length} candidates"
  0
end

exit main if __FILE__ == $PROGRAM_NAME
