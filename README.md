# Mast

Tie yourself to the mast before the Sirens start singing.

Mast is an [Omarchy](https://omarchy.org) bar widget that blocks distracting
sites -- YouTube, X, Instagram, Reddit and more -- system-wide, and makes
unblocking one a deliberate act:

- **Type a passage first.** About 190 words, from 300 excerpts of public
  domain books that ship with Mast -- Seneca, Marcus Aurelius, Epictetus,
  William James, Arnold Bennett, Thoreau and more -- or from your own
  paragraphs. The ones that win battles come up more often; hide any you
  never want to see again.
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

The second step installs the root helper that edits `/etc/hosts` and the
Chrome policy, a polkit rule that lets blocking skip the password prompt, and
a boot service that restores pending relocks. `system/uninstall.sh` undoes it.

## Development

```sh
rake test                     # minitest, on a Ruby that has it
bin/mast-db attempts          # the record, from a terminal
bin/mast-db reasons
bin/mast-db passages
rake passages:candidates      # cut config/books.yml into candidates to read
rake passages:build           # write config/passage_picks.yml to config/passages.json
```

The Ruby side is laid out like a Rails app without the gems; see
`lib/mast.rb`. Test the overlay end to end without touching the keyboard or
the real record through the `fazzledev.mast.test` IPC target (see
`Panel.qml`).

The passages are excerpts from public domain texts on Project Gutenberg, each
shown with its source and a link to the book.
