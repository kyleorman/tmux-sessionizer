#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
    setup_mock_environment
}

teardown() {
    teardown_mock_environment
}

@test "loads search directories from config file" {
    local config_dir
    config_dir="${HOME}/projects"
    mkdir -p "$config_dir"

    printf '%s\n' \
        '# comment' \
        '$HOME/projects' \
        '$HOME/does-not-exist' \
        > "${HOME}/.config/tmux-sessionizer.conf"

    run_sessionizer

    assert_success
    assert_tmux_log_contains "new-session -ds projects -c ${config_dir}"
}

@test "SEARCH_DIRS overrides config file values" {
    local config_dir
    local env_dir
    config_dir="${HOME}/from-config"
    env_dir="${HOME}/from-env"
    mkdir -p "$config_dir" "$env_dir"

    printf '%s\n' '$HOME/from-config' > "${HOME}/.config/tmux-sessionizer.conf"
    export SEARCH_DIRS="${env_dir}"

    run_sessionizer

    assert_success
    assert_tmux_log_contains "new-session -ds fromenv -c ${env_dir}"
    refute_tmux_log_contains "new-session -ds fromconfig -c ${config_dir}"
}

@test "command-line directory arguments override env and config" {
    local config_dir
    local env_dir
    local cli_dir
    local invalid_dir
    config_dir="${HOME}/from-config"
    env_dir="${HOME}/from-env"
    cli_dir="${HOME}/from-cli"
    invalid_dir="${HOME}/not-a-directory"
    mkdir -p "$config_dir" "$env_dir" "$cli_dir"

    printf '%s\n' '$HOME/from-config' > "${HOME}/.config/tmux-sessionizer.conf"
    export SEARCH_DIRS="${env_dir}"

    run_sessionizer "$cli_dir" "$invalid_dir"

    assert_success
    assert_output --partial "Warning: '${invalid_dir}' is not a directory or does not exist."
    assert_tmux_log_contains "new-session -ds fromcli -c ${cli_dir}"
    refute_tmux_log_contains "new-session -ds fromenv -c ${env_dir}"
    refute_tmux_log_contains "new-session -ds fromconfig -c ${config_dir}"
}
