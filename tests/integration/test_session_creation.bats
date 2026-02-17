#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
    setup_mock_environment
}

teardown() {
    teardown_mock_environment
}

@test "discovers child directories and creates session for selected entry" {
    local search_root
    local alpha_dir
    local beta_dir
    search_root="${HOME}/workspace"
    alpha_dir="${search_root}/alpha"
    beta_dir="${search_root}/beta"

    mkdir -p "$alpha_dir" "$beta_dir"
    printf '%s\n' '$HOME/workspace' > "${HOME}/.config/tmux-sessionizer.conf"
    export FZF_MOCK_SELECTION="$beta_dir"

    run_sessionizer

    assert_success
    assert_tmux_log_contains "new-session -ds beta -c ${beta_dir}"
}

@test "uses root directory when no children exist" {
    local search_root
    search_root="${HOME}/single-project"
    mkdir -p "$search_root"

    printf '%s\n' '$HOME/single-project' > "${HOME}/.config/tmux-sessionizer.conf"

    run_sessionizer

    assert_success
    assert_tmux_log_contains "new-session -ds singleproject -c ${search_root}"
}
