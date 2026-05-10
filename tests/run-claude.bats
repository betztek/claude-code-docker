#!/usr/bin/env bats

load test_helper

@test "run-claude.sh is executable" {
  [ -x "$REPO_ROOT/run-claude.sh" ]
}
