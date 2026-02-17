#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
    setup_mock_environment
    load_tmux_sessionizer_functions
}

teardown() {
    teardown_mock_environment
}

@test "switch_to uses switch-client when inside tmux" {
    export TMUX="/tmp/tmux-123/default,123,0"

    switch_to "demo-session"

    assert_tmux_log_contains "switch-client -t demo-session"
    refute_tmux_log_contains "attach-session -t demo-session"
}

@test "switch_to uses attach-session when outside tmux" {
    unset TMUX

    switch_to "demo-session"

    assert_tmux_log_contains "attach-session -t demo-session"
    refute_tmux_log_contains "switch-client -t demo-session"
}

@test "has_session returns success for existing session" {
    export MOCK_TMUX_EXISTING_SESSIONS="existing-session"

    run has_session "existing-session"

    assert_success
}

@test "has_session returns failure for missing session" {
    run has_session "missing-session"

    assert_failure
}

@test "hydrate prefers project-local tmux-sessionizer file" {
    local project_dir
    project_dir="${HOME}/project"
    mkdir -p "$project_dir"

    printf '%s\n' "set-option -g mouse on" > "${HOME}/.tmux-sessionizer"
    printf '%s\n' "split-window -h" > "${project_dir}/.tmux-sessionizer"

    hydrate "demo-session" "$project_dir"

    assert_tmux_log_contains "source-file ${project_dir}/.tmux-sessionizer"
    refute_tmux_log_contains "source-file ${HOME}/.tmux-sessionizer"
}

@test "hydrate falls back to home tmux-sessionizer file" {
    local project_dir
    project_dir="${HOME}/project"
    mkdir -p "$project_dir"

    printf '%s\n' "split-window -v" > "${HOME}/.tmux-sessionizer"

    hydrate "demo-session" "$project_dir"

    assert_tmux_log_contains "source-file ${HOME}/.tmux-sessionizer"
}

@test "check_command_exists succeeds for installed command" {
    run check_command_exists "bash"

    assert_success
    assert_output ""
}

@test "check_command_exists exits for missing command" {
    run check_command_exists "command-that-does-not-exist"

    assert_failure
    assert_output --partial "is required but not installed"
}

@test "session name sanitization uses alnum and underscores" {
    local project_dir
    project_dir="${HOME}/project.with-dash!"
    mkdir -p "$project_dir"

    run_sessionizer "$project_dir"

    assert_success
    assert_tmux_log_contains "new-session -ds project_withdash -c ${project_dir}"
}

@test "config parsing expands env vars and ignores invalid entries" {
    local workspace_dir
    workspace_dir="${HOME}/workspace"
    mkdir -p "$workspace_dir"

    printf '%s\n' \
        "# comment" \
        '$HOME/workspace' \
        '$HOME/does-not-exist' \
        > "${HOME}/.config/tmux-sessionizer.conf"

    run_sessionizer

    assert_success
    assert_tmux_log_contains "new-session -ds workspace -c ${workspace_dir}"
}
