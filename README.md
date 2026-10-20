# agentkit

Claude Code on Opus plans, routes and reviews; Codex (GPT-6.1 Sol, through the
[openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) plugin) writes
the code; a Claude Opus `complex-implementer` subagent takes only high-risk units.
`agentkit` is one bash file that sets this up on a machine and in any repo.

```text
You -> Opus session (plan, route) --default--> codex:codex-rescue (Codex, Sol)
                                   \--high-risk--> complex-implementer (Opus)
       both --> reviewer (Opus): PASS -> commit on agent/<unit> | FIX (max 2) | ESCALATE
```

## Install (once per machine)

```bash
git clone <your-private-remote>/agent-kit.git ~/.agent-kit   # or keep it anywhere
~/.agent-kit/agentkit install
```

`install` installs Claude Code and the Codex CLI if missing, writes
`~/.codex/config.toml` only if you have none, installs the `codex@openai-codex`
plugin at user scope, and links `agentkit` into `~/.local/bin`. Then sign in once:

```bash
claude setup-token          # headless; export CLAUDE_CODE_OAUTH_TOKEN=<token>
codex login --device-auth   # or copy ~/.codex/auth.json from a laptop
```

## Set up a project (once per repo, safe to re-run)

```bash
cd ~/work/<repo> && agentkit init
# review AGENTS.md (Commands section), then commit the result
```

| File | Read by | Written by `init` |
| --- | --- | --- |
| `AGENTS.md` | Codex and Claude | Created once with detected install/test/lint commands; never overwritten. An existing `CLAUDE.md` is moved here (backup kept). |
| `CLAUDE.md` | Claude | `@AGENTS.md` on line 1, plus the orchestration rules between `agentkit:begin/end` markers (refreshed on every run). |
| `.claude/agents/reviewer.md`, `complex-implementer.md` | Claude | Refreshed while they carry the "managed by agentkit" marker. |
| `.claude/settings.json` | Claude | Merged: `model` (only if unset), plugin enabled, marketplace declared. |
| `.codex/config.toml` | Codex | Model, effort, `approval_policy = "never"`, `workspace-write`, network off. |
| `~/.codex/config.toml` | Codex | Appends a `[projects."<repo>"] trust_level = "trusted"` entry so the project config applies. |
| `.gitignore` | git | Adds `.worktrees/`. |

Override models at setup time: `CODEX_MODEL=<id> CODEX_EFFORT=xhigh CLAUDE_MODEL=claude-opus-5-5 agentkit init`.
Set `CODEX_NETWORK=true` for a project where Codex itself must install packages.

## Commands

| Command | What it does |
| --- | --- |
| `agentkit install` | Machine setup (above). |
| `agentkit init [dir]` | Project setup (above). Works from inside a linked worktree too; it always targets the main checkout. |
| `agentkit wt <name> [base] [--no-install]` | Creates `.worktrees/<name>` on branch `agent/<name>` from `origin/<base>` (or `origin/HEAD`, or the current branch), installs Node dependencies there, and prints only the path on stdout. |
| `agentkit rm <name>` | Removes a clean unit worktree; keeps the branch. |
| `agentkit doctor [dir]` | One line per machine and project check; exits non-zero if anything is missing. |

## Daily use

```bash
tmux new -As work
cd ~/work/<repo> && claude
> APP-1234: <ticket text>. Plan, route, and bring every unit to review PASS.
```

Approve the plan and route table, watch Codex with `/codex:status` and
`/codex:result`, read the final report, then push the `agent/` branch and raise
the PR yourself. To take over a Codex run: `codex resume <session-id>`.

## Changes from the original plan, and why

- **Builders never commit.** Codex's `workspace-write` sandbox keeps `.git`
  read-only, so it cannot `git add`/`commit`. Builders leave changes uncommitted;
  the reviewer reads `git diff HEAD` and untracked files; Opus commits after PASS.
- **`--wait` inside a background subagent.** The rules tell Opus to run
  `codex:codex-rescue` in the background with `--wait`, so Codex's result comes
  back when it finishes instead of a job id that has to be polled.
- **`--resume` only for the latest job.** The plugin resumes the *most recent*
  Codex thread in the repo, so with parallel units a FIX round resends the spec
  plus findings with `--fresh` unless that unit was the last Codex task.
- **`wt` installs dependencies.** Codex runs with network off, so a fresh
  worktree would have no `node_modules`.
- **Worktree-safe roots.** `init`, `wt` and `rm` resolve the main checkout even
  when run inside `.worktrees/<x>`, so worktrees never nest.
- **Logs on stderr**, so `path=$(agentkit wt x)` works; `doctor` checks are
  argument-safe (no `eval`) and check the configured model, not the default one.
- Input validation for `CODEX_EFFORT`, `CODEX_NETWORK` and model ids; a
  `.gitignore` or `config.toml` without a trailing newline is no longer corrupted.

## Guardrails

- Never enable the plugin's review gate (`/codex:setup --enable-review-gate`): it
  runs Codex after every Claude reply and can drain both plans.
- Fix rounds are capped at 2, then the unit escalates to Opus.
- Agents push only `agent/` branches; protect `main` on the remote.
- On a shared VPS, run everything as a dedicated non-root `agent` user with a
  deploy key that can push feature branches only.

## Tests

```bash
bash tests/run.sh
uvx --from shellcheck-py shellcheck -x agentkit tests/*.sh
```
