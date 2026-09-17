# Mast

Tie yourself to the mast before the Sirens start singing.

Mast is an [Omarchy](https://omarchy.org) bar widget that blocks distracting
sites -- YouTube, X, Instagram, Reddit and more -- system-wide, and makes
unblocking one a deliberate act:

- **Type a passage first.** About 190 words, from your own paragraphs, public
  domain books (Seneca, William James, Thoreau...), Cal Newport and James
  Clear, or research in The Conversation -- ranked by Claude for how likely
  they are to talk you out of it.
- **Say why.** Your reason is saved with the attempt.
- **It blocks itself again.** Every unblock is temporary.
- **See your battles.** A history of attempts, reasons, and which passages
  won.

## Requirements

- Omarchy, with its shell
- Ruby (standard library only) and the `sqlite3` command-line tool
- Optional: `claude` for ranking passages

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
bin/fetch-passages --force    # refresh the passage pool now
```

The Ruby side is laid out like a Rails app without the gems; see
`lib/mast.rb`. Test the overlay end to end without touching the keyboard or
the real record through the `fazzledev.mast.test` IPC target (see
`Panel.qml`).
