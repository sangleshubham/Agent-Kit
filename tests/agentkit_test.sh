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
  assert_contains AGENTS.md 'Builders (Codex, complex-implementer) never commit'
  assert_contains CLAUDE.md 'agentkit codex <unit>'
  assert_contains CLAUDE.md 'agentkit wt <B> agent/<A>'
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

test_init_replaces_claude_symlink_to_agents() {
  printf '# Shared rules\nKeep these bytes, including the final newline.\n' > AGENTS.md
  cp AGENTS.md "$SANDBOX/original-agents"
  ln -s AGENTS.md CLAUDE.md
  kit_ok init
  [[ -f CLAUDE.md && ! -L CLAUDE.md ]] || fail 'CLAUDE.md must become a regular file'
  assert_eq '@AGENTS.md' "$(head -n1 CLAUDE.md)"
  assert_eq 1 "$(grep -cF 'agentkit:begin' CLAUDE.md)"
  assert_same "$SANDBOX/original-agents" AGENTS.md
  if grep -qE 'agentkit:begin|@AGENTS\.md' AGENTS.md; then
    fail 'Orchestration instructions leaked into AGENTS.md'
  fi
}

test_init_rejects_agents_symlink() {
  printf '# User instructions\nKeep exactly these bytes.' > CLAUDE.md
  cp CLAUDE.md "$SANDBOX/original-claude"
  ln -s CLAUDE.md AGENTS.md
  kit_fails init
  assert_contains "$SANDBOX/stderr" 'AGENTS.md is a symlink'
  [[ -L AGENTS.md ]] || fail 'AGENTS.md symlink was replaced'
  assert_eq CLAUDE.md "$(readlink AGENTS.md)"
  assert_same "$SANDBOX/original-claude" CLAUDE.md
  assert_same "$SANDBOX/original-claude" AGENTS.md
}

test_init_rejects_claude_symlink_to_other_file() {
  printf '# Shared rules\n' > AGENTS.md
  printf '# Other instructions\nKeep these bytes.' > other.md
  cp AGENTS.md "$SANDBOX/original-agents"
  cp other.md "$SANDBOX/original-other"
  ln -s other.md CLAUDE.md
  kit_fails init
  assert_contains "$SANDBOX/stderr" 'CLAUDE.md is a symlink'
  [[ -L CLAUDE.md ]] || fail 'CLAUDE.md symlink was replaced'
  assert_eq other.md "$(readlink CLAUDE.md)"
  assert_same "$SANDBOX/original-other" other.md
  assert_same "$SANDBOX/original-agents" AGENTS.md
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

test_trust_untrusted_is_preserved_and_doctor_reports_missing() {
  printf '[projects."%s"]\ntrust_level = "untrusted"\n' "$REPO" > "$CODEX_HOME/config.toml"
  cp "$CODEX_HOME/config.toml" "$SANDBOX/trust"
  kit_ok init
  assert_contains "$SANDBOX/stderr" 'trust_level=untrusted'
  assert_eq 1 "$(grep -cxF "[projects.\"$REPO\"]" "$CODEX_HOME/config.toml")"
  assert_same "$SANDBOX/trust" "$CODEX_HOME/config.toml"
  capture "$KIT_DIR/agentkit" doctor
  assert_line "$SANDBOX/stdout" '  MISS  codex trusts project'
}

test_trust_trailing_comment_is_trusted() {
  printf '[projects."%s"]\ntrust_level = "trusted" # user choice\n' "$REPO" > "$CODEX_HOME/config.toml"
  cp "$CODEX_HOME/config.toml" "$SANDBOX/trust"
  kit_ok init
  assert_same "$SANDBOX/trust" "$CODEX_HOME/config.toml"
  capture "$KIT_DIR/agentkit" doctor
  assert_line "$SANDBOX/stdout" '  ok    codex trusts project'
}

test_trust_does_not_leak_from_following_table() {
  printf '[projects."%s"]\n# no trust level here\n[projects."/other"]\ntrust_level = "trusted"\n' \
    "$REPO" > "$CODEX_HOME/config.toml"
  cp "$CODEX_HOME/config.toml" "$SANDBOX/trust"
  kit_ok init
  assert_same "$SANDBOX/trust" "$CODEX_HOME/config.toml"
  capture "$KIT_DIR/agentkit" doctor
  assert_line "$SANDBOX/stdout" '  MISS  codex trusts project'
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

origin_with_newer_release() {
  git init --quiet --bare --initial-branch=release "$SANDBOX/origin.git"
  git remote add origin "$SANDBOX/origin.git"
  git push --quiet origin fixture-base:release
  # Build a newer remote release in a local clone, leaving local release behind.
  git clone --quiet --branch release "$SANDBOX/origin.git" "$SANDBOX/publisher"
  printf 'remote release\n' > "$SANDBOX/publisher/remote.txt"
  git -C "$SANDBOX/publisher" add remote.txt
  git -C "$SANDBOX/publisher" commit --quiet -m 'Remote release fixture'
  git -C "$SANDBOX/publisher" push --quiet origin release
  git fetch --quiet origin
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/release
}

test_wt_explicit_base_used_as_given() {
  commit_fixture
  local local_commit remote_commit
  local_commit=$(git rev-parse HEAD)
  git branch release
  origin_with_newer_release
  remote_commit=$(git rev-parse origin/release)
  [[ "$local_commit" != "$remote_commit" ]] || fail 'Origin fixture did not diverge'
  kit_ok wt u release
  assert_eq "$local_commit" "$(git -C "$REPO/.worktrees/u" rev-parse HEAD)"
  assert_eq 'agent/u' "$(git -C "$REPO/.worktrees/u" branch --show-current)"
  assert_eq "$local_commit" "$(git rev-parse release)"
  assert_contains "$SANDBOX/stderr" '(from release)'
  kit_ok wt v origin/release
  assert_eq "$remote_commit" "$(git -C "$REPO/.worktrees/v" rev-parse HEAD)"
  assert_eq 'agent/v' "$(git -C "$REPO/.worktrees/v" branch --show-current)"
  assert_contains "$SANDBOX/stderr" '(from origin/release)'
}

test_wt_default_base_is_current_branch() {
  commit_fixture
  origin_with_newer_release
  git checkout --quiet -b feature
  printf 'feature\n' > feature.txt
  git add feature.txt
  git commit --quiet -m 'Feature fixture'
  local feature_commit
  feature_commit=$(git rev-parse HEAD)
  [[ "$feature_commit" != "$(git rev-parse origin/HEAD)" ]] || fail 'Origin HEAD must differ'
  kit_ok wt u
  assert_eq "$feature_commit" "$(git -C "$REPO/.worktrees/u" rev-parse HEAD)"
  assert_contains "$SANDBOX/stderr" '(from feature)'
}

test_wt_chained_base() {
  commit_fixture
  kit_ok wt a
  printf 'unit a\n' > "$REPO/.worktrees/a/unit-a.txt"
  git -C "$REPO/.worktrees/a" add unit-a.txt
  git -C "$REPO/.worktrees/a" commit --quiet -m 'Unit A fixture'
  local a_commit
  a_commit=$(git -C "$REPO/.worktrees/a" rev-parse HEAD)
  [[ "$a_commit" != "$(git rev-parse HEAD)" ]] || fail 'Unit A must have its own commit'
  kit_ok wt b agent/a
  assert_eq "$a_commit" "$(git -C "$REPO/.worktrees/b" rev-parse HEAD)"
  assert_contains "$SANDBOX/stderr" '(from agent/a)'
}

# Each line records the executable, its cwd, then each argument separately.
record_installers() {
  export INSTALL_LOG="$SANDBOX/install.log"
  : > "$INSTALL_LOG"
  local manager
  for manager in npm pnpm yarn go uv pip poetry; do
    cat > "$SANDBOX/bin/$manager" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" "$PWD" "$@" >> "$INSTALL_LOG"
SH
    chmod +x "$SANDBOX/bin/$manager"
  done
}

test_wt_installs_go_dependencies() {
  record_installers
  printf 'module example.invalid/fixture\n' > go.mod
  commit_fixture
  kit_ok wt u
  printf '%s\n' go "$REPO/.worktrees/u" mod download > "$SANDBOX/expected-install"
  assert_same "$SANDBOX/expected-install" "$INSTALL_LOG"
}

test_wt_installs_uv_dependencies() {
  record_installers
  touch pyproject.toml uv.lock
  commit_fixture
  kit_ok wt u
  printf '%s\n' uv "$REPO/.worktrees/u" sync > "$SANDBOX/expected-install"
  assert_same "$SANDBOX/expected-install" "$INSTALL_LOG"
}

test_wt_requirements_warns_without_installing() {
  record_installers
  printf 'fixture-package==1.0\n' > requirements.txt
  commit_fixture
  kit_ok wt u
  [[ ! -s "$INSTALL_LOG" ]] || fail 'requirements.txt triggered an install'
  assert_contains "$SANDBOX/stderr" "not running 'pip install"
}

test_wt_no_install_skips_dependencies() {
  record_installers
  printf '.worktrees/\n' > .gitignore
  # Exercise every supported installer and the pip warning path independently.
  local fixture unit=0
  for fixture in npm pnpm yarn go uv requirements; do
    rm -f package.json package-lock.json pnpm-lock.yaml yarn.lock go.mod pyproject.toml uv.lock requirements.txt
    case "$fixture" in
      npm|pnpm|yarn)
        printf '{}\n' > package.json
        case "$fixture" in
          npm) touch package-lock.json ;;
          pnpm) touch pnpm-lock.yaml ;;
          yarn) touch yarn.lock ;;
        esac ;;
      go) printf 'module example.invalid/fixture\n' > go.mod ;;
      uv) touch pyproject.toml uv.lock ;;
      requirements) touch requirements.txt ;;
    esac
    commit_fixture
    unit=$((unit + 1))
    kit_ok wt "u$unit" --no-install
    [[ ! -s "$INSTALL_LOG" ]] || fail "--no-install ran an installer for $fixture"
    if grep -qE 'installing dependencies|not running .pip install' "$SANDBOX/stderr"; then
      fail "--no-install entered dependency handling for $fixture"
    fi
  done
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

test_rm_dirty_worktree_is_kept() {
  commit_fixture
  kit_ok wt dirty --no-install
  printf 'uncommitted change\n' >> "$REPO/.worktrees/dirty/fixture.txt"
  cp "$REPO/.worktrees/dirty/fixture.txt" "$SANDBOX/dirty-fixture"
  kit_fails rm dirty
  [[ -d "$REPO/.worktrees/dirty" ]] || fail 'Dirty worktree directory was removed'
  assert_same "$SANDBOX/dirty-fixture" "$REPO/.worktrees/dirty/fixture.txt"
  git worktree list --porcelain | grep -qxF "worktree $REPO/.worktrees/dirty" ||
    fail 'Dirty worktree is no longer registered'
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
