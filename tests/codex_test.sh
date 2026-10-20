#!/usr/bin/env bash
# Sourced by run.sh. The companion records calls locally; it never invokes Codex.

write_fake_companion() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'JS'
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
fs.writeFileSync(process.env.COMPANION_RECORD, JSON.stringify({
  argv: process.argv.slice(2),
  cwd: process.cwd(),
  stdin: fs.readFileSync(0, 'utf8'),
  pluginData: process.env.CLAUDE_PLUGIN_DATA,
  script: fileURLToPath(import.meta.url),
}));
JS
}

setup_codex_fixture() {
  commit_fixture
  kit_ok wt u --no-install
  export AGENTKIT_COMPANION="$SANDBOX/fake companion.mjs"
  export COMPANION_RECORD="$SANDBOX/companion.json"
  write_fake_companion "$AGENTKIT_COMPANION"
}

assert_companion_args() {
  assert_file "$COMPANION_RECORD"
  node -e '
    const fs = require("fs"), record = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expected = process.argv.slice(2);
    if (JSON.stringify(record.argv) !== JSON.stringify(expected)) {
      console.error("Expected argv", expected, "got", record.argv);
      process.exit(1);
    }
  ' "$COMPANION_RECORD" "$@" || fail 'Companion argv differs'
}

companion_check() {
  assert_file "$COMPANION_RECORD"
  node -e '
    const fs = require("fs"), r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (!eval(process.argv[2])) process.exit(1);
  ' "$COMPANION_RECORD" "$1" || fail "Companion assertion failed: $1"
}

test_codex_task_args_and_default_plugin_data() {
  setup_codex_fixture
  kit_ok codex u 'do x' </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" 'do x'
  companion_check 'r.cwd === process.cwd() && r.stdin === ""'
  companion_check 'r.pluginData === process.env.HOME + "/.claude/plugins/data/codex-openai-codex"'
}

test_codex_resume_model_and_effort() {
  setup_codex_fixture
  kit_ok codex u --resume --model m --effort high 'do x' </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" --resume-last --model m --effort high 'do x'
}

test_codex_prompt_file_is_absolute() {
  setup_codex_fixture
  mkdir -p rel
  printf 'prompt fixture\n' > rel/path
  kit_ok codex u --prompt-file rel/path </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" --prompt-file "$REPO/rel/path"
}

test_codex_forwards_stdin() {
  setup_codex_fixture
  printf hello | kit_ok codex u
  assert_companion_args task --write --cwd "$REPO/.worktrees/u"
  companion_check 'r.stdin === "hello"'
}

test_codex_control_commands() {
  setup_codex_fixture
  local subcommand
  for subcommand in status result cancel; do
    rm -f "$COMPANION_RECORD"
    kit_ok codex u "$subcommand" </dev/null
    assert_companion_args "$subcommand" --cwd "$REPO/.worktrees/u"
  done
}

test_codex_preserves_existing_plugin_data() {
  setup_codex_fixture
  export CLAUDE_PLUGIN_DATA="$SANDBOX/custom plugin data"
  kit_ok codex u 'do x' </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" 'do x'
  companion_check 'r.pluginData === process.env.CLAUDE_PLUGIN_DATA'
}

test_codex_no_name_fails() {
  setup_codex_fixture
  kit_fails codex </dev/null
  assert_contains "$SANDBOX/stderr" 'usage: agentkit codex <name>'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran without a name'
}

test_codex_missing_worktree_fails() {
  setup_codex_fixture
  kit_fails codex missing 'do x' </dev/null
  assert_contains "$SANDBOX/stderr" 'no worktree at'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran for a missing worktree'
}

test_codex_unknown_option_fails() {
  setup_codex_fixture
  kit_fails codex u --unknown </dev/null
  assert_contains "$SANDBOX/stderr" 'unknown option --unknown'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran with an unknown option'
}

test_codex_model_without_value_fails() {
  setup_codex_fixture
  kit_fails codex u --model </dev/null
  assert_contains "$SANDBOX/stderr" '--model needs a value'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran without a model value'
}

test_codex_missing_prompt_file_fails() {
  setup_codex_fixture
  kit_fails codex u --prompt-file rel/missing </dev/null
  assert_contains "$SANDBOX/stderr" '--prompt-file needs an existing file'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran with a missing prompt file'
}

test_codex_missing_companion_fails() {
  setup_codex_fixture
  unset AGENTKIT_COMPANION
  mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex"
  kit_fails codex u 'do x' </dev/null
  assert_contains "$SANDBOX/stderr" 'Codex plugin not found under'
  [[ ! -e "$COMPANION_RECORD" ]] || fail 'Companion ran from an empty plugin cache'
}

test_codex_discovers_newest_companion_version() {
  setup_codex_fixture
  unset AGENTKIT_COMPANION
  local cache="$HOME/.claude/plugins/cache/openai-codex/codex"
  write_fake_companion "$cache/1.0.6/scripts/codex-companion.mjs"
  write_fake_companion "$cache/1.0.10/scripts/codex-companion.mjs"
  kit_ok codex u 'do x' </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" 'do x'
  companion_check 'r.script === process.env.HOME + "/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts/codex-companion.mjs"'
}

test_codex_from_linked_worktree_targets_main_checkout() {
  setup_codex_fixture
  kit_ok wt other --no-install
  mkdir -p "$REPO/.worktrees/other/subdir"
  cd "$REPO/.worktrees/other/subdir" || fail 'Could not enter another worktree'
  kit_ok codex u 'do x' </dev/null
  assert_companion_args task --write --cwd "$REPO/.worktrees/u" 'do x'
  companion_check 'r.cwd === process.cwd()'
}
