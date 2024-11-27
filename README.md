# Tmux Sessionizer

A powerful tmux session management tool that allows quick navigation between projects and automatic session handling. It combines fuzzy finding capabilities with intelligent session management, including features for both persistent and temporary sessions.

## Features

- Fuzzy find and switch between project directories
- Automatic session creation and naming
- Support for persistent and temporary sessions
- Automatic cleanup of inactive temporary sessions
- Custom session configuration through `.tmux-sessionizer` files
- Integration with window managers (i3/i3-gaps)
- Directory search configuration via config file

## Prerequisites

The following tools are required:
- tmux
- fzf
- Either `fd` (preferred) or `find`
- zsh (for automatic session management features)

## Installation

1. Install the main script:
```bash
sudo curl -o /usr/local/bin/tmux-sessionizer.sh https://raw.githubusercontent.com/kyleorman/tmux-sessionizer/main/tmux-sessionizer.sh
sudo chmod +x /usr/local/bin/tmux-sessionizer.sh
```

2. Copy the function definitions to your home directory:
```bash
curl -o ~/.tmux-functions.zsh https://raw.githubusercontent.com/kyleorman/tmux-sessionizer/main/.tmux-functions.zsh
```

3. Set up the configuration (optional):
```bash
mkdir -p ~/.config
echo "$HOME\n$HOME/projects" > ~/.config/tmux-sessionizer.conf
```

## Configuration

### Directory Search Configuration

Create `~/.config/tmux-sessionizer.conf` to specify which directories to search:

```bash
$HOME
$HOME/projects
$HOME/work
# Add more directories as needed
```

Alternatively, you can set the `SEARCH_DIRS` environment variable:
```bash
export SEARCH_DIRS="$HOME:$HOME/projects:$HOME/work"
```

### Session-specific Configuration

Create a `.tmux-sessionizer` file in any project directory to define custom tmux configuration for that session:

```tmux
# Example .tmux-sessionizer
split-window -h -p 30
split-window -v -p 20
select-pane -L
```

### Shell Integration

Add to your `.zshrc`:
```zsh
# Source tmux functions
source ~/.tmux-functions.zsh

# Start a new tmux session with a generated name if not already inside tmux
if [[ $- == *i* ]]; then
  if command -v tmux > /dev/null 2>&1 && [ -z "$TMUX" ]; then
    SESSION_NAME="session-$(date +%s)"
    tmux new-session -As "$SESSION_NAME"
    tmux set-option -t "$SESSION_NAME" @persistent 0
  fi
fi

# Call the cleanup function
cleanup_old_sessions
```

### Tmux Configuration

Add to your `.tmux.conf`:
```tmux
# Toggle session persistence with 'm'
bind-key m if-shell '~/.tmux-functions.zsh toggle' '' ''

# Rename session with 'R' 
bind-key R if-shell '~/.tmux-functions.zsh rename' '' ''

# Force cleanup with 'Q'
bind-key Q if-shell '~/.tmux-functions.zsh force-cleanup' '' ''
```

### i3 Integration

Add to your i3 config:
```i3
# Tmux sessionizer
bindsym $mod+backslash exec --no-startup-id "alacritty -e /usr/bin/zsh -c 'source ~/.zshrc; /usr/local/bin/tmux-sessionizer.sh; exec /usr/bin/zsh'"
```

## Usage

### Basic Usage

1. Launch the sessionizer:
```bash
tmux-sessionizer.sh
```

2. Use fzf to select a directory
3. A tmux session will be created (if it doesn't exist) and you'll be switched to it

### Session Management

- **Toggle Persistence**: Press `prefix + m` to toggle whether a session should persist
- **Rename Session**: Press `prefix + R` to rename a generated session
- **Force Cleanup**: Press `prefix + Q` to force cleanup of all non-persistent sessions

### Automatic Features

- Temporary sessions are automatically created with a timestamp-based name
- Inactive temporary sessions are automatically cleaned up after 1 hour
- Session-specific configurations are automatically loaded when creating new sessions

## How It Works

1. **Directory Discovery**:
   - Searches configured directories for potential project locations
   - Uses `fd` if available, falls back to `find`
   - Respects configuration file and environment variable settings

2. **Session Management**:
   - Creates unique session names based on directory names
   - Supports both persistent and temporary sessions
   - Automatic cleanup of inactive temporary sessions
   - Custom session configurations through `.tmux-sessionizer` files

3. **Integration**:
   - Works seamlessly with tmux's session management
   - Integrates with window managers for quick access
   - Provides shell functions for enhanced management

## Contributing

Feel free to submit issues and pull requests to improve the tool.

## Acknowledgment

This script and setup was inspired by The Primeagen's tmux-sessionizer script
