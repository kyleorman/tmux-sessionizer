# Contributing to tmux-sessionizer

Thanks for helping improve tmux-sessionizer. This guide covers the expected workflow for docs, tests, and shell code changes.

## Getting Started

Prerequisites:

- `bash` 4.0+
- `zsh` 5.0+
- `tmux`
- `fzf`
- `fd` (preferred) or `find`
- `shellcheck`

Setup:

```bash
git clone https://github.com/kyleorman/tmux-sessionizer.git
cd tmux-sessionizer

# Run tests (downloads BATS dependencies on first run if needed)
./test/run-tests.sh

# Lint and syntax checks
shellcheck tmux-sessionizer.sh
shellcheck -s bash .tmux-functions.zsh
bash -n tmux-sessionizer.sh
zsh -n .tmux-functions.zsh
```

## Development Workflow

- Create a focused branch from your working base.
- Recommended branch naming:
  - `feat/<short-description>`
  - `fix/<short-description>`
  - `docs/<short-description>`
  - `test/<short-description>`
- Keep commits small and scoped to one concern.
- Use clear commit messages in imperative form. Conventional prefixes are recommended:
  - `feat: ...`
  - `fix: ...`
  - `docs: ...`
  - `test: ...`
  - `refactor: ...`
  - `chore: ...`

## Testing Guidelines

Run tests before submitting changes:

```bash
# Full suite
./test/run-tests.sh

# Unit or integration subsets
./test/run-tests.sh tests/unit/
./test/run-tests.sh tests/integration/

# Single file
./test/run-tests.sh tests/unit/test_functions.bats
```

Adding tests:

- Put unit tests in `tests/unit/`.
- Put integration tests in `tests/integration/`.
- Put shared helpers in `tests/test_helper/common.bash`.
- Use BATS patterns (`@test`, `setup`, `teardown`) and keep each test focused on one behavior.

BATS basics:

- Use `load '../test_helper/common.bash'` in test files.
- Use mock helpers to isolate `tmux`, `fzf`, and filesystem behavior.
- Prefer deterministic tests that do not depend on user machine state.

## Code Style

- ShellCheck is required for shell scripts.
- Quote variable expansions (`"$var"`) unless unquoted expansion is explicitly required.
- Prefer `[[ ... ]]` for conditionals in Bash/Zsh scripts.
- Avoid `eval` unless there is no safe alternative.
- Keep function names `snake_case` and constants `UPPER_SNAKE_CASE`.
- Print actionable errors to stderr and return meaningful exit codes.

## Submitting Changes

- Open a pull request with a clear title and short summary.
- Include why the change is needed, not just what changed.
- Link related issues (if any).
- Include validation output for relevant commands:
  - `./test/run-tests.sh`
  - `shellcheck tmux-sessionizer.sh`
  - `shellcheck -s bash .tmux-functions.zsh`
  - `bash -n tmux-sessionizer.sh`
  - `zsh -n .tmux-functions.zsh`
- Be responsive to review feedback and keep follow-up commits focused.

## Reporting Issues

For bug reports, include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- OS and shell versions
- `tmux`, `fzf`, and `bash`/`zsh` versions
- Relevant config snippets (`~/.config/tmux-sessionizer.conf`, `.tmux-sessionizer`)

For feature requests, include:

- Problem statement or workflow pain point
- Proposed behavior
- Example usage
- Backward compatibility considerations
