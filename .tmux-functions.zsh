#!/usr/bin/env zsh

# ============================================================================
# tmux-sessionizer zsh helpers
# ============================================================================
#
# This helper script exposes convenience commands for operating on
# auto-generated tmux sessions (toggle persistence, safe rename, cleanup).

# Check whether a session matches the generated naming format.
# @param $1 Session name.
# @return 0 if generated, 1 otherwise.
is_generated_session() {
	local session_name="$1"
	[[ "$session_name" =~ ^session-[0-9]+$ ]]
}

# Toggle @persistent for the current tmux session.
# @return 0 on success or when not in tmux.
toggle_session_persistence() {
	if [[ -z "$TMUX" ]]; then
		return 0
	fi

	local session_name
	local current_persistent

	session_name="$(tmux display-message -p '#S')"
	current_persistent="$(tmux show-option -t "$session_name" -v "@persistent" 2>/dev/null || echo "0")"

	if [[ "$current_persistent" == "1" ]]; then
		tmux set-option -t "$session_name" @persistent 0
		tmux display-message "Session marked as temporary"
	else
		tmux set-option -t "$session_name" @persistent 1
		tmux display-message "Session marked as persistent"
	fi

	return 0
}

# Rename current session only when it is auto-generated.
# @return 0 on success, 1 on validation failure.
rename_session() {
	if [[ -z "$TMUX" ]]; then
		return 0
	fi

	local current_name
	current_name="$(tmux display-message -p '#S')"

	if ! is_generated_session "$current_name"; then
		tmux display-message "Cannot rename manually created sessions"
		return 1
	fi

	tmux command-prompt -I "$current_name" "rename-session -- '%%'"
	return 0
}

# Cleanup stale generated sessions that are unattached and non-persistent.
# @return 0 always.
cleanup_old_sessions() {
	local max_inactive=3600
	local session
	local attached
	local persistent
	local activity
	local current_time
	local inactivity

	tmux list-sessions -F "#{session_name} #{session_attached} #{session_option:@persistent} #{session_activity}" 2>/dev/null |
	while read -r session attached persistent activity; do
		if ! is_generated_session "$session"; then
			continue
		fi

		if [[ "$persistent" == "1" ]]; then
			continue
		fi

		current_time=$(date +%s)
		inactivity=$((current_time - activity))
		if ((inactivity > max_inactive)) && [[ "$attached" -eq 0 ]]; then
			tmux kill-session -t "$session"
		fi
	done

	return 0
}

# Force-delete all non-persistent generated sessions.
# @return 0 always.
force_cleanup_sessions() {
	local session
	local persistent

	tmux list-sessions -F "#{session_name} #{session_attached} #{session_option:@persistent}" 2>/dev/null |
	while read -r session _attached persistent; do
		if ! is_generated_session "$session"; then
			continue
		fi

		if [[ "$persistent" != "1" ]]; then
			tmux kill-session -t "$session"
			echo "Killed session: $session"
		fi
	done

	return 0
}

# Dispatch command when script is invoked directly.
# @param $1 Command name.
# @return 0 for handled commands, 1 for unknown command.
dispatch_tmux_sessionizer_command() {
	case "${1:-}" in
	toggle)
		toggle_session_persistence
		;;
	rename)
		rename_session
		;;
	force-cleanup)
		force_cleanup_sessions
		;;
	"" )
		return 0
		;;
	*)
		echo "Unknown command: $1" >&2
		return 1
		;;
	esac

	return 0
}

dispatch_tmux_sessionizer_command "${1:-}"
