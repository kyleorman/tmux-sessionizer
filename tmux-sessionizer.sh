#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and prevent errors in a pipeline
# from being masked.
set -euo pipefail
#set -x  # Uncomment this line to enable script debugging

# Functions ###############################################################

# Function: switch_to
# Description: Switches to the specified tmux session, attaching if necessary.
switch_to() {
    if [[ -n "${TMUX:-}" ]]; then
        # Inside tmux, switch the client to the target session
        tmux switch-client -t "$1"
    else
        # Outside tmux, attach to the target session
        tmux attach-session -t "$1"
    fi
}

# Function: has_session
# Description: Checks if a tmux session with the given name exists.
has_session() {
    tmux has-session -t "$1" 2>/dev/null
}

# Function: hydrate
# Description: Sources a tmux configuration file for the session if it exists.
hydrate() {
    if [ -f "$2/.tmux-sessionizer" ]; then
        tmux source-file "$2/.tmux-sessionizer"
    elif [ -f "$HOME/.tmux-sessionizer" ]; then
        tmux source-file "$HOME/.tmux-sessionizer"
    fi
}

# Function: check_command_exists
# Description: Checks if a command exists, and exits with an error if it does not.
check_command_exists() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: '$1' is required but not installed." >&2
        exit 1
    fi
}

# Main Script #############################################################

# Check for required commands
for cmd in tmux fzf; do
    check_command_exists "$cmd"
done

# Determine which directory listing command to use
if command -v fd &>/dev/null; then
    dir_cmd="fd"
else
    dir_cmd="find"
fi

# Determine the directories to search
# Default directories if nothing else is specified
search_dirs=(
    "$HOME"
    "$HOME/personal"
    "$HOME/personal/dev/env/.config"
)

# Override with config file if it exists
if [ -f "$HOME/.config/tmux-sessionizer.conf" ]; then
    # Clear default directories if config file exists
    search_dirs=()
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        # Expand environment variables in the line
        expanded_line=$(eval echo "$line")
        # Check if the expanded line is a valid directory
        if [ -d "$expanded_line" ]; then
            search_dirs+=("$expanded_line")
        fi
    done < "$HOME/.config/tmux-sessionizer.conf"
fi

# Override with environment variable if set
if [ -n "${SEARCH_DIRS:-}" ]; then
    IFS=':' read -r -a search_dirs <<< "$SEARCH_DIRS"
fi

# Override with command line arguments if provided
if [ $# -gt 0 ]; then
    search_dirs=()
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            search_dirs+=("$dir")
        else
            echo "Warning: '$dir' is not a directory or does not exist." >&2
        fi
    done
fi

# Ensure at least one directory exists
if [ ${#search_dirs[@]} -eq 0 ]; then
    echo "Error: No valid directories to search." >&2
    exit 1
fi

# Build the list of all directories to search
all_dirs=()
for search_dir in "${search_dirs[@]}"; do
    # Add the root directory itself
    all_dirs+=("$search_dir")
    
    # Add subdirectories
    if [ "$dir_cmd" = "fd" ]; then
        while IFS= read -r dir; do
            all_dirs+=("$dir")
        done < <(fd --type d --max-depth 1 --hidden --exclude .git . "$search_dir" 2>/dev/null || true)
    else
        while IFS= read -r dir; do
            all_dirs+=("$dir")
        done < <(find "$search_dir" -mindepth 1 -maxdepth 1 -type d -not -path '*/\.*' 2>/dev/null || true)
    fi
done

# Remove duplicates and sort
readarray -t sorted_dirs < <(printf '%s\n' "${all_dirs[@]}" | sort -u)

# Select directory using fzf
if [[ ${#sorted_dirs[@]} -eq 1 ]]; then
    selected="${sorted_dirs[0]}"
else
    selected=$(printf '%s\n' "${sorted_dirs[@]}" | fzf --height 40% --reverse --border)
fi

# Exit if no directory was selected
if [[ -z ${selected:-} ]]; then
    echo "No directory selected."
    exit 0
fi

# Generate a safe session name from the selected directory
selected_name=$(basename "$selected" | tr . _ | tr -cd '[:alnum:]_')

# Ensure the session name is not empty
if [[ -z $selected_name ]]; then
    echo "Error: Session name is empty after sanitization." >&2
    exit 1
fi

# Create or attach to the tmux session
if [[ -z "${TMUX:-}" ]]; then
    # Not inside tmux
    if ! has_session "$selected_name"; then
        tmux new-session -ds "$selected_name" -c "$selected"
        hydrate "$selected_name" "$selected"
    fi
    tmux attach-session -t "$selected_name"
else
    # Inside tmux
    if ! has_session "$selected_name"; then
        tmux new-session -ds "$selected_name" -c "$selected"
        hydrate "$selected_name" "$selected"
    fi
    tmux switch-client -t "$selected_name"
fi
