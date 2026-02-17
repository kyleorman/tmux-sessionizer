# Tmux Sessionizer

A tmux session management tool for fast project switching. It combines fuzzy directory selection, automatic session creation, and optional per-project tmux layout hydration.

## Badges

![ShellCheck](https://img.shields.io/badge/ShellCheck-placeholder-lightgrey)
![Tests](https://img.shields.io/badge/Tests-placeholder-lightgrey)

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
  - [Directory Search Configuration](#directory-search-configuration)
  - [Environment Variables](#environment-variables)
  - [Session-specific Configuration](#session-specific-configuration)
  - [Shell Integration](#shell-integration)
  - [Tmux Configuration](#tmux-configuration)
  - [i3 Integration](#i3-integration)
  - [Examples Directory](#examples-directory)
- [Usage](#usage)
  - [Basic Usage](#basic-usage)
  - [Session Management](#session-management)
  - [Automatic Behavior](#automatic-behavior)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [Acknowledgment](#acknowledgment)

## Features

- Fast fuzzy selection for projects across one or more root directories
- Automatic tmux session creation and switching from selected directories
- Session naming that sanitizes project directory names for tmux safety
- Optional per-project `.tmux-sessionizer` files for custom window/pane layouts
- Optional shell helpers for toggling session persistence and cleanup routines
- Flexible discovery source precedence: CLI args, `SEARCH_DIRS`, config file, then defaults

Common use cases:

- Jump between client repos in seconds from one picker
- Bootstrap the same pane layout whenever you open a project
- Keep temporary sessions lightweight while preserving important ones
- Launch session switching directly from i3 or tmux keybindings

## Quick Start

If you already have `tmux` and `fzf` installed:

```bash
git clone https://github.com/kyleorman/tmux-sessionizer.git
cd tmux-sessionizer

mkdir -p ~/.config
cp examples/tmux-sessionizer.conf.simple ~/.config/tmux-sessionizer.conf

./tmux-sessionizer.sh
```

That gives you a working setup immediately from the repo checkout. See [Installation](#installation) for global install options.

## Prerequisites

Required tools:

- `bash` 4.0+
- `tmux`
- `fzf`
- `fd` (preferred) or `find`

Notes:

- macOS ships Bash 3.2 by default; install a newer Bash (4.0+) for full compatibility.

Optional tools/features:

- `zsh` for `.tmux-functions.zsh` session lifecycle helpers
- `shellcheck` for local linting
- BATS (or the bundled downloader in `test/run-tests.sh`) for test execution

## Installation

### Option A: Global install (recommended)

Install the main script:

```bash
sudo curl -o /usr/local/bin/tmux-sessionizer.sh https://raw.githubusercontent.com/kyleorman/tmux-sessionizer/main/tmux-sessionizer.sh
sudo chmod +x /usr/local/bin/tmux-sessionizer.sh
```

Install zsh helper functions (optional but recommended):

```bash
curl -o ~/.tmux-functions.zsh https://raw.githubusercontent.com/kyleorman/tmux-sessionizer/main/.tmux-functions.zsh
```

### Option B: Run from a local checkout

```bash
git clone https://github.com/kyleorman/tmux-sessionizer.git
cd tmux-sessionizer
chmod +x tmux-sessionizer.sh
./tmux-sessionizer.sh
```

## Configuration

### Directory Search Configuration

Create `~/.config/tmux-sessionizer.conf` to define search roots (one directory per line):

```bash
$HOME
$HOME/projects
$HOME/work
# Lines beginning with # are ignored
```

You can also use `SEARCH_DIRS` (colon-separated):

```bash
export SEARCH_DIRS="$HOME:$HOME/projects:$HOME/work"
```

Precedence order:

1. Command-line directory arguments
2. `SEARCH_DIRS` environment variable
3. `~/.config/tmux-sessionizer.conf`
4. Built-in default directories

### Environment Variables

`tmux-sessionizer.sh` supports runtime overrides via environment variables.

### FZF Height Control

By default, fzf height is automatically determined:
- **Inside tmux:** 40% height (compact popup style)
- **Outside tmux:** 100% height (full terminal, ideal for WM hotkeys)

Override with:

```bash
export TMUX_SESSIONIZER_FZF_HEIGHT="50%"
```

### Session-specific Configuration

Create `.tmux-sessionizer` inside a project directory to apply tmux commands when a new session is created for that project.

Example:

```tmux
rename-window -t 0 editor
split-window -h -t 0 -c "#{pane_current_path}"
new-window -n tools -c "#{pane_current_path}"
```

You can start with the provided template:

```bash
cp examples/.tmux-sessionizer.example /path/to/project/.tmux-sessionizer
```

### Shell Integration

Add to `~/.zshrc`:

```zsh
source ~/.tmux-functions.zsh

# Start a generated tmux session when launching an interactive shell outside tmux
if [[ $- == *i* ]]; then
  if command -v tmux >/dev/null 2>&1 && [[ -z "${TMUX:-}" ]]; then
    SESSION_NAME="session-$(date +%s)"
    tmux new-session -As "$SESSION_NAME"
    tmux set-option -t "$SESSION_NAME" @persistent 0
  fi
fi

cleanup_old_sessions
```

### Tmux Configuration

Add keybindings to your `~/.tmux.conf` (or copy from `examples/tmux.conf.snippet`):

```tmux
bind-key C-f run-shell "/usr/local/bin/tmux-sessionizer.sh"
bind-key m run-shell "~/.tmux-functions.zsh toggle"
bind-key R run-shell "~/.tmux-functions.zsh rename"
bind-key Q run-shell "~/.tmux-functions.zsh force-cleanup"
```

### i3 Integration

Add this to your i3 config (also in `examples/i3-config-snippet`) for fullscreen picker behavior:

```i3
bindsym $mod+backslash exec --no-startup-id "alacritty --class tmux-sessionizer -e zsh -lc 'tmux-sessionizer.sh; exec zsh'"
for_window [class="tmux-sessionizer"] fullscreen enable
```

### Examples Directory

Copy-paste-ready examples are available in `examples/`:

- `examples/tmux-sessionizer.conf.simple`
- `examples/tmux-sessionizer.conf.advanced`
- `examples/.tmux-sessionizer.example`
- `examples/i3-config-snippet`
- `examples/wm-hotkeys-guide.md`
- `examples/tmux.conf.snippet`

## Usage

### Basic Usage

Launch with configured search roots:

```bash
tmux-sessionizer.sh
```

Or pass directories directly for one-off sessions:

```bash
tmux-sessionizer.sh "$HOME/projects" "$HOME/work"
```

Workflow:

1. Run `tmux-sessionizer.sh`.
2. Select a directory in the `fzf` picker.
3. The script creates a session when needed and switches/attaches to it.

### Session Management

- Toggle persistence: `prefix + m`
- Rename generated session: `prefix + R`
- Force cleanup non-persistent generated sessions: `prefix + Q`

### Automatic Behavior

- Temporary sessions can be generated from shell startup logic
- Generated sessions can be marked persistent with `@persistent`
- Inactive temporary sessions can be cleaned up automatically
- Per-project `.tmux-sessionizer` config is loaded when creating a new session

## Testing

### Run the test suite

From the project root:

```bash
./test/run-tests.sh
```

Run only unit tests:

```bash
./test/run-tests.sh tests/unit/
```

Run only integration tests:

```bash
./test/run-tests.sh tests/integration/
```

Run a specific test file:

```bash
./test/run-tests.sh tests/unit/test_functions.bats
```

### Test dependencies

- `test/run-tests.sh` checks for system `bats` first.
- If missing, it downloads `bats-core` into `test/tmp/bats/`.
- It also downloads `bats-support` and `bats-assert` when missing.
- First run may require network access.

### Writing new tests

- Put shared helpers in `tests/test_helper/common.bash`.
- Add unit tests in `tests/unit/`.
- Add integration tests in `tests/integration/`.
- In BATS files, load shared helpers:

```bash
load '../test_helper/common.bash'
```

- Use `setup_mock_environment` and `teardown_mock_environment` for isolated tests.

### CI notes

- Use `./test/run-tests.sh` in CI for consistent local/CI behavior.
- Cache `test/tmp/bats/` between runs to avoid repeated downloads.
- Combine tests with lint checks:

```bash
shellcheck tmux-sessionizer.sh
shellcheck -s bash .tmux-functions.zsh
shellcheck test/run-tests.sh
```

## Troubleshooting

### Error: 'tmux' is required but not installed.

Install tmux and confirm it is on `PATH`:

```bash
command -v tmux
```

### Error: No valid directories to search.

- Check `~/.config/tmux-sessionizer.conf` for valid existing paths.
- Verify `SEARCH_DIRS` uses `:` separators.
- Try explicit directories:

```bash
tmux-sessionizer.sh "$HOME"
```

### Picker opens but no useful directories appear

- Confirm configured roots actually contain subdirectories.
- Check permissions on configured roots.
- If using `fd`, verify it is returning expected directories.

### Project layout file is not applied

- Confirm file is named exactly `.tmux-sessionizer` in project root.
- Verify tmux commands in that file are valid.
- Test manually:

```bash
tmux source-file /path/to/project/.tmux-sessionizer
```

### Keybindings do not work in tmux

- Confirm `~/.tmux-functions.zsh` exists and is executable by your shell.
- Reload tmux config after changes:

```bash
tmux source-file ~/.tmux.conf
```

## FAQ

### Do I need zsh to use tmux-sessionizer.sh?

No. The main script is Bash. `zsh` is only needed for the optional helper file `.tmux-functions.zsh`.

### Which config source wins if I set multiple?

Priority is: CLI directory args > `SEARCH_DIRS` > `~/.config/tmux-sessionizer.conf` > built-in defaults.

### Can I use this on macOS?

Yes, with tmux/fzf installed. If your environment defaults to Bash 3.2, use a newer Bash for full compatibility.

### What happens if I cancel the `fzf` picker?

The script exits cleanly without switching sessions.

### Where can I find ready-made config snippets?

Use the `examples/` directory in this repository for configuration and integration snippets.

## How It Works

1. Directory discovery:
   - Reads search roots from args/env/config/defaults
   - Uses `fd` when available, falls back to `find`
   - Aggregates and de-duplicates root directories plus first-level children
2. Selection and session naming:
   - Uses `fzf` for interactive selection (or auto-selects when only one option exists)
   - Converts selected directory basename to a tmux-safe session name
3. Session handling:
   - Creates session if missing, then switches or attaches
   - Loads project-level or home-level `.tmux-sessionizer` file when present

## Contributing

See `CONTRIBUTING.md` for setup, workflow, testing expectations, and submission guidelines.

## Acknowledgment

This script and setup was inspired by ThePrimeagen's tmux-sessionizer workflow.
