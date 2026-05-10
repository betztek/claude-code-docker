# Shared bats setup. Test files: `load test_helper` at the top.
load 'lib/bats-support/load'
load 'lib/bats-assert/load'

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
