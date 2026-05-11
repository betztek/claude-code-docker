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

# ── F2: container chown corrupts host ~/.claude ownership ───────
# Fix shape: run-claude.sh passes HOST_UID/HOST_GID; entrypoint.sh aligns
# claude user's UID to match, so bind-mounted ~/.claude is naturally
# accessible without an unconditional recursive chown that propagates to
# the host on Linux/WSL.

@test "F2: run-claude.sh passes HOST_UID and HOST_GID to docker run" {
  run grep -E 'HOST_UID|HOST_GID' "$REPO_ROOT/run-claude.sh"
  assert_success
}

@test "F2: entrypoint.sh does not unconditionally recurse-chown bind mounts" {
  # An unindented (top-level / unconditional) chown -R of the bind-mounted
  # ~/.claude is the F2 bug. Indented (inside an else-branch fallback) is
  # acceptable because the UID-matching path skips it.
  run grep -E '^chown -R claude:claude /home/claude/\.claude' "$REPO_ROOT/entrypoint.sh"
  assert_failure
}

# ── F3: non-TTY graceful degradation ─────────────────────────────
# Without a TTY, `docker exec -it` errors with 'the input device is not a TTY'
# and the script exits 1, masking a successful container boot. The fix is an
# attach_to_container helper that gates -it on stdin/stdout being TTYs and
# prints a hint otherwise.

@test "F3: attach_to_container returns 0 with hint when no TTY" {
  run bash -c "
    source '$REPO_ROOT/run-claude.sh' || exit 1
    exec </dev/null
    attach_to_container claude-smoke
  "
  assert_success
  assert_output --partial "TTY"
}
