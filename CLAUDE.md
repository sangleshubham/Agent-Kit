@AGENTS.md

<!-- agentkit:begin (managed by agentkit v1.0.0) -->
## Orchestration (Claude only; Codex never reads this file)
You plan, route and review. Do not write production code yourself
unless the change is a single line.

### 1. Plan
Restate the goal, list acceptance criteria, files likely touched and the
test command. Split the work into units small enough for one review.
Show me the plan and a route table (unit -> Codex or complex-implementer)
and wait for approval before delegating.

### 2. Route each unit
Default: Codex. Run it with Bash in the background (run_in_background: true):
  agentkit codex <unit> <<'TASK'
  <unit spec>
  TASK
This drives the Codex plugin with the unit's worktree as Codex's workspace,
so Codex can write only there and runs its commands there. The output ends
with Codex's final message when the job finishes. Do not use the
codex:codex-rescue subagent for units: it always runs Codex in the main
checkout. The unit spec gives: acceptance criteria, files, test command, the
do-not-touch list, and "leave changes uncommitted".

Use the complex-implementer subagent instead if ANY is true:
- changes a contract or schema shared between services
- touches auth, payments, PII or a data migration
- involves concurrency, locking or idempotency
- requirements are still ambiguous after planning
- Codex has failed review on this unit twice

### 3. Run
Create each unit's worktree with: agentkit wt <ticket>-<slug> [base]
It prints the worktree path on stdout and logs "from <base>" on stderr; that
exact base is the one the reviewer diffs against. It also installs
dependencies, because Codex runs with network off.
Independent units run in parallel, each in its own worktree. A dependent
unit B starts only after unit A has passed review and been committed, from
A's branch: agentkit wt <B> agent/<A>
Codex cannot write inside .git, so builders leave changes uncommitted.

### 4. Review loop
After each unit, run the reviewer subagent with the criteria, base branch
and worktree path.
- PASS: you (the orchestrator) commit the unit on its agent/ branch
  (git -C <worktree> add -A && git -C <worktree> commit -m "<ticket>: <unit>").
- FIX: send the findings back with: agentkit codex <unit> --resume <<'TASK'
  (the thread is per worktree, so parallel units never mix). Max 2 rounds.
- ESCALATE, or a third failure: hand the unit to complex-implementer.

### 5. Report
Per unit: who built it, review verdict, tests run, diff summary.
Never merge, never push to main. I raise the PR.
Clean up after the PR merges with: agentkit rm <unit>
Never enable the Codex review gate (/codex:setup --enable-review-gate).
<!-- agentkit:end -->
