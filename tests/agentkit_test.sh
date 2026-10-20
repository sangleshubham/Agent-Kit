#!/usr/bin/env bash
# Sourced by run.sh. All fixtures and command output live in that test's sandbox.

test_init_fresh_repo() {
  kit_ok init
  local file
  for file in AGENTS.md CLAUDE.md .claude/agents/reviewer.md \
    .claude/agents/complex-implementer.md .claude/settings.json .codex/config.toml; do
    assert_file "$REPO/$file"
  done
  assert_eq '@AGENTS.md' "$(head -n1 CLAUDE.md)"
  assert_eq 1 "$(grep -cF 'agentkit:begin' CLAUDE.md)"
  assert_eq 1 "$(grep -cF 'agentkit:end' CLAUDE.md)"
  settings_check 's.model === "opus" && s.enabledPlugins["codex@openai-codex"] === true && s.extraKnownMarketplaces["openai-codex"].source.repo === "openai/codex-plugin-cc"'
  assert_line .gitignore '.worktrees/'
}

test_init_idempotent_every_file_and_trust() {
  kit_ok init
  snapshot_files "$SANDBOX/first.sha256"
  kit_ok init
  snapshot_files "$SANDBOX/second.sha256"
  assert_same "$SANDBOX/first.sha256" "$SANDBOX/second.sha256"
  assert_eq 1 "$(grep -cF "[projects.\"$REPO\"]" "$CODEX_HOME/config.toml")"
}

test_init_migrates_claude_and_repairs_gitignore_newline() {
  printf '@AGENTS.md\n# User instructions\n\nKeep this content.\n' > CLAUDE.md
  cp CLAUDE.md "$SANDBOX/original-claude"
  printf 'existing-ignore' > .gitignore
  kit_ok init
  assert_contains AGENTS.md $'## Migrated from CLAUDE.md'
  assert_eq $'# User instructions\n\nKeep this content.' \
    "$(sed -n '/^## Migrated from CLAUDE.md$/,$p' AGENTS.md | tail -n +3)"
  assert_same "$SANDBOX/original-claude" CLAUDE.md.agentkit-backup
  assert_eq '@AGENTS.md' "$(head -n1 CLAUDE.md)"
  if grep -qF 'Keep this content.' CLAUDE.md; then fail 'Migrated content remains in CLAUDE.md'; fi
  printf 'existing-ignore\nCLAUDE.md.agentkit-backup\n.worktrees/\n' > "$SANDBOX/expected-ignore"
  assert_same "$SANDBOX/expected-ignore" .gitignore
  git check-ignore -q CLAUDE.md.agentkit-backup || fail 'Backup is not gitignored'
}

test_init_preserves_existing_agents_and_claude_content() {
  printf '# My AGENTS\nUser rules with no final newline' > AGENTS.md
  printf '# My CLAUDE\nUser instructions\n' > CLAUDE.md
  cp AGENTS.md "$SANDBOX/original-agents"
  cp CLAUDE.md "$SANDBOX/original-claude"
  kit_ok init
  assert_same "$SANDBOX/original-agents" AGENTS.md
  assert_eq '@AGENTS.md' "$(head -n1 CLAUDE.md)"
  sed -n '2,3p' CLAUDE.md > "$SANDBOX/kept-claude"
  assert_same "$SANDBOX/original-claude" "$SANDBOX/kept-claude"
  assert_eq 1 "$(grep -cF 'agentkit:begin' CLAUDE.md)"
  [[ ! -e CLAUDE.md.agentkit-backup ]] || fail 'Existing AGENTS should prevent migration'
}

test_init_preserves_user_reviewer() {
  mkdir -p .claude/agents
  printf '# My reviewer\nKeep exactly this.' > .claude/agents/reviewer.md
  cp .claude/agents/reviewer.md "$SANDBOX/reviewer"
  kit_ok init
  assert_same "$SANDBOX/reviewer" .claude/agents/reviewer.md
}

test_init_refreshes_managed_reviewer() {
  kit_ok init
  cp .claude/agents/reviewer.md "$SANDBOX/reviewer"
  printf '<!-- managed by agentkit -->\nSTALE REVIEWER\n' > .claude/agents/reviewer.md
  kit_ok init
  assert_same "$SANDBOX/reviewer" .claude/agents/reviewer.md
}

test_settings_merge_preserves_user_values() {
  mkdir -p .claude
  cat > .claude/settings.json <<'JSON'
{"model":"sonnet","userKey":{"keep":[1,2]},"enabledPlugins":{"custom@example":false},"extraKnownMarketplaces":{"custom":{"source":{"source":"github","repo":"user/repo"}}}}
JSON
  kit_ok init
  settings_check 's.model === "sonnet" && JSON.stringify(s.userKey) === "{\"keep\":[1,2]}" && s.enabledPlugins["custom@example"] === false && s.enabledPlugins["codex@openai-codex"] === true && s.extraKnownMarketplaces.custom.source.repo === "user/repo" && s.extraKnownMarketplaces["openai-codex"].source.repo === "openai/codex-plugin-cc"'
}

test_settings_invalid_json_fails() {
  mkdir -p .claude
  printf '{invalid json\n' > .claude/settings.json
  cp .claude/settings.json "$SANDBOX/settings"
  kit_fails init
  assert_contains "$SANDBOX/stderr" 'is not valid JSON'
  assert_same "$SANDBOX/settings" .claude/settings.json
}

test_settings_empty_file_is_object() {
  mkdir -p .claude
  : > .claude/settings.json
  kit_ok init
  settings_check 's.model === "opus" && s.enabledPlugins["codex@openai-codex"] === true'
}

test_trust_appends_to_config_without_newline() {
  printf 'model = "user-model"' > "$CODEX_HOME/config.toml"
  kit_ok init
  assert_line "$CODEX_HOME/config.toml" 'model = "user-model"'
  assert_line "$CODEX_HOME/config.toml" "[projects.\"$REPO\"]"
  assert_line "$CODEX_HOME/config.toml" 'trust_level = "trusted"'
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' 2>/dev/null; then
    python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$CODEX_HOME/config.toml"
  else
    printf 'SKIP: TOML parsing assertion (python3 with tomllib unavailable)\n'
  fi
}

test_trust_existing_double_quoted_key_not_duplicated() {
  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$REPO" > "$CODEX_HOME/config.toml"
  cp "$CODEX_HOME/config.toml" "$SANDBOX/trust"
  kit_ok init
  assert_same "$SANDBOX/trust" "$CODEX_HOME/config.toml"
}

test_trust_existing_single_quoted_key_not_duplicated() {
  printf "[projects.'%s']\ntrust_level = \"trusted\"\n" "$REPO" > "$CODEX_HOME/config.toml"
  cp "$CODEX_HOME/config.toml" "$SANDBOX/trust"
  kit_ok init
  assert_same "$SANDBOX/trust" "$CODEX_HOME/config.toml"
}

test_init_from_linked_worktree_configures_main_checkout() {
  commit_fixture
  kit_ok wt linked --no-install
  local linked="$REPO/.worktrees/linked"
  cd "$linked" || fail 'Could not enter linked worktree'
  kit_ok init
  assert_file "$REPO/AGENTS.md"
  assert_file "$REPO/CLAUDE.md"
  assert_file "$REPO/.claude/settings.json"
  assert_file "$REPO/.codex/config.toml"
  [[ ! -e "$linked/AGENTS.md" && ! -e "$linked/.claude" && ! -e "$linked/.codex" ]] ||
    fail 'Init wrote project configuration into the linked worktree'
  assert_line "$CODEX_HOME/config.toml" "[projects.\"$REPO\"]"
}

test_init_rejects_invalid_effort() {
  export CODEX_EFFORT=bogus
  kit_fails init
  assert_contains "$SANDBOX/stderr" 'CODEX_EFFORT'
}

test_init_rejects_invalid_network() {
  export CODEX_NETWORK=maybe
  kit_fails init
  assert_contains "$SANDBOX/stderr" 'CODEX_NETWORK'
}

test_init_uses_custom_codex_model() {
  export CODEX_MODEL=foo-1
  kit_ok init
  assert_line .codex/config.toml 'model = "foo-1"'
}

test_detect_npm_default_test_is_todo() {
  cat > package.json <<'JSON'
{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}
JSON
  node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
  kit_ok init
  assert_line AGENTS.md '- Test: TODO: add a test command'
  assert_line AGENTS.md '- Install: npm install'
}

test_detect_pnpm_test() {
  printf '{"scripts":{"test":"fixture-test"}}\n' > package.json
  touch pnpm-lock.yaml
  kit_ok init
  assert_line AGENTS.md '- Test: pnpm test'
}

test_detect_yarn_test() {
  printf '{"scripts":{"test":"fixture-test"}}\n' > package.json
  touch yarn.lock
  kit_ok init
  assert_line AGENTS.md '- Test: yarn test'
}

test_detect_uv_pytest() {
  touch pyproject.toml uv.lock
  kit_ok init
  assert_line AGENTS.md '- Test: uv run pytest'
}

test_detect_go_test() {
  printf 'module example.invalid/fixture\n' > go.mod
  kit_ok init
  assert_line AGENTS.md '- Test: go test ./...'
}

test_wt_stdout_path_stderr_logs_and_branch() {
  # A package fixture also verifies --no-install prevents running its lifecycle hook.
  printf '{"scripts":{"preinstall":"exit 99"}}\n' > package.json
  commit_fixture
  kit_ok wt unit --no-install
  printf '%s\n' "$REPO/.worktrees/unit" > "$SANDBOX/expected-stdout"
  assert_same "$SANDBOX/expected-stdout" "$SANDBOX/stdout.raw"
  assert_contains "$SANDBOX/stderr" '[agentkit] worktree'
  if grep -qF 'installing dependencies' "$SANDBOX/stderr"; then
    fail '--no-install attempted dependency installation'
  fi
  assert_eq 'agent/unit' "$(git -C "$REPO/.worktrees/unit" branch --show-current)"
  [[ ! -e "$REPO/.worktrees/unit/node_modules" ]] || fail 'Unexpected dependency install'
}

test_wt_from_linked_worktree_does_not_nest() {
  commit_fixture
  kit_ok wt first --no-install
  mkdir -p "$REPO/.worktrees/first/subdir"
  cd "$REPO/.worktrees/first/subdir" || fail 'Could not enter worktree subdirectory'
  kit_ok wt second --no-install
  assert_eq "$REPO/.worktrees/second" "$(cat "$SANDBOX/stdout")"
  assert_eq 'agent/second' "$(git -C "$REPO/.worktrees/second" branch --show-current)"
  [[ ! -e "$REPO/.worktrees/first/.worktrees" ]] || fail 'Nested worktrees directory created'
}

test_wt_duplicate_name_fails() {
  commit_fixture
  kit_ok wt duplicate --no-install
  kit_fails wt duplicate --no-install
  assert_contains "$SANDBOX/stderr" 'already exists'
}

test_wt_existing_branch_without_directory_fails() {
  commit_fixture
  git branch agent/existing
  kit_fails wt existing --no-install
  assert_contains "$SANDBOX/stderr" 'branch agent/existing already exists'
}

test_wt_name_with_spaces_fails() {
  commit_fixture
  kit_fails wt 'bad name' --no-install
  assert_contains "$SANDBOX/stderr" 'not a valid branch name'
}

test_wt_parent_traversal_fails() {
  commit_fixture
  kit_fails wt '../x' --no-install
  assert_contains "$SANDBOX/stderr" 'not a valid branch name'
  [[ ! -e "$REPO/x" ]] || fail 'Traversal created an outside worktree'
}

test_wt_nonexistent_base_fails() {
  commit_fixture
  kit_fails wt missing-base does-not-exist --no-install
  assert_contains "$SANDBOX/stderr" "base 'does-not-exist' does not exist"
  [[ ! -e "$REPO/.worktrees/missing-base" ]] || fail 'Worktree created for invalid base'
}

test_wt_repo_without_commits_fails() {
  kit_fails wt unborn --no-install
  assert_contains "$SANDBOX/stderr" 'repository has no commits'
}

test_wt_unknown_option_fails() {
  commit_fixture
  kit_fails wt unit --unknown --no-install
  assert_contains "$SANDBOX/stderr" 'unknown option --unknown'
}

test_wt_explicit_base_prefers_origin_ref() {
  commit_fixture
  local local_commit remote_commit
  local_commit=$(git rev-parse HEAD)
  git branch release
  git init --quiet --bare --initial-branch=fixture-base "$SANDBOX/origin.git"
  git remote add origin "$SANDBOX/origin.git"
  git push --quiet origin fixture-base:release
  # Build a newer remote release in a local clone, leaving local release behind.
  git clone --quiet --branch release "$SANDBOX/origin.git" "$SANDBOX/publisher"
  printf 'remote release\n' > "$SANDBOX/publisher/remote.txt"
  git -C "$SANDBOX/publisher" add remote.txt
  git -C "$SANDBOX/publisher" commit --quiet -m 'Remote release fixture'
  remote_commit=$(git -C "$SANDBOX/publisher" rev-parse HEAD)
  git -C "$SANDBOX/publisher" push --quiet origin release
  [[ "$local_commit" != "$remote_commit" ]] || fail 'Origin fixture did not diverge'
  kit_ok wt remote-unit release --no-install
  assert_eq "$remote_commit" "$(git -C "$REPO/.worktrees/remote-unit" rev-parse HEAD)"
  assert_eq "$local_commit" "$(git rev-parse release)"
  assert_contains "$SANDBOX/stderr" '(from origin/release)'
}

test_rm_clean_worktree_keeps_branch() {
  commit_fixture
  kit_ok wt removable --no-install
  kit_ok rm removable
  [[ ! -e "$REPO/.worktrees/removable" ]] || fail 'Worktree directory remains'
  git show-ref --verify --quiet refs/heads/agent/removable || fail 'Worktree branch was removed'
  if git worktree list --porcelain | grep -qF "$REPO/.worktrees/removable"; then
    fail 'Worktree is still registered'
  fi
}

test_rm_missing_worktree_fails() {
  commit_fixture
  kit_fails rm missing
  assert_contains "$SANDBOX/stderr" 'no worktree at'
}

test_doctor_after_init_project_checks_all_ok() {
  kit_ok init
  # Machine checks are host-dependent and may make doctor return nonzero.
  capture "$KIT_DIR/agentkit" doctor
  sed -n '/^project (/,$p' "$SANDBOX/stdout" > "$SANDBOX/project-checks"
  assert_line "$SANDBOX/project-checks" "project ($REPO):"
  local count=0 line
  while IFS= read -r line; do
    [[ "$line" == 'project ('* ]] && continue
    [[ "$line" == '  ok    '* ]] || fail "Unexpected project check: $line"
    count=$((count + 1))
  done < "$SANDBOX/project-checks"
  [[ "$count" -gt 0 ]] || fail 'Doctor emitted no project checks'
}

test_doctor_before_init_has_missing_project_checks_and_fails() {
  kit_fails doctor
  sed -n '/^project (/,$p' "$SANDBOX/stdout" > "$SANDBOX/project-checks"
  assert_line "$SANDBOX/project-checks" "project ($REPO):"
  assert_contains "$SANDBOX/project-checks" '  MISS  '
}

test_version() {
  kit_ok version
  assert_eq 'agentkit 1.0.0' "$(cat "$SANDBOX/stdout")"
}

test_help() {
  kit_ok help
  assert_contains "$SANDBOX/stdout" 'agentkit init'
}

test_no_arguments_fails() {
  kit_fails
}
