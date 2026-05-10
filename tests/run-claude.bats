#!/usr/bin/env bats

load test_helper

@test "run-claude.sh is executable" {
  [ -x "$REPO_ROOT/run-claude.sh" ]
}

# ── F1: credentials dual-mount overlap ──────────────────────────
# The cred mount must be skipped when CREDS_FILE lives inside CLAUDE_DIR
# (e.g. canonical $HOME/.claude/.credentials.json). is_path_under_dir is
# the helper that decides this.

@test "is_path_under_dir: file directly in dir → success" {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/sub"
  touch "$tmpdir/sub/file"
  run bash -c "source '$REPO_ROOT/run-claude.sh' && is_path_under_dir '$tmpdir/sub/file' '$tmpdir/sub'"
  rm -rf "$tmpdir"
  assert_success
}

@test "is_path_under_dir: file outside dir → failure" {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/sub"
  touch "$tmpdir/file"
  run bash -c "source '$REPO_ROOT/run-claude.sh' && is_path_under_dir '$tmpdir/file' '$tmpdir/sub'"
  rm -rf "$tmpdir"
  assert_failure
}

@test "is_path_under_dir: prefix-overlap (.claudefoo vs .claude) → failure" {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.claude" "$tmpdir/.claudefoo"
  touch "$tmpdir/.claudefoo/file"
  run bash -c "source '$REPO_ROOT/run-claude.sh' && is_path_under_dir '$tmpdir/.claudefoo/file' '$tmpdir/.claude'"
  rm -rf "$tmpdir"
  assert_failure
}
