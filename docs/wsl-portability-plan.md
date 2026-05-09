# Plan: Get claude-code-docker running on Windows (WSL) and prep an upstream PR

## Where this plan lives

**Canonical location (in repo, committed on `wsl-portability` branch):** `docs/wsl-portability-plan.md`

The plan is committed in the working branch so it follows the user's fork across machines. It is **not** part of the diff sent to upstream — Phase 6 strips it before opening the PR by cherry-picking the actual code commits onto a clean branch. Until Phase 6, this file is allowed to be edited by any agent picking up a chunk; just commit the update with a `docs(plan):` prefix so it's easy to filter out later.

**For agents picking up mid-stream:** open `docs/wsl-portability-plan.md`, find the first unchecked box in the Status section, and start that chunk.

## How to use this plan

This plan is structured so any agent (a fresh session, a subagent, or the user themselves) can pick up at the next unfinished chunk **without re-reading the whole conversation**. Each chunk is self-contained: pre-conditions, work, commits, and a stop-gate.

**Working rules:**
1. **Do exactly one chunk per agent invocation, then stop.** At the stop-gate, summarize what was done and ask the user for the go-ahead before starting the next chunk.
2. **Commit often.** Each chunk lists explicit commit points. Err toward smaller commits — a typo fix or single-helper refactor warrants its own commit. Conventional Commits style (`test:`, `fix:`, `docs:`, `chore:`, `ci:`).
3. **Update the Status section** in `docs/wsl-portability-plan.md` at the end of every chunk so the next agent knows where we are. Also append observations to "Phase 2 findings" or other sections as relevant. Plan-file updates should be committed with a `docs(plan):` prefix so Phase 6 can filter them out.
4. **Don't skip ahead.** If a chunk reveals that a later chunk's plan is wrong, stop and report — don't replan unilaterally.
5. **Stay on the feature branch** (`wsl-portability`). Never commit to `main`.
6. **No force-pushing, no rebasing published commits, no `git push` until Phase 6** — work is local until then.
7. **Plan-file commits use `docs(plan):` prefix.** Code commits use the normal `feat:` / `fix:` / `test:` / `chore:` / `ci:` prefixes. This makes it trivial in Phase 6 to identify which commits to drop from the upstream PR.

## Status (update at end of each chunk)

- [x] **Phase 0** — Workspace hygiene (branch created, plan committed to `docs/`)
- [x] **Phase 1** — WSL + Docker prerequisites verified (apt-installed `docker.io` inside WSL with systemd; `hello-world` works). Repo location decision pending — see Phase 1 stop-gate.
- [x] **Phase 6 (partial, early)** — Fork at `betztek/claude-code-docker` created; `origin` points at fork, `upstream` at `cdowin/claude-code-docker`; `main` and `wsl-portability` pushed. Plan-strip + actual PR open still happen at the real Phase 6.
- [ ] **Phase 2** — Smoke run + failure list captured (no commits; appended to this plan)
- [ ] **Phase 3** — bats harness scaffold landed
- [ ] **Phase 4a** — TDD: timezone detection
- [ ] **Phase 4b** — TDD: auth-method selection (Keychain guard)
- [ ] **Phase 4c** — TDD: gh-token fallback
- [ ] **Phase 4d** — TDD: any other failures from Phase 2
- [ ] **Phase 5** — README WSL section
- [ ] **Phase 6** — Fork, push, open PR

(Phases 4a–4d may be reordered or trimmed once Phase 2 produces the real failure list.)

## Context

`claude-code-docker` is a third-party wrapper that runs Claude Code in persistent, sandboxed Docker containers, controlled by a host-side bash orchestrator ([run-claude.sh](run-claude.sh)). It targets macOS and Linux today — calls macOS Keychain (`security`), reads `/etc/timezone`, assumes `gh` is on PATH. The current clone is a plain clone of upstream `cdowin/claude-code-docker` (not a fork). There are **no tests**.

The user wants to (a) run it on Windows via WSL2, (b) drive the work with red/green TDD, and (c) eventually open a PR upstream. Decisions confirmed:

- **Fork later.** Work local until Phase 6.
- **Docker Desktop with WSL2 integration.** Not yet installed.
- **PR scope: WSL portability + bats test harness.** Reviewable diff.
- **Auth method: `file`**, pointing at `/mnt/c/Users/<windows-user>/.claude/.credentials.json` from inside WSL.

TDD fits because the host script has discrete helpers (timezone, auth, image resolution) with no current coverage — exactly the seams to test, and exactly where Windows portability bugs live.

---

## Phase 0 — Workspace hygiene + plan relocation

**Pre-conditions:** Plan approved. On `main`, clean tree.

**Work:**
- `git checkout -b wsl-portability`
- `mkdir -p .claude/plans`
- Copy the plan from `~/.claude/plans/i-would-like-to-spicy-moon.md` to `.claude/plans/wsl-portability.md`. From inside the repo, in WSL/bash: `cp ~/.claude/plans/i-would-like-to-spicy-moon.md .claude/plans/wsl-portability.md` (Windows path equivalent if running from PowerShell).
- Add `/.claude/` to `.git/info/exclude` (local-only ignore — never committed, never shown in PRs):
  ```bash
  echo '/.claude/' >> .git/info/exclude
  ```
- Verify `git status` shows the `.claude/` directory as ignored (it should not appear in untracked files).

**Commits:** None (branch creation + local-only files).

**Stop-gate:** Confirm:
- Branch `wsl-portability` is checked out
- `.claude/plans/wsl-portability.md` exists in the repo
- `git status` is clean (no untracked `.claude/` showing)

Update Status checkbox in `.claude/plans/wsl-portability.md`. Hand back to user with a one-line summary and ask for go-ahead on Phase 1.

---

## Phase 1 — WSL + Docker prerequisites (one-time, host-level setup)

**Pre-conditions:** Phase 0 complete. User has admin on the Windows machine.

**Decision:** install Docker engine **inside WSL via apt** (not Docker Desktop). Reasons: (a) cleaner README story for the upstream PR — `sudo apt install docker.io` is unambiguous and needs no curl-pipe-sh or third-party apt repo, (b) no Docker Desktop license to worry about, (c) self-contained inside WSL.

**Work (run from a WSL shell — no need to know the distro name):**

1. From PowerShell: `wsl --list --verbose` to confirm a WSL2 distro exists. If none, `wsl --install -d Ubuntu` and reboot if prompted.
2. Open the WSL shell. Enable systemd so `dockerd` autostarts each session:
   ```bash
   sudo bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
   exit
   ```
3. From PowerShell: `wsl --shutdown` (so systemd takes effect).
4. Open a fresh WSL shell. Verify systemd is PID 1, then install Docker:
   ```bash
   ps -p 1 -o comm=                # should print "systemd"
   sudo apt-get update
   sudo apt-get install -y docker.io
   sudo usermod -aG docker $USER
   exit
   ```
5. From PowerShell: `wsl --shutdown` again (so the docker group membership applies).
6. Open a fresh WSL shell and verify:
   ```bash
   docker version                  # client + server both shown
   docker run --rm hello-world
   ```
7. **Decide repo location inside WSL.** Recommended: fresh `git clone https://github.com/betztek/claude-code-docker.git ~/claude-code-docker && cd ~/claude-code-docker && git checkout wsl-portability`. This avoids `/mnt/c` permission/perf quirks. Cloning the **fork** (not upstream) means the WIP branch is already there.
   - Alternative if working from `/mnt/c`: paths with spaces (e.g. `/mnt/c/Users/<windows-user>/IT\ Docs/Software/claude-code-docker`) are useful test fixtures but slow on `/mnt/c` — only use this if cross-mounting is needed.

**Commits:** None.

**Stop-gate:** Report `docker version` output and which repo location was chosen. Ask user for go-ahead on Phase 2.

### Cross-system workflow

The fork lives at `https://github.com/betztek/claude-code-docker.git`. To pick up work on a new machine after Phase 1 is done there:

```bash
git clone https://github.com/betztek/claude-code-docker.git
cd claude-code-docker
git checkout wsl-portability
# read docs/wsl-portability-plan.md, find first unchecked Status box, continue
```

No need to redo `.git/info/exclude` — the plan now lives in `docs/` (committed), not `.claude/` (local-only). Each Phase 1 setup (systemd + Docker install) is per-machine and not repeatable from the repo state, so do that first on any new system.

---

## Phase 2 — Smoke run as-is, capture the failure list

**Pre-conditions:** Phase 1 complete. WSL has working `docker`, repo cloned/accessible inside WSL, on `wsl-portability` branch.

**Work:**
1. `cp claude-docker.conf.example claude-docker.conf`
2. Edit `claude-docker.conf`:
   - `auth_method=file`
   - `claude_credentials_file=<path to your .credentials.json>`. Two reasonable choices on WSL:
     - **Bridge to Windows-side credentials:** `/mnt/c/Users/<you>/.claude/.credentials.json` if Claude Code on Windows has already authed and you want to reuse that file.
     - **WSL-native:** authenticate Claude Code from inside WSL once (so a credentials file lives at `~/.claude/.credentials.json`) and use that path. Cleaner if the WSL machine will be your primary driver.
   - `default_workspace=$HOME/work` (or chosen path; create dir if absent)
3. `./run-claude.sh smoke` — capture stdout + stderr verbatim.
4. If it boots: `docker exec claude-smoke claude --version`, then `./run-claude.sh --rm smoke`.
5. **Append findings to the "Phase 2 findings" section of this plan**, with each failure as a bullet: file, line, what failed, expected behavior on WSL.

**Commits:** None (this phase is investigation; the plan-file edit is local-only context).

**Stop-gate:** Show user the failure list. Ask whether the proposed Phase 4 sub-chunks (4a–4d) cover everything, need additions, or need re-prioritization.

---

## Phase 3 — bats harness scaffold

**Pre-conditions:** Phase 2 complete with failure list.

**Work:**
1. Add bats as **vendored git submodules** under `tests/lib/` (so upstream CI doesn't depend on apt):
   - `git submodule add https://github.com/bats-core/bats-core.git tests/lib/bats-core`
   - `git submodule add https://github.com/bats-core/bats-support.git tests/lib/bats-support`
   - `git submodule add https://github.com/bats-core/bats-assert.git tests/lib/bats-assert`
2. Create `tests/test_helper.bash` that sources `bats-support` and `bats-assert`.
3. Create `tests/run-claude.bats` with a single smoke test: `@test "run-claude.sh is executable"` → asserts `[ -x run-claude.sh ]`.
4. Add the `BASH_SOURCE` main-guard to [run-claude.sh](run-claude.sh): wrap the bottom invocation in `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi` (extract a `main()` if needed). This is the one structural change so bats can `source` the script and call helpers without running it.
5. Run `tests/lib/bats-core/bin/bats tests/` — must be green.
6. Add `.github/workflows/test.yml`:
   - Trigger on `push` and `pull_request`
   - Runs `tests/lib/bats-core/bin/bats tests/`
   - `actions/checkout@v4` with `submodules: recursive`

**Commits (in this order, each its own commit):**
- `chore: vendor bats-core, bats-support, bats-assert as submodules`
- `refactor: gate run-claude.sh main with BASH_SOURCE guard for sourcability`
- `test: add bats harness scaffold and smoke test`
- `ci: run bats on push and pull_request`

**Stop-gate:** All four commits made, `bats tests/` green locally. Ask user for go-ahead on Phase 4a.

---

## Phase 4 — Red/green TDD, one bug per sub-chunk

Each sub-chunk follows the same pattern. **Do exactly one sub-chunk per agent invocation.**

### Per-sub-chunk pattern

**Pre-conditions:** Previous sub-chunk green and committed.

**Work:**
1. **Red:** add a `@test` to `tests/run-claude.bats` that calls the relevant helper function with WSL-realistic inputs and asserts the desired output. Run bats — confirm it fails for the right reason (not a syntax error or missing function).
2. **Commit red:** `test: add failing case for <bug>`. Yes, commit a known-failing test — small, reversible, lets a future bisect see exactly when each fix landed. (If user prefers green-only history, squash red+green into one commit instead — note this preference in feedback memory.)
3. **Green:** if the helper isn't a function yet, extract it from inline code into a named function (mechanical refactor — usually a 5–15 line block). Then fix the bug minimally. Re-run bats — green.
4. **Commit green:** `fix: <one-line description of bug>`.
5. Update the Status checkbox for this sub-chunk.

**Stop-gate:** Report the diff (`git log --oneline upstream/main..HEAD` or similar) and ask for go-ahead on the next sub-chunk.

### Likely sub-chunks (final list set after Phase 2)

- **4a** — Timezone detection ([run-claude.sh:272](run-claude.sh#L272)). Test: with `/etc/timezone` present (Ubuntu/WSL case) → returns its contents; with it absent → returns `Etc/UTC` or graceful fallback without stderr noise.
- **4b** — `security` Keychain guard ([run-claude.sh:106](run-claude.sh#L106)). Test: when `command -v security` returns nonzero (non-macOS) and `auth_method=file`, the script doesn't try to call `security` and proceeds with file auth.
- **4c** — `gh auth token` fallback ([run-claude.sh:244](run-claude.sh#L244)). Test: when `gh` not on PATH, script doesn't error out; it falls back / skips token injection cleanly.
- **4d** — Anything else surfaced by Phase 2.
  - **Revisit `.gitattributes`** (added pre-Phase-2 to unblock WSL/`/mnt/c` work — see Phase 2 findings). Confirm coverage (`*.sh`, `*.bash`, `*.bats`) is still right by then; consider whether `Dockerfile`, `*.yml`, `*.md` should also be pinned to LF, and whether a `* text=auto` baseline is wanted.

---

## Phase 5 — Documentation

**Pre-conditions:** All Phase 4 sub-chunks green and committed.

**Work:**
- Add "## Running on Windows (WSL2)" section to [README.md](README.md). Cover: prerequisites (Docker Desktop + WSL integration), the `auth_method=file` recipe with the `/mnt/c/...` credentials path, the smoke-test command, any caveats discovered in Phase 2.
- Add a brief "## Running tests" section: `tests/lib/bats-core/bin/bats tests/`.

**Commits:**
- `docs: document WSL2 setup`
- `docs: add running-tests section`

**Stop-gate:** Ask user to read the README diff. Go-ahead on Phase 6.

---

## Phase 6 — Fork, strip plan, push, open PR

**Note:** Fork creation and remote rewiring may have been done earlier (out of phase order) for cross-machine convenience. If `origin` already points at the user's fork and `upstream` points at `cdowin/claude-code-docker`, skip steps 1–3.

**Pre-conditions:** All earlier phases done. `git status` clean. `tests/lib/bats-core/bin/bats tests/` green. CI green on the feature branch (after we push).

**Work:**
1. Fork via `gh repo fork cdowin/claude-code-docker --remote=false --clone=false` (or web UI).
2. `git remote rename origin upstream`
3. `git remote add origin <your-fork-url>`
4. **Strip the plan from a clean PR branch:**
   - `git checkout -b wsl-portability-pr upstream/main`
   - Cherry-pick every commit on `wsl-portability` *except* those with `docs(plan):` prefix:
     ```bash
     git log --reverse --format='%H %s' upstream/main..wsl-portability \
       | grep -v 'docs(plan):' \
       | awk '{print $1}' \
       | xargs -n1 git cherry-pick
     ```
   - Verify the branch contains zero references to `docs/wsl-portability-plan.md`: `git diff upstream/main -- docs/wsl-portability-plan.md` should be empty.
5. `git push -u origin wsl-portability` (so the fork has the full WIP branch with plan, for cross-machine work)
6. `git push -u origin wsl-portability-pr` (clean branch for the upstream PR)
7. Wait for CI to be green on `wsl-portability-pr`.
8. `gh pr create --repo cdowin/claude-code-docker --base main --head <fork>:wsl-portability-pr` with a body covering: motivation (WSL2 support), summary of changes, test harness rationale, manual test instructions.

**Commits:** None new (cherry-picks reuse existing commits).

**Stop-gate:** PR URL shared with user.

---

## Phase 2 findings

**Pre-Phase-2 (line-endings, surfaced while bringing up `/mnt/c` workflow on a second machine):**
- All tracked shell scripts (`entrypoint.sh`, `init-firewall.sh`, `run-claude.sh`, `statusline.sh`) checked out as CRLF on Windows under default `core.autocrlf=true`. The repo's index is LF — only the working-tree checkout was mangled. Bash refuses `#!/bin/bash\r`, so `run-claude.sh` would not execute as-is from `/mnt/c`.
- Fix: added `.gitattributes` pinning `*.sh`, `*.bash`, `*.bats` to `eol=lf`. Force-re-checkout applied to working tree. Decision to land this now (rather than in 4d) was deliberate so the fix follows the repo across machines via OneDrive.
- Revisit in 4d (see Phase 4 likely-sub-chunks list).

(populate further during Phase 2)

---

## Critical files

- [run-claude.sh](run-claude.sh) — primary edit target
- [README.md](README.md) — WSL section
- `tests/run-claude.bats` (new)
- `tests/test_helper.bash` (new)
- `tests/lib/bats-*` (new submodules)
- `.github/workflows/test.yml` (new)
- [.github/workflows/publish.yml](.github/workflows/publish.yml) — leave alone

## Out of scope

- Native Windows / PowerShell port.
- Tests for container-side scripts ([entrypoint.sh](entrypoint.sh), [init-firewall.sh](init-firewall.sh)) — needs in-container test rig; separate PR.
- Reorganizing the script into multiple files.
