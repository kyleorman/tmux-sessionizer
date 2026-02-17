#!/usr/bin/env bash

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
	printf 'Error: run-tests.sh requires bash 4.0 or higher (found %s).\n' "${BASH_VERSION:-unknown}" >&2
	exit 1
fi

set -euo pipefail

readonly BATS_CORE_VERSION="v1.11.1"
readonly BATS_SUPPORT_VERSION="v0.3.0"
readonly BATS_ASSERT_VERSION="v2.1.0"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

BATS_CACHE_DIR="${PROJECT_ROOT}/test/tmp/bats"
BATS_CORE_DIR="${BATS_CACHE_DIR}/bats-core"
BATS_SUPPORT_DIR="${BATS_CACHE_DIR}/bats-support"
BATS_ASSERT_DIR="${BATS_CACHE_DIR}/bats-assert"

usage() {
	cat <<'EOF'
Usage: ./test/run-tests.sh [PATH ...]

Run tmux-sessionizer BATS tests.

Arguments:
  PATH    Optional test file or directory paths (default: tests/)

Options:
  -h, --help    Show this help message

The runner checks for a system bats binary first. If unavailable, it downloads
bats-core into test/tmp/bats/ and uses the vendored binary. bats-support and
bats-assert are downloaded into test/tmp/bats/ when missing.
EOF
}

require_downloader() {
	if command -v curl >/dev/null 2>&1; then
		printf '%s\n' "curl"
		return 0
	fi

	if command -v wget >/dev/null 2>&1; then
		printf '%s\n' "wget"
		return 0
	fi

	echo "Error: curl or wget is required to download BATS dependencies." >&2
	exit 1
}

download_archive() {
	local url="$1"
	local destination="$2"
	local downloader

	downloader="$(require_downloader)"

	if [[ "$downloader" == "curl" ]]; then
		curl -fsSL "$url" -o "$destination"
	else
		wget -qO "$destination" "$url"
	fi
}

install_repo_from_tag() {
	local repo="$1"
	local tag="$2"
	local destination="$3"
	local archive_name
	local archive_path
	local url

	if [[ -d "$destination" ]]; then
		return 0
	fi

	mkdir -p "$destination"

	archive_name="${repo##*/}-${tag}.tar.gz"
	archive_path="${BATS_CACHE_DIR}/${archive_name}"
	url="https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz"

	download_archive "$url" "$archive_path"
	tar -xzf "$archive_path" --strip-components=1 -C "$destination"
}

ensure_test_dependencies() {
	mkdir -p "$BATS_CACHE_DIR"

	install_repo_from_tag "bats-core/bats-support" "$BATS_SUPPORT_VERSION" "$BATS_SUPPORT_DIR"
	install_repo_from_tag "bats-core/bats-assert" "$BATS_ASSERT_VERSION" "$BATS_ASSERT_DIR"
}

resolve_bats_command() {
	if command -v bats >/dev/null 2>&1; then
		command -v bats
		return 0
	fi

	install_repo_from_tag "bats-core/bats-core" "$BATS_CORE_VERSION" "$BATS_CORE_DIR"
	printf '%s\n' "${BATS_CORE_DIR}/bin/bats"
}

collect_test_targets() {
	local input_target
	local found=0

	for input_target in "$@"; do
		if [[ -d "$input_target" ]]; then
			while IFS= read -r test_file; do
				found=1
				printf '%s\n' "$test_file"
			done < <(find "$input_target" -type f -name '*.bats' | sort)
		else
			found=1
			printf '%s\n' "$input_target"
		fi
	done

	if [[ "$found" -eq 0 ]]; then
		echo "Error: No test files found for the provided targets." >&2
		exit 1
	fi
}

main() {
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		usage
		exit 0
	fi

	ensure_test_dependencies

	local bats_cmd
	bats_cmd="$(resolve_bats_command)"

	local -a raw_targets
	if [[ "$#" -eq 0 ]]; then
		raw_targets=("tests")
	else
		raw_targets=("$@")
	fi

	local -a targets
	mapfile -t targets < <(collect_test_targets "${raw_targets[@]}")

	BATS_LIB_PATH="$BATS_CACHE_DIR" \
		BATS_SUPPORT_PATH="${BATS_SUPPORT_DIR}/load.bash" \
		BATS_ASSERT_PATH="${BATS_ASSERT_DIR}/load.bash" \
		"$bats_cmd" "${targets[@]}"
}

main "$@"
