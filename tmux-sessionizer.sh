#!/usr/bin/env bash

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
	printf 'Error: tmux-sessionizer requires bash 4.0 or higher (found %s).\n' "${BASH_VERSION:-unknown}" >&2
	exit 3
fi

set -euo pipefail

# ============================================================================
# Header
# ============================================================================

VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="$HOME/.config/tmux-sessionizer.conf"
TEMPLATES_DIR="${TMUX_SESSIONIZER_TEMPLATES_DIR:-$HOME/.config/tmux-sessionizer/templates}"

readonly TMUX_MIN_VERSION="2.6"
readonly TMUX_SESSION_NAME_MAX_LENGTH=128

# ============================================================================
# Exit Codes
# ============================================================================
#
# 0   Success
# 1   General error
# 2   Invalid usage / unsupported CLI flags
# 3   Missing dependency
# 4   Configuration and directory validation errors
# 5   tmux interaction errors
# 130 User interrupted selection (Ctrl-C)

readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_USAGE=2
readonly EXIT_MISSING_DEPENDENCY=3
readonly EXIT_CONFIG_ERROR=4
readonly EXIT_TMUX_ERROR=5
readonly EXIT_INTERRUPTED=130

# ============================================================================
# Utility Functions
# ============================================================================

# Print a standardized error line to stderr.
# @param $1 Human-readable error message.
# @param $2 Exit code associated with the error (optional).
# @return EXIT_SUCCESS (always prints; does not terminate).
error() {
	local message="$1"
	local exit_code="${2:-$EXIT_GENERAL_ERROR}"

	printf 'Error: %s [context: %s, exit_code: %s]\n' "$message" "$SCRIPT_NAME" "$exit_code" >&2
}

# Print a standardized warning line to stderr.
# @param $1 Human-readable warning message.
# @return EXIT_SUCCESS.
warn() {
	local message="$1"

	printf 'Warning: %s [context: %s]\n' "$message" "$SCRIPT_NAME" >&2
}

# Print an error and terminate the script.
# @param $1 Human-readable error message.
# @param $2 Exit code for process termination (optional).
# @return Does not return; exits process.
die() {
	local message="$1"
	local exit_code="${2:-$EXIT_GENERAL_ERROR}"

	error "$message" "$exit_code"
	exit "$exit_code"
}

# Provide install guidance for a missing dependency.
# @param $1 Command name.
# @return EXIT_SUCCESS.
dependency_hint() {
	case "$1" in
	tmux)
		printf '%s\n' "Install tmux: https://github.com/tmux/tmux/wiki/Installing"
		;;
	fzf)
		printf '%s\n' "Install fzf: https://github.com/junegunn/fzf#installation"
		;;
	fd | fdfind)
		printf '%s\n' "Install fd: https://github.com/sharkdp/fd#installation"
		;;
	*)
		printf '%s\n' "Install '$1' and ensure it is available in PATH."
		;;
	esac
}

# Join a list of paths into a readable semicolon-delimited string.
# @param $@ Path values.
# @return EXIT_SUCCESS.
format_path_list() {
	local joined=""
	local item

	if [[ $# -eq 0 ]]; then
		printf '%s\n' "(none)"
		return "$EXIT_SUCCESS"
	fi

	for item in "$@"; do
		if [[ -z "$joined" ]]; then
			joined="$item"
		else
			joined+="; $item"
		fi
	done

	printf '%s\n' "$joined"
	return "$EXIT_SUCCESS"
}

# ============================================================================
# Core Functions
# ============================================================================

# Attach or switch the current tmux client to a target session.
# @param $1 Target tmux session name.
# @return EXIT_SUCCESS on success; exits with EXIT_TMUX_ERROR on failure.
switch_to() {
	local session_name="$1"

	if [[ -n "${TMUX:-}" ]]; then
		if ! tmux switch-client -t "$session_name"; then
			die "Failed to switch tmux client to session '$session_name'. Ensure tmux is running and the session exists." "$EXIT_TMUX_ERROR"
		fi
	else
		if ! tmux attach-session -t "$session_name"; then
			die "Failed to attach to tmux session '$session_name'. Ensure tmux is running and the session exists." "$EXIT_TMUX_ERROR"
		fi
	fi

	return "$EXIT_SUCCESS"
}

# Check if a tmux session exists.
# @param $1 Session name to test.
# @return 0 when session exists, 1 otherwise.
has_session() {
	tmux has-session -t "$1" 2>/dev/null
}

# Source project or home tmux sessionizer config for new sessions.
# @param $1 Session name (kept for interface stability).
# @param $2 Selected project directory.
# @return EXIT_SUCCESS.
hydrate() {
	local session_name="$1"
	local selected_dir="$2"

	if [[ -f "$selected_dir/.tmux-sessionizer" ]]; then
		if ! tmux source-file "$selected_dir/.tmux-sessionizer"; then
			warn "Failed to source project tmux config: $selected_dir/.tmux-sessionizer"
		fi
	elif [[ -f "$HOME/.tmux-sessionizer" ]]; then
		if ! tmux source-file "$HOME/.tmux-sessionizer"; then
			warn "Failed to source home tmux config: $HOME/.tmux-sessionizer"
		fi
	fi

	# Intentionally keep session_name consumed for interface stability.
	: "$session_name"
	return "$EXIT_SUCCESS"
}

# Ensure a required command is available in PATH.
# @param $1 Command name.
# @return EXIT_SUCCESS on success; exits with EXIT_MISSING_DEPENDENCY on failure.
check_command_exists() {
	if ! command -v "$1" &>/dev/null; then
		die "'$1' is required but not installed. $(dependency_hint "$1")" "$EXIT_MISSING_DEPENDENCY"
	fi

	return "$EXIT_SUCCESS"
}

# Validate tmux version when version output is parseable.
# @return EXIT_SUCCESS; exits with EXIT_MISSING_DEPENDENCY when version is too old.
check_tmux_version() {
	local version_output
	local major
	local minor
	local version_number

	version_output=$(tmux -V 2>/dev/null || true)
	if [[ -z "$version_output" ]]; then
		warn "Could not determine tmux version from 'tmux -V'; continuing."
		return "$EXIT_SUCCESS"
	fi

	if [[ "$version_output" =~ ^tmux[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
		major="${BASH_REMATCH[1]}"
		minor="${BASH_REMATCH[2]}"
		version_number=$((major * 100 + minor))
		if ((version_number < 206)); then
			die "tmux ${major}.${minor} is too old. tmux-sessionizer requires tmux ${TMUX_MIN_VERSION}+ for full compatibility." "$EXIT_MISSING_DEPENDENCY"
		fi
		return "$EXIT_SUCCESS"
	fi

	warn "Unable to parse tmux version output '$version_output'; continuing."
	return "$EXIT_SUCCESS"
}

# Ensure tmux server is reachable and usable.
# @return EXIT_SUCCESS; exits with EXIT_TMUX_ERROR on connectivity failures.
ensure_tmux_server() {
	local start_output
	local list_output

	if ! start_output=$(tmux start-server 2>&1); then
		die "Failed to start tmux server. ${start_output:-Check tmux socket permissions and TMUX_TMPDIR.}" "$EXIT_TMUX_ERROR"
	fi

	list_output=$(tmux list-sessions 2>&1 || true)
	if [[ "$list_output" == *"failed to connect"* || "$list_output" == *"Permission denied"* ]]; then
		die "Cannot communicate with tmux server after startup attempt: $list_output" "$EXIT_TMUX_ERROR"
	fi

	return "$EXIT_SUCCESS"
}

# ============================================================================
# Configuration Functions
# ============================================================================

# Trim leading and trailing whitespace from a string.
# @param $1 Input string.
# @return Trimmed string via stdout.
trim_whitespace() {
	local value="$1"

	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"

	printf '%s\n' "$value"
}

# Normalize directory paths by removing trailing slash except root.
# @param $1 Path to normalize.
# @return Normalized path via stdout.
normalize_directory() {
	local normalized

	normalized="${1%/}"
	if [[ -z "$normalized" ]]; then
		normalized='/'
	fi

	printf '%s\n' "$normalized"
}

# Detect unsupported command-substitution syntax in user-provided paths.
# @param $1 Raw config entry.
# @return 0 when unsupported syntax is detected, 1 otherwise.
has_unsupported_env_syntax() {
	[[ "$1" == *\$\(* || "$1" == *\`* ]]
}

# Expand ~ and simple environment variable tokens in path entries.
# @param $1 Raw config or CLI path entry.
# @return Expanded path via stdout.
expand_directory_entry() {
	local expanded
	local token
	local variable_name
	local variable_value
	local next_value

	expanded=$(trim_whitespace "$1")

	if [[ "$expanded" == "~" ]]; then
		expanded="$HOME"
	elif [[ "$expanded" == \~/* ]]; then
		expanded="$HOME/${expanded#~/}"
	fi

	while [[ "$expanded" =~ (\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*) ]]; do
		token="${BASH_REMATCH[1]}"

		if [[ "$token" == \$\{* ]]; then
			variable_name="${token:2:${#token}-3}"
		else
			variable_name="${token:1}"
		fi

		variable_value="${!variable_name-}"
		next_value="${expanded/$token/$variable_value}"
		if [[ "$next_value" == "$expanded" ]]; then
			break
		fi

		expanded="$next_value"
	done

	printf '%s\n' "$expanded"
}

# Validate config file and SEARCH_DIRS content without creating sessions.
# @return EXIT_SUCCESS when no issues are found, EXIT_CONFIG_ERROR otherwise.
validate_config() {
	local issues=0
	local line
	local expanded
	local normalized
	local env_dir
	local -a env_dirs
	local -A seen_dirs=()

	echo "Validating tmux-sessionizer configuration..."

	if [[ ! -e "$CONFIG_FILE" ]]; then
		echo "Info: Config file not found at $CONFIG_FILE (defaults will be used)."
	elif [[ ! -r "$CONFIG_FILE" ]]; then
		error "Config file exists but is not readable: $CONFIG_FILE" "$EXIT_CONFIG_ERROR"
		issues=$((issues + 1))
	else
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

			if has_unsupported_env_syntax "$line"; then
				warn "Unsupported environment format in config entry: $line"
				issues=$((issues + 1))
				continue
			fi

			expanded=$(expand_directory_entry "$line")
			if [[ ! -d "$expanded" ]]; then
				warn "Config directory does not exist: $expanded"
				issues=$((issues + 1))
				continue
			fi

			if [[ ! -r "$expanded" || ! -x "$expanded" ]]; then
				warn "Config directory is not accessible: $expanded"
				issues=$((issues + 1))
				continue
			fi

			normalized=$(normalize_directory "$expanded")
			if [[ -n "${seen_dirs[$normalized]:-}" ]]; then
				warn "Duplicate directory entry in config: $expanded"
				issues=$((issues + 1))
			else
				seen_dirs["$normalized"]=1
			fi
		done <"$CONFIG_FILE"
	fi

	if [[ -n "${SEARCH_DIRS:-}" ]]; then
		if [[ "$SEARCH_DIRS" == *"::"* || "$SEARCH_DIRS" == :* || "$SEARCH_DIRS" == *: ]]; then
			warn "SEARCH_DIRS contains empty entries (leading, trailing, or repeated ':')."
			issues=$((issues + 1))
		fi

		IFS=':' read -r -a env_dirs <<<"$SEARCH_DIRS"
		for env_dir in "${env_dirs[@]}"; do
			[[ -z "$env_dir" ]] && continue

			if has_unsupported_env_syntax "$env_dir"; then
				warn "Unsupported environment format in SEARCH_DIRS entry: $env_dir"
				issues=$((issues + 1))
				continue
			fi

			expanded=$(expand_directory_entry "$env_dir")
			if [[ ! -d "$expanded" ]]; then
				warn "SEARCH_DIRS entry is not a directory: $expanded"
				issues=$((issues + 1))
				continue
			fi

			if [[ ! -r "$expanded" || ! -x "$expanded" ]]; then
				warn "SEARCH_DIRS entry is not accessible: $expanded"
				issues=$((issues + 1))
				continue
			fi

			normalized=$(normalize_directory "$expanded")
			if [[ -n "${seen_dirs[$normalized]:-}" ]]; then
				warn "Duplicate directory entry detected: $expanded"
				issues=$((issues + 1))
			else
				seen_dirs["$normalized"]=1
			fi
		done
	fi

	if [[ $issues -eq 0 ]]; then
		echo "Validation successful: no issues found."
		return "$EXIT_SUCCESS"
	fi

	error "Validation failed: ${issues} issue(s) found." "$EXIT_CONFIG_ERROR"
	return "$EXIT_CONFIG_ERROR"
}

# Load default search directories used when no overrides are provided.
# @return EXIT_SUCCESS.
load_defaults() {
	search_dirs=(
		"$HOME"
		"$HOME/personal"
		"$HOME/personal/dev/env/.config"
	)
	attempted_dirs=("${search_dirs[@]}")
	return "$EXIT_SUCCESS"
}

# Load directory list from CONFIG_FILE and replace defaults when present.
# @return EXIT_SUCCESS.
load_config_file() {
	local line
	local expanded_line

	if [[ ! -f "$CONFIG_FILE" ]]; then
		return "$EXIT_SUCCESS"
	fi

	search_dirs=()
	attempted_dirs=()

	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

		if has_unsupported_env_syntax "$line"; then
			warn "Unsupported environment format in config entry: $line"
			continue
		fi

		expanded_line=$(expand_directory_entry "$line")
		[[ -z "$expanded_line" ]] && continue
		attempted_dirs+=("$expanded_line")

		if [[ ! -d "$expanded_line" ]]; then
			warn "Config entry is not a directory or does not exist: $expanded_line"
			continue
		fi

		if [[ ! -r "$expanded_line" || ! -x "$expanded_line" ]]; then
			warn "Config directory is not accessible: $expanded_line"
			continue
		fi

		search_dirs+=("$expanded_line")
	done <"$CONFIG_FILE"

	return "$EXIT_SUCCESS"
}

# Apply SEARCH_DIRS override when set.
# @return EXIT_SUCCESS.
apply_env_overrides() {
	local -a env_search_dirs
	local env_dir
	local expanded_line

	if [[ -z "${SEARCH_DIRS:-}" ]]; then
		return "$EXIT_SUCCESS"
	fi

	search_dirs=()
	attempted_dirs=()

	IFS=':' read -r -a env_search_dirs <<<"$SEARCH_DIRS"
	for env_dir in "${env_search_dirs[@]}"; do
		[[ -z "$env_dir" ]] && continue

		if has_unsupported_env_syntax "$env_dir"; then
			warn "Unsupported environment format in SEARCH_DIRS entry: $env_dir"
			continue
		fi

		expanded_line=$(expand_directory_entry "$env_dir")
		[[ -z "$expanded_line" ]] && continue
		attempted_dirs+=("$expanded_line")

		if [[ ! -d "$expanded_line" ]]; then
			warn "SEARCH_DIRS entry is not a directory or does not exist: $expanded_line"
			continue
		fi

		if [[ ! -r "$expanded_line" || ! -x "$expanded_line" ]]; then
			warn "SEARCH_DIRS entry is not accessible: $expanded_line"
			continue
		fi

		search_dirs+=("$expanded_line")
	done

	return "$EXIT_SUCCESS"
}

# Apply CLI directory overrides when positional paths are provided.
# @return EXIT_SUCCESS.
apply_cli_overrides() {
	local dir
	local expanded_line

	if [[ ${#cli_dirs[@]} -eq 0 ]]; then
		return "$EXIT_SUCCESS"
	fi

	search_dirs=()
	attempted_dirs=()

	for dir in "${cli_dirs[@]}"; do
		expanded_line=$(expand_directory_entry "$dir")
		[[ -z "$expanded_line" ]] && continue
		attempted_dirs+=("$expanded_line")

		if [[ -d "$expanded_line" ]]; then
			if [[ ! -r "$expanded_line" || ! -x "$expanded_line" ]]; then
				warn "'$expanded_line' exists but is not accessible (permission denied)."
				continue
			fi

			search_dirs+=("$expanded_line")
		else
			warn "'$expanded_line' is not a directory or does not exist."
		fi
	done

	return "$EXIT_SUCCESS"
}

# Ensure configuration resolution produced at least one usable directory.
# @return EXIT_SUCCESS; exits with EXIT_CONFIG_ERROR when empty.
validate_search_dirs() {
	if [[ ${#search_dirs[@]} -eq 0 ]]; then
		die "No valid directories to search. Tried: $(format_path_list "${attempted_dirs[@]}"). Checked CLI args, SEARCH_DIRS, config (${CONFIG_FILE}), and defaults." "$EXIT_CONFIG_ERROR"
	fi

	return "$EXIT_SUCCESS"
}

# Run full configuration resolution pipeline in precedence order.
# @return EXIT_SUCCESS.
load_configuration() {
	load_defaults
	load_config_file
	apply_env_overrides
	apply_cli_overrides
	validate_search_dirs
	return "$EXIT_SUCCESS"
}

# ============================================================================
# Session Management Functions
# ============================================================================

# Convert a filesystem name into a tmux-safe session token.
# @param $1 Candidate directory basename.
# @return Sanitized session token via stdout.
sanitize_session_name() {
	printf '%s' "$1" | tr . _ | tr -cd '[:alnum:]_'
}

# Enforce tmux session name length, appending a deterministic hash when needed.
# @param $1 Candidate session name.
# @param $2 Seed used for hash derivation.
# @return Fitted session name via stdout; non-zero when no valid name can be produced.
fit_session_name() {
	local candidate="$1"
	local seed="$2"
	local hash
	local prefix_len

	if [[ -z "$candidate" ]]; then
		return 1
	fi

	if ((${#candidate} <= TMUX_SESSION_NAME_MAX_LENGTH)); then
		printf '%s\n' "$candidate"
		return "$EXIT_SUCCESS"
	fi

	hash=$(printf '%s' "$seed" | cksum)
	hash=${hash%% *}
	hash=${hash:0:6}
	prefix_len=$((TMUX_SESSION_NAME_MAX_LENGTH - ${#hash} - 1))
	if ((prefix_len < 1)); then
		return 1
	fi

	printf '%s_%s\n' "${candidate:0:prefix_len}" "$hash"
	return "$EXIT_SUCCESS"
}

# Look up the working directory associated with an existing session.
# @param $1 Session name.
# @return Session path via stdout when available.
session_directory() {
	tmux display-message -p -t "$1" "#{session_path}" 2>/dev/null || true
}

# Compare a session's tracked directory to a target path.
# @param $1 Session name.
# @param $2 Target directory path.
# @return 0 when directories match, 1 otherwise.
session_matches_directory() {
	local existing_dir

	existing_dir=$(session_directory "$1")
	if [[ -z "$existing_dir" ]]; then
		return 1
	fi

	[[ "$(normalize_directory "$existing_dir")" == "$(normalize_directory "$2")" ]]
}

# Resolve a collision-safe session name for the selected directory.
#
# Collision strategy:
# 1) basename
# 2) parent_basename + basename
# 3) basename + short hash
# 4) incrementing numeric suffix
#
# @param $1 Selected directory.
# @return Resolved session name via stdout; non-zero when generation fails.
resolve_session_name() {
	local selected_dir="$1"
	local base_name
	local parent_name
	local candidate
	local suffixed_candidate
	local hash
	local suffix
	local max_suffix_attempts=100
	local fallback_seed
	local fallback_hash
	local fallback_candidate
	local fallback_attempt

	base_name=$(sanitize_session_name "$(basename "$selected_dir")")
	base_name=$(fit_session_name "$base_name" "$selected_dir") || return 1
	if [[ -z "$base_name" ]]; then
		return 1
	fi

	if ! has_session "$base_name" || session_matches_directory "$base_name" "$selected_dir"; then
		printf '%s\n' "$base_name"
		return "$EXIT_SUCCESS"
	fi

	parent_name=$(sanitize_session_name "$(basename "$(dirname "$selected_dir")")")
	if [[ -n "$parent_name" ]]; then
		candidate="${parent_name}_${base_name}"
		candidate=$(fit_session_name "$candidate" "$selected_dir") || return 1
		if ! has_session "$candidate" || session_matches_directory "$candidate" "$selected_dir"; then
			printf '%s\n' "$candidate"
			return "$EXIT_SUCCESS"
		fi
	fi

	hash=$(printf '%s' "$selected_dir" | cksum)
	hash=${hash%% *}
	hash=${hash:0:4}
	candidate="${base_name}_${hash}"
	candidate=$(fit_session_name "$candidate" "$selected_dir") || return 1

	if ! has_session "$candidate" || session_matches_directory "$candidate" "$selected_dir"; then
		printf '%s\n' "$candidate"
		return "$EXIT_SUCCESS"
	fi

	suffix=1
	while ((suffix <= max_suffix_attempts)); do
		suffixed_candidate=$(fit_session_name "${candidate}_${suffix}" "${selected_dir}_${suffix}") || return 1
		if ! has_session "$suffixed_candidate" || session_matches_directory "$suffixed_candidate" "$selected_dir"; then
			printf '%s\n' "$suffixed_candidate"
			return "$EXIT_SUCCESS"
		fi
		suffix=$((suffix + 1))
	done

	warn "Session name collision limit reached after ${max_suffix_attempts} attempts for '$selected_dir'; using hash fallback."
	for ((fallback_attempt = 1; fallback_attempt <= 10; fallback_attempt++)); do
		fallback_seed="${selected_dir}_${fallback_attempt}_$(date +%s)_$$"
		fallback_hash=$(printf '%s' "$fallback_seed" | cksum)
		fallback_hash=${fallback_hash%% *}
		fallback_hash=${fallback_hash:0:8}
		fallback_candidate=$(fit_session_name "${base_name}_${fallback_hash}" "$fallback_seed") || return 1
		if ! has_session "$fallback_candidate" || session_matches_directory "$fallback_candidate" "$selected_dir"; then
			printf '%s\n' "$fallback_candidate"
			return "$EXIT_SUCCESS"
		fi
	done

	return 1
}

# Pick a template name based on common project marker files.
# @param $1 Project directory.
# @return Template key via stdout.
detect_template_name() {
	local project_dir="$1"

	if [[ -f "$project_dir/requirements.txt" || -f "$project_dir/pyproject.toml" ]]; then
		printf '%s\n' "python"
		return "$EXIT_SUCCESS"
	fi

	if [[ -f "$project_dir/package.json" ]]; then
		printf '%s\n' "node"
		return "$EXIT_SUCCESS"
	fi

	if [[ -f "$project_dir/Cargo.toml" ]]; then
		printf '%s\n' "rust"
		return "$EXIT_SUCCESS"
	fi

	if [[ -f "$project_dir/go.mod" ]]; then
		printf '%s\n' "go"
		return "$EXIT_SUCCESS"
	fi

	printf '%s\n' "default"
	return "$EXIT_SUCCESS"
}

# Resolve an on-disk template path from a template key.
# @param $1 Template key.
# @return Template file path via stdout; non-zero when unresolved.
resolve_template_file() {
	local template_name="$1"
	local candidate

	for candidate in "$TEMPLATES_DIR/$template_name" "$TEMPLATES_DIR/${template_name}.template"; do
		if [[ -f "$candidate" ]]; then
			printf '%s\n' "$candidate"
			return "$EXIT_SUCCESS"
		fi
	done

	return 1
}

# Apply the best matching tmux template to a new session.
# @param $1 Session name.
# @param $2 Project directory.
# @return EXIT_SUCCESS.
apply_session_template() {
	local session_name="$1"
	local project_dir="$2"
	local template_name
	local template_file

	if [[ ! -d "$TEMPLATES_DIR" ]]; then
		return "$EXIT_SUCCESS"
	fi

	template_name=$(detect_template_name "$project_dir")
	template_file=""
	if template_file=$(resolve_template_file "$template_name"); then
		:
	elif [[ "$template_name" != "default" ]] && template_file=$(resolve_template_file "default"); then
		:
	else
		return "$EXIT_SUCCESS"
	fi

	if ! tmux source-file "$template_file"; then
		warn "Failed to apply template '$template_file' to session '$session_name'."
	fi

	return "$EXIT_SUCCESS"
}

# Create a session for the selected directory when it does not already exist.
# @param $1 Session name.
# @param $2 Selected directory.
# @return EXIT_SUCCESS; exits with EXIT_TMUX_ERROR on creation failure.
create_session_if_missing() {
	local session_name="$1"
	local selected_dir="$2"

	if ! has_session "$session_name"; then
		if ! tmux new-session -ds "$session_name" -c "$selected_dir"; then
			die "Failed to create tmux session '$session_name' for directory '$selected_dir'. Check tmux socket permissions and directory accessibility." "$EXIT_TMUX_ERROR"
		fi
		apply_session_template "$session_name" "$selected_dir"
		hydrate "$session_name" "$selected_dir"
	fi

	return "$EXIT_SUCCESS"
}

# Resolve GNU coreutils timeout command name across platforms.
# @return timeout command name via stdout; non-zero if unavailable.
resolve_timeout_command() {
	if command -v timeout &>/dev/null; then
		printf '%s\n' "timeout"
		return "$EXIT_SUCCESS"
	fi

	if command -v gtimeout &>/dev/null; then
		printf '%s\n' "gtimeout"
		return "$EXIT_SUCCESS"
	fi

	return 1
}

# Discover first-level subdirectories beneath a search root.
#
# This path scan is intentionally defensive: inaccessible roots are skipped,
# discovery errors are downgraded to warnings, and optional timeout wrappers
# avoid hanging on slow or stale network filesystems.
#
# @param $1 Search root directory.
# @param $2 Discovery command ('fd' or 'find').
# @return EXIT_SUCCESS (warnings emitted for recoverable issues).
discover_subdirectories() {
	local search_dir="$1"
	local discover_cmd="$2"
	local timeout_seconds="${TMUX_SESSIONIZER_SCAN_TIMEOUT_SECONDS:-6}"
	local timeout_cmd
	local -a cmd
	local status

	if [[ ! -d "$search_dir" ]]; then
		warn "Skipping search path that is not a directory: $search_dir"
		return "$EXIT_SUCCESS"
	fi

	if [[ ! -r "$search_dir" || ! -x "$search_dir" ]]; then
		warn "Skipping inaccessible search directory (permission denied): $search_dir"
		return "$EXIT_SUCCESS"
	fi

	if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$timeout_seconds" -le 0 ]]; then
		timeout_seconds=6
	fi

	if [[ "$discover_cmd" == "fd" ]]; then
		cmd=(fd --type d --max-depth 1 --hidden --exclude .git . "$search_dir")
	else
		cmd=(find "$search_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.git')
	fi

	if timeout_cmd=$(resolve_timeout_command); then
		set +e
		"$timeout_cmd" "${timeout_seconds}s" "${cmd[@]}" 2>/dev/null
		status=$?
		set -e

		if [[ $status -eq 124 || $status -eq 137 ]]; then
			warn "Directory scan timed out after ${timeout_seconds}s: $search_dir (network filesystem may be slow)"
			return "$EXIT_SUCCESS"
		fi

		if [[ $status -ne 0 ]]; then
			warn "Failed to list subdirectories in: $search_dir"
			return "$EXIT_SUCCESS"
		fi

		return "$EXIT_SUCCESS"
	fi

	if ! "${cmd[@]}" 2>/dev/null; then
		warn "Failed to list subdirectories in: $search_dir"
	fi

	return "$EXIT_SUCCESS"
}

# ============================================================================
# Main Logic
# ============================================================================

# Print CLI usage, options, environment variables, and exit codes.
# @return EXIT_SUCCESS.
print_help() {
	cat <<EOF
Usage:
  tmux-sessionizer.sh [options] [directory ...]

Description:
  Select a project directory and attach to an existing tmux session or create one.
  Directory precedence is: command-line directories, SEARCH_DIRS, config file, defaults.

Runtime Requirements:
  bash 4.0+
  tmux, fzf, and fd (preferred) or find

Options:
  -h, --help       Show this help text and exit
  -v, --version    Show the installed version and exit
  --validate       Validate config/environment and exit

Examples:
  ./tmux-sessionizer.sh
  ./tmux-sessionizer.sh ~/work ~/personal
  SEARCH_DIRS="$HOME/work:$HOME/personal" ./tmux-sessionizer.sh

Exit Codes:
  0    Success (EXIT_SUCCESS)
  1    General error (EXIT_GENERAL_ERROR)
  2    Invalid usage (EXIT_INVALID_USAGE)
  3    Missing dependency (EXIT_MISSING_DEPENDENCY)
  4    Configuration error (EXIT_CONFIG_ERROR)
  5    tmux error (EXIT_TMUX_ERROR)
  130  Interrupted (EXIT_INTERRUPTED)

Environment Variables:
  SEARCH_DIRS                         Colon-separated directory list override
  TMUX_SESSIONIZER_FZF_PREVIEW        Set to 0 to disable fzf preview
  TMUX_SESSIONIZER_FZF_PREVIEW_WINDOW fzf preview layout (default: right:60%:wrap)
  TMUX_SESSIONIZER_FZF_HEIGHT         Override fzf height (default: auto - 40% in tmux, 100% outside)
  TMUX_SESSIONIZER_TEMPLATES_DIR      Template directory (default: ~/.config/tmux-sessionizer/templates)

Config File:
  ${CONFIG_FILE}

Template Directory:
  ${TEMPLATES_DIR}
EOF
}

# Print version and tmux compatibility floor.
# @return EXIT_SUCCESS.
print_version() {
	printf 'tmux-sessionizer %s (requires tmux >= %s)\n' "$VERSION" "$TMUX_MIN_VERSION"
}

# Parse command-line options and positional directory overrides.
# @param $@ CLI arguments.
# @return EXIT_SUCCESS or EXIT_INVALID_USAGE.
parse_arguments() {
	show_help=0
	show_version=0
	validate_only=0
	cli_dirs=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help=1
			;;
		-v | --version)
			show_version=1
			;;
		--validate)
			validate_only=1
			;;
		--)
			shift
			while [[ $# -gt 0 ]]; do
				cli_dirs+=("$1")
				shift
			done
			break
			;;
		-*)
			error "Unknown option: $1. Use --help to view supported flags." "$EXIT_INVALID_USAGE"
			return "$EXIT_INVALID_USAGE"
			;;
		*)
			cli_dirs+=("$1")
			;;
		esac
		shift
	done

	return "$EXIT_SUCCESS"
}

# Choose the filesystem discovery backend for directory listing.
# @return EXIT_SUCCESS; exits with EXIT_MISSING_DEPENDENCY when neither fd/find is available.
select_directory_command() {
	if command -v fd &>/dev/null; then
		dir_cmd="fd"
	elif command -v find &>/dev/null; then
		dir_cmd="find"
	else
		die "Neither 'fd' nor 'find' is available for directory discovery. $(dependency_hint "fd")" "$EXIT_MISSING_DEPENDENCY"
	fi

	return "$EXIT_SUCCESS"
}

# Validate required dependencies and tmux runtime state.
# @return EXIT_SUCCESS.
check_dependencies() {
	local cmd

	for cmd in tmux fzf; do
		check_command_exists "$cmd"
	done

	check_tmux_version
	ensure_tmux_server
	select_directory_command

	return "$EXIT_SUCCESS"
}

# Build and deduplicate the candidate directory list for selection.
# @return EXIT_SUCCESS; exits with EXIT_CONFIG_ERROR when no directories are available.
build_directory_index() {
	local -a all_dirs=()
	local search_dir
	local discovered_dir

	for search_dir in "${search_dirs[@]}"; do
		all_dirs+=("$search_dir")
		while IFS= read -r discovered_dir; do
			[[ -z "$discovered_dir" ]] && continue
			all_dirs+=("$discovered_dir")
		done < <(discover_subdirectories "$search_dir" "$dir_cmd")
	done

	readarray -t sorted_dirs < <(printf '%s\n' "${all_dirs[@]}" | sort -u)
	if [[ ${#sorted_dirs[@]} -eq 0 ]]; then
		die "No directories found after scanning. Tried search roots: $(format_path_list "${search_dirs[@]}")." "$EXIT_CONFIG_ERROR"
	fi

	return "$EXIT_SUCCESS"
}

# Run interactive directory selection (or auto-select single candidate).
# @return EXIT_SUCCESS on normal flow, EXIT_INTERRUPTED on Ctrl-C.
select_directory() {
	local -a fzf_args
	local fzf_height
	local preview_cmd
	local fzf_status

	# Determine fzf height based on context:
	# - Inside tmux: 40% (popup style)
	# - Outside tmux: 100% (full terminal)
	# - Override: TMUX_SESSIONIZER_FZF_HEIGHT
	if [[ -n "${TMUX_SESSIONIZER_FZF_HEIGHT:-}" ]]; then
		fzf_height="$TMUX_SESSIONIZER_FZF_HEIGHT"
	elif [[ -n "${TMUX:-}" ]]; then
		fzf_height="40%"
	else
		fzf_height="100%"
	fi

	fzf_args=(--height "$fzf_height" --reverse --border)

	if [[ "${TMUX_SESSIONIZER_FZF_PREVIEW:-1}" != "0" ]]; then
		preview_cmd="bash -c 'selected_dir=\"\$1\"; session_name=\$(basename \"\$selected_dir\" | tr . _ | tr -cd \"[:alnum:]_\"); if [[ -n \"\$session_name\" ]] && tmux has-session -t \"\$session_name\" 2>/dev/null; then tmux list-windows -t \"\$session_name\" 2>/dev/null || printf \"%s\\n\" \"Session exists\"; else printf \"%s\\n\" \"New session\"; fi' _ {}"
		fzf_args+=(--preview "$preview_cmd")
		fzf_args+=(--preview-window "${TMUX_SESSIONIZER_FZF_PREVIEW_WINDOW:-right:60%:wrap}")
	fi

	selected=""
	if [[ ${#sorted_dirs[@]} -eq 1 ]]; then
		selected="${sorted_dirs[0]}"
		return "$EXIT_SUCCESS"
	fi

	set +e
	selected=$(printf '%s\n' "${sorted_dirs[@]}" | fzf "${fzf_args[@]}")
	fzf_status=$?
	set -e

	if [[ $fzf_status -eq $EXIT_INTERRUPTED ]]; then
		warn "Directory selection interrupted by user (Ctrl-C)."
		return "$EXIT_INTERRUPTED"
	fi

	if [[ $fzf_status -ne 0 ]]; then
		warn "No directory selected."
		selected=""
		return "$EXIT_SUCCESS"
	fi

	if [[ -z "${selected:-}" ]]; then
		warn "No directory selected."
		return "$EXIT_SUCCESS"
	fi

	return "$EXIT_SUCCESS"
}

# Complete the directory -> session workflow.
# @return EXIT_SUCCESS on normal flow, EXIT_INTERRUPTED when selection is cancelled.
select_and_create_session() {
	local selected_name
	local select_status

	build_directory_index

	set +e
	select_directory
	select_status=$?
	set -e

	if [[ $select_status -eq $EXIT_INTERRUPTED ]]; then
		return "$EXIT_INTERRUPTED"
	fi

	if [[ $select_status -ne $EXIT_SUCCESS ]]; then
		return "$select_status"
	fi

	if [[ -z "${selected:-}" ]]; then
		return "$EXIT_SUCCESS"
	fi

	if [[ ! -d "$selected" ]]; then
		die "Selected directory no longer exists: '$selected'. It may have been deleted after selection." "$EXIT_CONFIG_ERROR"
	fi

	if [[ ! -r "$selected" || ! -x "$selected" ]]; then
		die "Selected directory is not accessible: '$selected'. Check permissions and try again." "$EXIT_CONFIG_ERROR"
	fi

	if ! selected_name=$(resolve_session_name "$selected"); then
		die "Session name is empty after sanitization for '${selected}'. This usually means the directory name only contains unsupported special characters. Rename the directory and try again." "$EXIT_CONFIG_ERROR"
	fi

	if [[ -z "$selected_name" ]]; then
		die "Session name is empty after sanitization for '${selected}'. This usually means the directory name only contains unsupported special characters. Rename the directory and try again." "$EXIT_CONFIG_ERROR"
	fi

	if ((${#selected_name} > TMUX_SESSION_NAME_MAX_LENGTH)); then
		die "Session name '$selected_name' exceeds tmux limit (${TMUX_SESSION_NAME_MAX_LENGTH} characters)." "$EXIT_CONFIG_ERROR"
	fi

	create_session_if_missing "$selected_name" "$selected"
	switch_to "$selected_name"

	return "$EXIT_SUCCESS"
}

# Main application entrypoint for CLI execution.
# @param $@ CLI arguments.
# @return Exit code constant matching execution result.
main() {
	local parse_status
	local validate_status

	set +e
	parse_arguments "$@"
	parse_status=$?
	set -e

	if [[ $parse_status -ne $EXIT_SUCCESS ]]; then
		return "$parse_status"
	fi

	if [[ $show_help -eq 1 ]]; then
		print_help
		return "$EXIT_SUCCESS"
	fi

	if [[ $show_version -eq 1 ]]; then
		print_version
		return "$EXIT_SUCCESS"
	fi

	if [[ $validate_only -eq 1 ]]; then
		set +e
		validate_config
		validate_status=$?
		set -e
		return "$validate_status"
	fi

	check_dependencies
	load_configuration
	select_and_create_session
	return "$EXIT_SUCCESS"
}

# ============================================================================
# Entry Point
# ============================================================================

show_help=0
show_version=0
validate_only=0
cli_dirs=()
search_dirs=()
attempted_dirs=()
sorted_dirs=()
dir_cmd=""
selected=""

# Main Script
main "$@"
