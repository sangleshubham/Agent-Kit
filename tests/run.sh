#!/usr/bin/env bash
# Run from any directory with: bash /path/to/tests/run.sh
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KIT_DIR=$(cd -- "$TEST_DIR/.." && pwd -P)
export KIT_DIR

strip_ansi() { sed $'s/\033\\[[0-9;]*[[:alpha:]]//g'; }

fail() {
  printf '%s\n' "$*" >&2
  if [[ -f ${SANDBOX:-}/stderr ]]; then
    printf '%s\n' 'Last command stderr:' >&2
    cat "$SANDBOX/stderr" >&2
  fi
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "Expected [$1], got [$2]${3:+: $3}"
}

assert_file() { [[ -f "$1" ]] || fail "Missing file: $1"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "Missing [$2] in $1"; }
assert_line() { grep -qxF -- "$2" "$1" || fail "Missing exact line [$2] in $1"; }
assert_same() { cmp -s -- "$1" "$2" || fail "Files differ: $1 and $2"; }

# Keep status and both streams available, including for expected command failures.
capture() {
  if "$@" > "$SANDBOX/stdout.raw" 2> "$SANDBOX/stderr.raw"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
  strip_ansi < "$SANDBOX/stdout.raw" > "$SANDBOX/stdout"
  strip_ansi < "$SANDBOX/stderr.raw" > "$SANDBOX/stderr"
}

kit_ok() {
  capture "$KIT_DIR/agentkit" "$@"
  assert_eq 0 "$RUN_STATUS" "agentkit $*"
}

kit_fails() {
  capture "$KIT_DIR/agentkit" "$@"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "Expected agentkit $* to fail"
}

setup_sandbox() {
  export HOME="$SANDBOX/home" CODEX_HOME="$SANDBOX/codex" TMPDIR="$SANDBOX/tmp"
  mkdir -p "$HOME" "$CODEX_HOME" "$TMPDIR" "$SANDBOX/bin"
  # Ignore inherited git repositories, config injections, identities and hooks.
  local var
  for var in ${!GIT_@}; do unset "$var"; done
  export GIT_CEILING_DIRECTORIES="$TEST_DIR"
  export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=file
  export GIT_AUTHOR_NAME='Agentkit Test' GIT_AUTHOR_EMAIL='test@example.invalid'
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  printf '[core]\n\thooksPath = /dev/null\n[commit]\n\tgpgSign = false\n' > "$GIT_CONFIG_GLOBAL"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_MODEL=opus CODEX_MODEL=gpt-6.1-sol CODEX_EFFORT=high CODEX_NETWORK=false
  unset CLAUDE_CODE_OAUTH_TOKEN AGENTKIT_COMPANION CLAUDE_PLUGIN_DATA
  # Doctor may call installed CLIs. Never query a real login or plugin service.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/bin/claude"
  cp "$SANDBOX/bin/claude" "$SANDBOX/bin/codex"
  chmod +x "$SANDBOX/bin/claude" "$SANDBOX/bin/codex"
  # A regression in --no-install must fail locally instead of installing packages.
  local package_manager
  for package_manager in npm pnpm yarn go uv pip poetry; do
    printf '#!/usr/bin/env bash\nprintf "Unexpected package install\\n" >&2\nexit 99\n' > "$SANDBOX/bin/$package_manager"
    chmod +x "$SANDBOX/bin/$package_manager"
  done
  export PATH="$SANDBOX/bin:$PATH"
  REPO="$SANDBOX/project with spaces"
  mkdir -p "$REPO"
  git init --quiet --initial-branch=fixture-base "$REPO"
  cd "$REPO"
}

commit_fixture() {
  printf 'fixture\n' > "$REPO/fixture.txt"
  git -C "$REPO" add --all
  git -C "$REPO" commit --quiet -m 'Test fixture'
}

snapshot_files() {
  find "$REPO" "$CODEX_HOME" -type f ! -path "$REPO/.git/*" -print0 |
    sort -z | xargs -0 -r sha256sum > "$1"
}

settings_check() {
  node -e '
    const fs = require("fs"), s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (!eval(process.argv[2])) process.exit(1);
  ' "$REPO/.claude/settings.json" "$1" || fail "Settings assertion failed: $1"
}

# Test files only define functions; each test executes below in a fresh subshell.
shopt -s nullglob
for test_file in "$TEST_DIR"/*.sh; do
  [[ "$test_file" == "$TEST_DIR/run.sh" ]] && continue
  # shellcheck disable=SC1090
  source "$test_file" || exit 1
done
mapfile -t test_names < <(compgen -A function test_ | LC_ALL=C sort)
if (( ${#test_names[@]} == 0 )); then
  printf 'FAIL: no test_* functions found\n' >&2
  exit 1
fi

passed=0
failed=0
for test_name in "${test_names[@]}"; do
  SANDBOX=$(mktemp -d "$TEST_DIR/.sandbox.XXXXXXXX") || exit 1
  trap 'rm -rf -- "$SANDBOX" "$SANDBOX.log"; exit 130' INT TERM
  (
    set -euo pipefail
    trap 'rm -rf -- "$SANDBOX"' EXIT
    setup_sandbox
    "$test_name"
  ) > "$SANDBOX.log" 2>&1
  test_status=$?
  if (( test_status == 0 )); then
    printf 'ok   %s\n' "$test_name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$test_name"
    failed=$((failed + 1))
  fi
  strip_ansi < "$SANDBOX.log"
  rm -f -- "$SANDBOX.log"
done
printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "${#test_names[@]}"
(( failed == 0 ))
