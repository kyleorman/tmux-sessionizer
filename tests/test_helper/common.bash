#!/usr/bin/env bash

if [[ -n "${BATS_SUPPORT_PATH:-}" ]]; then
	load "$BATS_SUPPORT_PATH"
else
	load 'bats-support/load'
fi

if [[ -n "${BATS_ASSERT_PATH:-}" ]]; then
	load "$BATS_ASSERT_PATH"
else
	load 'bats-assert/load'
fi

COMMON_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(CDPATH='' cd -- "${COMMON_DIR}/../.." && pwd)"
SESSIONIZER_SCRIPT="${PROJECT_ROOT}/tmux-sessionizer.sh"

load_tmux_sessionizer_functions() {
	source <(
		while IFS= read -r line; do
			if [[ "$line" == "# Main Script"* ]]; then
				break
			fi
			printf '%s\n' "$line"
		done <"$SESSIONIZER_SCRIPT"
	)
}

setup_mock_environment() {
	TEST_SANDBOX="$(mktemp -d "${BATS_TEST_TMPDIR}/tmux-sessionizer.XXXXXX")"
	export TEST_SANDBOX

	export HOME="${TEST_SANDBOX}/home"
	mkdir -p "${HOME}/.config"

	MOCK_BIN_DIR="${TEST_SANDBOX}/bin"
	mkdir -p "$MOCK_BIN_DIR"

	export ORIGINAL_PATH="$PATH"
	export PATH="${MOCK_BIN_DIR}:$PATH"

	export TMUX_MOCK_LOG="${TEST_SANDBOX}/tmux.log"
	: >"$TMUX_MOCK_LOG"

	create_tmux_mock
	create_fzf_mock
	create_fd_mock
}

teardown_mock_environment() {
	if [[ -n "${ORIGINAL_PATH:-}" ]]; then
		export PATH="$ORIGINAL_PATH"
	fi

	if [[ -n "${TEST_SANDBOX:-}" && -d "${TEST_SANDBOX}" ]]; then
		rm -rf "${TEST_SANDBOX}"
	fi
}

create_tmux_mock() {
	cat >"${MOCK_BIN_DIR}/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${TMUX_MOCK_LOG:?}"
printf '%s\n' "$*" >> "$log_file"

command_name="${1:-}"
shift || true

case "$command_name" in
    has-session)
        target=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                -t)
                    target="${2:-}"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        existing_sessions=":${MOCK_TMUX_EXISTING_SESSIONS:-}:"
        if [[ "$existing_sessions" == *":${target}:"* ]]; then
            exit 0
        fi
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF

	chmod +x "${MOCK_BIN_DIR}/tmux"
}

create_fzf_mock() {
	cat >"${MOCK_BIN_DIR}/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FZF_MOCK_CANCEL:-0}" == "1" ]]; then
    exit 130
fi

if [[ -n "${FZF_MOCK_SELECTION:-}" ]]; then
    printf '%s\n' "${FZF_MOCK_SELECTION}"
    exit 0
fi

if IFS= read -r first_line; then
    printf '%s\n' "$first_line"
fi
EOF

	chmod +x "${MOCK_BIN_DIR}/fzf"
}

create_fd_mock() {
	cat >"${MOCK_BIN_DIR}/fd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
    exit 0
fi

search_dir="${!#}"
find "$search_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -print
EOF

	chmod +x "${MOCK_BIN_DIR}/fd"
}

run_sessionizer() {
	run bash "$SESSIONIZER_SCRIPT" "$@"
}

assert_tmux_log_contains() {
	local expected="$1"

	if ! grep -F -- "$expected" "$TMUX_MOCK_LOG" >/dev/null; then
		echo "Expected tmux log to contain: $expected" >&2
		echo "tmux log:" >&2
		cat "$TMUX_MOCK_LOG" >&2
		return 1
	fi
}

refute_tmux_log_contains() {
	local unexpected="$1"

	if grep -F -- "$unexpected" "$TMUX_MOCK_LOG" >/dev/null; then
		echo "Expected tmux log to not contain: $unexpected" >&2
		echo "tmux log:" >&2
		cat "$TMUX_MOCK_LOG" >&2
		return 1
	fi
}
