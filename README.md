# Mast

Tie yourself to the mast before the Sirens start singing.

Mast is an [Omarchy](https://omarchy.org) bar widget that blocks distracting
sites -- YouTube, X, Instagram, Reddit and more -- system-wide, and makes
unblocking one a deliberate act:

- **Type a passage first.** About 190 words, from the 343 that ship with
  Mast -- excerpts of public domain books (Seneca, Marcus Aurelius,
  Epictetus, William James, Arnold Bennett, Thoreau and more) and of
  researchers writing in The Conversation -- or from your own paragraphs.
  The ones that win battles come up more often; hide any you never want to
  see again.
- **Say why.** Your reason is saved with the attempt.
- **It blocks itself again.** Every unblock is temporary.
- **See your battles.** A history of attempts, reasons, and which passages
  won.

## Requirements

Omarchy, whose base install already includes the Ruby and SQLite Mast needs.
Nothing else, and no network at runtime.

## Install

```sh
omarchy plugin add https://github.com/fazzledev/mast --enable
sudo bash ~/.config/omarchy/plugins/fazzledev.mast/system/install.sh
```

The second step installs `mast`, the root helper that edits `/etc/hosts` and the
Chrome policy, a polkit rule that lets blocking skip the password prompt, and
a boot service that restores pending relocks. `system/uninstall.sh` undoes it.

## Development

```sh
rake test                     # minitest, on a Ruby that has it
rake test:shell               # the widget end to end, in the running shell
bin/mast-db attempts          # the record, from a terminal
bin/mast-db reasons
bin/mast-db passages
rake passages:candidates      # cut config/books.yml into candidates to read
rake passages:build           # write config/passage_picks.yml to config/passages.json
```

The Ruby side is laid out like a Rails app without the gems; see
`lib/mast.rb`. The QML follows it: `Panel.qml` is the widget, `Recorder.qml`
is everything that reaches the record, and `views/` holds a folder per
screen -- panel, settings, history, unblock -- with the rows each is built
from. `rake test` also covers the root helper: `test/system` runs
`system/mast` itself against a temporary directory instead of `/etc` and
`/var` (`MAST_PREFIX`), with systemd faked, so blocking, unblocking, the
relock cap and `restore` are checked without root.

`rake test:shell` drives the widget in the running shell
through its `fazzledev.mast.test` IPC target: the overlay, typing, hiding,
switching, the question page and the settings screen, checked against the
test database. It never touches the keyboard or the real record, but the
overlay does cover the screen while it runs. See `test/shell/shell_helper.rb`.

## Licence

MIT, except the passages: the book excerpts are public domain, and The
Conversation's are CC BY-ND 4.0 with credit. See LICENSE and NOTICE.

## Passages and credit

The book passages are excerpts from public domain texts on Project Gutenberg,
each shown with its source and a link to the book.

The news passages are unaltered excerpts from articles published by
[The Conversation](https://theconversation.com) under the
[Creative Commons Attribution-NoDerivatives 4.0](https://creativecommons.org/licenses/by-nd/4.0/)
licence. Each is shown with its authors, the article's title, a link to it,
and the licence; the only changes are typographic (straight quotes, dashes and
spacing, so they can be typed). Only articles their feeds mark with that
licence are used.
