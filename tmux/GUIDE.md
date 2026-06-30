# tmux Guide

A personal cheatsheet generated from `~/.config/tmux/` (`tmux.conf`, `tmux.reset.conf`, `theme.conf`).

## The prefix

Your prefix is **`Ctrl+A`** (`^A`), not the default `Ctrl+B`.

Everything below written as `prefix + x` means: press `Ctrl+A`, release, then press `x`. Bindings written as `prefix + ^X` mean press `Ctrl+A`, then `Ctrl+X`.

The status bar shows a **orange highlighted session name** while the prefix is active, grey otherwise.

## Core behaviour (set in `tmux.conf`)

| Setting | Effect |
| --- | --- |
| `base-index 1` / `renumber-windows on` | Windows start at 1 and renumber as you close them |
| `detach-on-destroy off` | Killing a session drops you into another, doesn't quit tmux |
| `escape-time 0` | No lag on `Esc` (good for vim/nvim) |
| `history-limit 1000000` | 1M lines of scrollback |
| `set-clipboard on` | Copy goes to the system clipboard |
| `mode-keys vi` | vi-style movement in copy mode |
| `status-position bottom` | Status bar at the bottom |

## Sessions

| Keys | Action |
| --- | --- |
| `prefix + o` | **sesh picker** — fuzzy switch sessions/configs/zoxide dirs (see below) |
| `prefix + S` | `choose-session` (built-in tree picker) |
| `prefix + ^A` | Jump to **last window** (toggle back and forth) |
| `prefix + ^D` | Detach from tmux |
| `prefix + ^X` | Lock the server |

### The sesh picker (`prefix + o`)

Opens an fzf popup (75%×85%). Inside it:

- `Tab` / `Shift+Tab` — move down / up
- `Ctrl+A` — show **all** sources
- `Ctrl+T` — tmux sessions only
- `Ctrl+G` — sesh **configs**
- `Ctrl+X` — **zoxide** directories
- `Ctrl+F` — **find** directories (`fd`, depth 2, under `~`)
- `Ctrl+D` — **kill** the highlighted tmux session

Requires `sesh`, `fzf`, `fd`, and `zoxide` on PATH.

## Windows

| Keys | Action |
| --- | --- |
| `prefix + ^C` | New window (in current pane's path) |
| `prefix + c` | **Kill pane** ⚠️ (note: not the default "new window") |
| `prefix + H` | Previous window |
| `prefix + L` | Next window |
| `prefix + r` | Rename window (prompts) |
| `prefix + w` or `prefix + ^W` | List windows |
| `prefix + "` | `choose-window` picker |
| `prefix + R` | **Reload** tmux config |

A window title shows `()` when a pane is zoomed.

## Panes

### Splitting

| Keys | Action |
| --- | --- |
| `prefix + s` | Split **vertical** (stacked, top/bottom) — same path |
| `prefix + v` | Split **horizontal** (side by side) — same path |
| `prefix + \|` | Split horizontal (default path) |

### Navigating (vim-style)

| Keys | Action |
| --- | --- |
| `prefix + h / j / k / l` | Move left / down / up / right |

### Resizing (repeatable — hold prefix region, tap repeatedly)

| Keys | Action |
| --- | --- |
| `prefix + ,` | Grow left by 20 |
| `prefix + .` | Grow right by 20 |
| `prefix + -` | Grow down by 7 |
| `prefix + =` | Grow up by 7 |

### Managing

| Keys | Action |
| --- | --- |
| `prefix + z` | Zoom / unzoom pane |
| `prefix + x` | Swap pane down |
| `prefix + c` | Kill pane |
| `prefix + *` | Toggle `synchronize-panes` (type to all panes at once) |
| `prefix + P` | Toggle pane border status labels |
| `prefix + K` | Send `clear` + Enter to the pane |

## Copy mode (vi keys)

| Keys | Action |
| --- | --- |
| `prefix + [` | Enter copy mode (default) |
| `v` | Begin selection |
| `y` | Yank to system clipboard (via tmux-yank) |
| `q` | Quit copy mode |

Movement uses vi keys (`h/j/k/l`, `w`, `b`, `/` to search, etc).

## Utilities & misc

| Keys | Action |
| --- | --- |
| `prefix + :` | Command prompt |
| `prefix + ^L` | Refresh client |
| `prefix + *` (no prefix repeat) | `list-clients` is `prefix + *`? See note below |

> Note: `*` is bound twice in `tmux.reset.conf` — `bind *` first to `list-clients`, then later to `setw synchronize-panes`. The **last binding wins**, so `prefix + *` toggles **synchronize-panes**.

## Plugins (managed by TPM)

| Plugin | What it gives you |
| --- | --- |
| `tpm` | Plugin manager |
| `tmux-sensible` | Sane defaults |
| `tmux-yank` | Copy to system clipboard |
| `tmux-resurrect` | Save/restore sessions (nvim sessions too) |
| `tmux-continuum` | **Auto-save & auto-restore** sessions on start |
| `tmux-thumbs` | Hint-jump to copy text on screen |
| `tmux-fzf` | fzf-driven tmux command menu |
| `tmux-fzf-url` | Open URLs from the pane via fzf |
| `tmux-floax` | Floating scratch terminal |

### Plugin keys

| Keys | Action |
| --- | --- |
| `prefix + p` | **floax** — toggle floating pane (80%×80%, cyan border) |
| `prefix + I` | TPM: install plugins (remapped to `i` via `@tpm-install`) |
| `prefix + U` | TPM: update plugins |
| `prefix + Alt+u` | TPM: uninstall removed plugins |

> tmux-fzf and tmux-fzf-url use their own default triggers; tmux-thumbs typically binds a key like `prefix + Space` (check the plugin if unbound).

**Session persistence is automatic** — `@continuum-restore on` means your layout is restored when the tmux server starts.

## TPM lifecycle

- After editing `tmux.conf`: `prefix + R` to reload, then `prefix + I` to install any new plugins.
- Plugins live in `~/.config/tmux/plugins/`.

## Theme

A minimal generated theme (`theme.conf`): black status bar, centred window list, teal active pane border, time on the right (`HH:MM`).

> ⚠️ `theme.conf` is auto-generated (`# [theme:generated] — do not edit, run theme/apply.sh`). Don't hand-edit it.
