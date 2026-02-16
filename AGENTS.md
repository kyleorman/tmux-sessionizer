# AGENTS.md

Project playbook for agent-driven work in `tmux-sessionizer`.

## Scope

- Project type: shell tooling (`bash` + `zsh`) for tmux session management.
- Main files: `tmux-sessionizer.sh`, `.tmux-functions.zsh`, `README.md`.
- Primary quality baseline: ShellCheck recommendations.

## Pipeline

Use this sequence for each non-trivial task:

1. `planner` -> writes `.opencode/work/<slug>/plan.md`
2. `plan-reviewer` -> writes `.opencode/work/<slug>/plan_review.md`
3. `build` (implementer) -> executes plan and appends `.opencode/work/<slug>/implementation_log.md`
4. `code-reviewer` -> writes `.opencode/work/<slug>/code_review.md`
5. `build` fix loop -> addresses findings and appends `.opencode/work/<slug>/fix_log.md`
6. `code-reviewer` release gate -> writes `.opencode/work/<slug>/release_check.md`

No commit or push is allowed until `release_check.md` says `PASS`.

## Work Artifacts

Create task artifacts at:

`.opencode/work/<slug>/`

Required files:

- `plan.md`
- `plan_review.md`
- `implementation_log.md`
- `code_review.md`
- `fix_log.md` (if fixes are needed)
- `release_check.md`

## Role Responsibilities

### planner

- Clarify objective, constraints, and affected files.
- Break work into ordered, testable steps.
- Define verification commands and success criteria.

### plan-reviewer

- Validate completeness and sequencing.
- Flag missing edge cases and risky assumptions.
- Approve/block with clear rationale.

### build (implementer)

- Execute approved plan step-by-step.
- Keep changes focused and minimal.
- Run validation commands early and after edits.
- After each completed step, append:
  - step number
  - what changed
  - commands run and results (including failures)

### code-reviewer

- Classify findings as `Blocker`, `Major`, or `Minor`.
- Confirm correctness, safety, and convention alignment.
- Produce release gate decision (`PASS`/`FAIL`).

## Severity Rules

- `Blocker`: potential data loss, security issue, crash/regression risk.
- `Major`: logic flaws, broken workflow, or requirement miss.
- `Minor`: style, clarity, or non-critical maintainability issue.

Fix order is always `Blocker` -> `Major` -> `Minor`.

## Validation Standard

Preferred validation stack:

1. ShellCheck
2. BATS (when tests exist)
3. Basic execution/syntax checks

Typical commands:

```bash
shellcheck tmux-sessionizer.sh
# ShellCheck does not parse zsh; lint this file in bash mode as a best-effort check
shellcheck -s bash .tmux-functions.zsh

bash -n tmux-sessionizer.sh
zsh -n .tmux-functions.zsh

# run when tests exist
bats tests/
```

Definition of done for this repository:

- ShellCheck passes
- basic execution test passes (syntax check at minimum)
- review gate is PASS

## Shell Conventions

- Use strict mode where applicable: `set -euo pipefail`.
- Quote expansions: `"$var"`.
- Prefer `[[ ... ]]` for conditionals.
- Avoid `eval` unless no safer option exists.
- Print actionable errors to stderr and return proper exit codes.
- Keep compatibility with common Linux/macOS shell environments.

## Commit and Push Policy

- Preserve unrelated local changes.
- Stage only files relevant to the task.
- Do not commit secrets or machine-local credentials.
- Do not amend prior commits unless explicitly requested.
- Push only after successful release gate (`PASS`).

## Suggested Templates

### implementation_log.md entry

```markdown
## Step <n>
- Changed: <what changed>
- Commands:
  - `<command>` -> <result>
  - `<command>` -> <result>
```

### fix_log.md entry

```markdown
## Fix <n>
- Review item: <Blocker/Major/Minor + description>
- Changed: <what changed>
- Commands:
  - `<command>` -> <result>
```

### release_check.md

```markdown
# Release Check

- ShellCheck: PASS/FAIL
- Basic execution test: PASS/FAIL
- BATS: PASS/FAIL/NOT RUN

Decision: PASS/FAIL
```
