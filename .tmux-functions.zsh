#!/usr/bin/env zsh

# Function to check if a session name matches our generated format
is_generated_session() {
  local session_name="$1"
  [[ "$session_name" =~ ^session-[0-9]+$ ]]
}

# Function to toggle session persistence
toggle_session_persistence() {
  if [[ -n "$TMUX" ]]; then
    local session_name
    session_name="$(tmux display-message -p '#S')"
    
    # Get the current persistent value for this specific session
    local current_persistent
    current_persistent="$(tmux show-option -t "$session_name" -v "@persistent" 2>/dev/null || echo "0")"
    
    if [[ "$current_persistent" == "1" ]]; then
      tmux set-option -t "$session_name" @persistent 0
      tmux display-message "Session marked as temporary"
    else
      tmux set-option -t "$session_name" @persistent 1
      tmux display-message "Session marked as persistent"
    fi
  fi
}

# Function to rename session with persistence check
rename_session() {
  if [[ -n "$TMUX" ]]; then
    local current_name
    current_name="$(tmux display-message -p '#S')"
    
    if ! is_generated_session "$current_name"; then
      tmux display-message "Cannot rename manually created sessions"
      return 1
    fi
    
    tmux command-prompt -I "$current_name" "rename-session -- '%%'"
  fi
}

# Enhanced cleanup function that only affects generated sessions
cleanup_old_sessions() {
  local max_inactive=3600  # Time in seconds (1 hour)
  
  tmux list-sessions -F "#{session_name} #{session_attached} #{session_option:@persistent} #{session_activity}" 2>/dev/null | 
  while read -r session attached persistent activity; do
    if is_generated_session "$session"; then
      if [[ "$persistent" != "1" ]]; then
        current_time=$(date +%s)
        inactivity=$(( current_time - activity ))
        if (( inactivity > max_inactive )) && [[ "$attached" -eq 0 ]]; then
          tmux kill-session -t "$session"
        fi
      fi
    fi
  done
}

# Function to force cleanup non-persistent sessions regardless of time
force_cleanup_sessions() {
  tmux list-sessions -F "#{session_name} #{session_attached} #{session_option:@persistent}" 2>/dev/null | 
  while read -r session attached persistent; do
    if is_generated_session "$session"; then
      if [[ "$persistent" != "1" ]]; then
        tmux kill-session -t "$session"
        echo "Killed session: $session"
      fi
    fi
  done
}

# If script is called with arguments, execute the corresponding function
if [[ "$1" == "toggle" ]]; then
  toggle_session_persistence
elif [[ "$1" == "rename" ]]; then
  rename_session
elif [[ "$1" == "force-cleanup" ]]; then
  force_cleanup_sessions
fi
