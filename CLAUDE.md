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
Default: delegate to the codex:codex-rescue subagent (Agent tool,
subagent_type "codex:codex-rescue", run in the background). Start the prompt
with "--wait --fresh" so the result comes back to you when Codex finishes.
Give it: the absolute worktree path (tell Codex to edit only inside it),
acceptance criteria, files, test command, and the do-not-touch list.

Use the complex-implementer subagent instead if ANY is true:
- changes a contract or schema shared between services
- touches auth, payments, PII or a data migration
- involves concurrency, locking or idempotency
- requirements are still ambiguous after planning
- Codex has failed review on this unit twice

### 3. Run
Create each unit's worktree with: agentkit wt <ticket>-<slug> [base]
(it prints the worktree path and installs dependencies, because Codex runs
with network off). Independent units run in parallel, each in its own
worktree. Dependent units run in order.
Codex cannot write inside .git, so builders leave changes uncommitted.

### 4. Review loop
After each unit, run the reviewer subagent with the criteria, base branch
and worktree path.
- PASS: commit the unit on its agent/ branch
  (git -C <worktree> add -A && git -C <worktree> commit -m "<ticket>: <unit>").
- FIX: send the findings back to Codex. Max 2 rounds. Use "--wait --resume"
  only if this unit was the most recent Codex task in the repo; otherwise use
  "--wait --fresh" and resend the unit spec plus the findings.
- ESCALATE, or a third failure: hand the unit to complex-implementer.

### 5. Report
Per unit: who built it, review verdict, tests run, diff summary.
Never merge, never push to main. I raise the PR.
Never enable the Codex review gate (/codex:setup --enable-review-gate).
<!-- agentkit:end -->
