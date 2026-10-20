# AGENTS.md
<!-- Shared by Codex and Claude. Edit freely; agentkit never overwrites this file. -->

## Stack
A single Bash script, `agentkit` (bash 4+, GNU coreutils, git, node for JSON edits).
No package manager, no dependencies.

## Commands
- Install: none
- Test: bash tests/run.sh
- Lint: uvx --offline --from shellcheck-py shellcheck -x agentkit tests/*.sh

## Rules
- Work only inside the worktree path you are given.
- Make the smallest change that meets the acceptance criteria.
- Every bug fix starts with a failing test that reproduces it.
- Never read or print .env files or secrets.
- Builders (Codex, complex-implementer) never commit, push or merge; leave changes uncommitted for review.
- Never push to or change the main branch.
- Tests must never touch the real $HOME or ~/.codex: point HOME and CODEX_HOME at a temp dir.
- Finish by listing files changed and the test output.
