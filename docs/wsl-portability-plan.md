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
- [x] **Phase 2** — Smoke run + failure list captured. Three findings (F1, F2, F3) plus the build-vs-pull observation logged below. Container boots and `claude --version` works inside it once F1 is worked around.
- [x] **Phase 3** — bats harness scaffold landed (4 commits: vendored submodules, BASH_SOURCE main-guard, test scaffold, CI workflow). `tests/lib/bats-core/bin/bats tests/` green locally; CI workflow at `.github/workflows/test.yml` triggers on push + PR.
- [x] **Phase 4a** — TDD: F1 fixed (credentials dual-mount overlap). New `is_path_under_dir` helper in `run-claude.sh`; CRED_ARGS construction skips the `/mnt/host-credentials.json` mount when CREDS_FILE is inside CLAUDE_DIR. Defensive `-ef` guard added to entrypoint. 3 bats cases + 1 smoke (executable check) green. End-to-end smoke booted cleanly with canonical `~/.claude/.credentials.json`.
- [x] **Phase 4b** — TDD: F2 fixed (container chown corrupts host `~/.claude` ownership on Linux). run-claude.sh passes HOST_UID/HOST_GID to docker run; entrypoint edits /etc/passwd and /etc/group directly via sed (intentionally NOT `usermod -u`, which auto-chowns the home dir and propagates through the bind mount — that's the trap that bit the first attempt). Legacy chown -R is preserved as an else-branch fallback for callers that don't pass HOST_UID. End-to-end smoke: host `~/.claude` ownership unchanged before/after run.
- [x] **Phase 4c** — TDD: F3 fixed. New `attach_to_container` helper at top of `run-claude.sh` gates the `docker exec -it` on `[ -t 0 ] && [ -t 1 ]`; non-TTY callers get a one-line manual-attach hint and exit 0. Both call sites (reconnect-to-running and wait-for-setup) updated. 7/7 bats green; end-to-end smoke in our non-TTY harness now exits 0 with the hint instead of 1 with the cryptic TTY error.
- [x] **Phase 4d** — Regression coverage + `.gitattributes` review. Four commits: regression bats cases (red), `resolve_timezone` extraction (green), keychain non-mac error now suggests `AUTH_METHOD=file`, `.gitattributes` extended with `* text=auto` baseline + Dockerfile/*.yml/*.yaml LF pins. 12/12 bats green.
- [x] **Phase 5** — README WSL section + running-tests section landed. Updated Requirements + the macOS-only Note to reflect that Linux/WSL2 is now supported via `auth_method=file`.
- [ ] **Phase 6** — Fork, push, open PR

(Phases 4a–4d may be reordered or trimmed once Phase 2 produces the real failure list.)

## Handoff notes (cold-pickup reference)

State on the active machine (`/mnt/c/Users/jerem/OneDrive/git-sync/claude-code-docker`) as of Phase 5 close:

- Branch `wsl-portability` is **26 commits ahead of `origin/wsl-portability`** and has not been pushed since `664a528` (the last email-scrub force-push, before any of the Phase 3/4/5 work). All subsequent commits are local-only.
- The pending push is blocked on GitHub OAuth `workflow` scope. The CI workflow file (`.github/workflows/test.yml`) added in Phase 3 requires it. Resolution: create a classic PAT at https://github.com/settings/tokens with `repo` + `workflow` scopes, then `git push origin wsl-portability` and paste the token when Git Credential Manager prompts (alternative: register `~/.ssh/id_rsa.pub` with GitHub and switch `origin` to SSH).
- Local artifacts not in the repo:
  - `claude-docker.conf` (gitignored) currently points at `claude-code-test` with credentials at `$HOME/.claude/.credentials.json` — the canonical Linux path now that F1 is fixed.
  - Docker image `claude-code-test` was built ad-hoc on top of `ghcr.io/cdowin/claude-code-docker:latest` via the test-image-overlay recipe (see Phase 4 lessons). Used for smoke runs that exercise our entrypoint changes without a 5-minute full rebuild.
  - `~/.claude.broken-by-f2.*` dirs in WSL home are orphan snapshots from earlier pre-F2-fix smoke runs. Safe to `rm -rf`.
- **OneDrive caveat:** the repo lives under `/mnt/c/Users/jerem/OneDrive/git-sync/`. `.git/` *is* syncing through OneDrive across the two Windows machines. Don't write `.git/` from both machines simultaneously — OneDrive's last-writer-wins can corrupt pack files or refs. Treat as soft "one machine at a time" while iterating.
- Two general workflow memories live at `~/.claude/projects/.../memory/` for this project: `workflow_test_image_overlay.md` (fast-iteration recipe for container changes) and `workflow_clean_baseline_for_state_bug_verification.md` (reset state before each fix-verification run).

## Pre-Phase-6 dogfooding checklist

Before sending the upstream PR, exercise these in a real WSL terminal. Each is a path the smoke runs don't cover. Log any new findings under "Phase 2 findings" or append here.

- [ ] **Interactive `./run-claude.sh myproject` in a real WSL shell.** Exercises the TTY branch of `attach_to_container` (the F3 fix); only the non-TTY exit-0 path has been verified. Do real work in the session for at least a few minutes.
- [ ] **Detach + reattach.** Ctrl+C out, re-run `./run-claude.sh myproject`. Hits the second `attach_to_container` call site (reconnect-to-running), separate from the wait-for-setup one.
- [ ] **Token refresh past expiry.** F1's fix relies on the `~/.claude` bind mount being writable so Claude can refresh OAuth tokens. Untested end-to-end; if refresh fails, sessions break after the first expiry. Easiest probe: keep a session open through the natural expiry, or wait until tokens age out and reuse.
- [ ] **Plugin loading from `~/.claude/plugins`.** `entrypoint.sh` has `HOST_HOME` symlink logic that we didn't touch but interacts with the new UID-matched `claude` user — plugin absolute-path resolution may behave differently.
- [ ] **SSH for git.** Switch `SSH_METHOD` to `key-file` and `git push` from inside a claude session. Smokes always used `none`.
- [ ] **Keychain error on Linux/WSL.** Set `AUTH_METHOD="keychain"` in conf and run; confirm the new "try AUTH_METHOD=file" hint shows up clearly and the user can act on it.
- [ ] **Other-machine sync.** After the workflow-scope push lands, on the other Windows machine: `git fetch origin && git checkout wsl-portability && git reset --hard origin/wsl-portability`. Confirm reset-hard adopts the rewritten branch cleanly. Also verify `git config --global user.email dev@betztek.com` is set so future commits don't diverge.
- [ ] **`claude-code-test` image cleanup.** Once upstream merges and `ghcr.io/cdowin/claude-code-docker:latest` carries the F1/F2/F3 fixes, drop `claude-code-test` and revert `IMAGE_NAME` in `claude-docker.conf` to point at the GHCR image.

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
   - Alternative if working from `/mnt/c`: paths with spaces (e.g. `/mnt/c/Users/<windows-user>/My\ Projects/claude-code-docker`) are useful test fixtures but slow on `/mnt/c` — only use this if cross-mounting is needed.

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

### Sub-chunks (reshaped post-Phase 2 around actual findings)

The original 4a/b/c (timezone, keychain guard, gh fallback) turned out to be largely already-fine on the WSL/Ubuntu path — see "Verifications" in Phase 2 findings. They survive in 4d as regression coverage, not fix-work. The real fix-work is F1, F2, F3.

- **4a — F1: credentials dual-mount overlap.** [run-claude.sh:232](run-claude.sh#L232) mounts `$CLAUDE_DIR` rw at `/home/claude/.claude` and [:238](run-claude.sh#L238) mounts `$CREDS_FILE` ro at `/mnt/host-credentials.json`. When the creds file is inside the .claude dir (the *canonical* Linux/WSL location, per [claude-docker.conf.example:22](claude-docker.conf.example#L22)), both mounts hit the same host inode, and [entrypoint.sh:26](entrypoint.sh#L26)'s `cp` fails with "are the same file". Reproduced under both Windows-copied and OAuth-derived credentials. Test: with `CREDS_FILE` under `CLAUDE_DIR`, script does not emit the duplicate `-v` mount; entrypoint sees creds via the dir mount and adjusts perms in place. Fix shape: skip the explicit `-v` for `/mnt/host-credentials.json` when the path is inside `$CLAUDE_DIR`, and make entrypoint's cp conditional ("if /mnt/host-credentials.json exists AND differs from dest").
- **4b — F2: container `chown` corrupts host ownership on Linux.** [entrypoint.sh:12](entrypoint.sh#L12) runs `chown -R claude:claude /home/claude/.claude` as root inside the container against the bind-mounted host directory. On Linux/WSL, the chown propagates to the host; the container's `claude` user (UID 1001 — next free after node:22-slim's `node` at 1000) doesn't match the host user's UID (1002 in our case), so the host's `~/.claude` becomes unwriteable. macOS hides this via Docker Desktop's mount-layer ownership translation. Test: after running the container against a bind-mounted host dir, that dir's host-side ownership and mode are unchanged. Fix candidates: (a) detect non-mac host and skip the recursive chown (touch only the specific files entrypoint wrote — `.credentials.json`, `.claude.json`); (b) build the container with a UID-matching mechanism (relevant history: `2e04eba` added UID matching, `839ef7a` reverted to chown — that arc is context for choosing direction).
- **4c — F3: host script doesn't degrade in non-TTY contexts.** [run-claude.sh:260](run-claude.sh#L260) and [:287](run-claude.sh#L287) blindly `exec docker exec -it` after the container is up. In non-interactive shells (CI, agent harnesses) this exits 1 with `the input device is not a TTY`, masking a successful container boot. Test: when stdin isn't a TTY, script either skips the auto-attach (printing a "container ready, attach with: …" hint) or returns 0. Fix shape: gate the `-it` exec on `[ -t 0 ]`.
- **4d — Regression coverage + `.gitattributes` review.** Defensive tests for the originally-suspected bugs (which turned out fine):
  - **Timezone fallback** ([run-claude.sh:272](run-claude.sh#L272)): with `/etc/timezone` absent (Arch and some other distros), the `readlink /etc/localtime` fallback should still return a valid TZ string. Test by stubbing `/etc/timezone` away.
  - **Missing `gh`** ([run-claude.sh:243](run-claude.sh#L243)): with `gh` not on PATH, script completes without error and emits no GH_TOKEN env. Test by ensuring `gh` is masked.
  - **Default-keychain on non-mac** ([claude-docker.conf.example:17](claude-docker.conf.example#L17)): a Linux user copying the example without editing hits the keychain branch and gets `security: command not found`. Decide whether to (a) leave the example default and emit a clearer cross-platform error, (b) flip the example to a non-keychain default, or (c) auto-detect platform and fall back. UX choice for the upstream PR review.
  - **`.gitattributes` coverage**: confirm `*.sh`, `*.bash`, `*.bats` is the right scope. Consider pinning `Dockerfile`, `*.yml`, `*.md` to LF, and whether a `* text=auto` baseline is wanted.

**Deferred to after 4a:** the README/example's recommended Linux/WSL auth path. Once F1 is fixed, `auth_method=file` with creds at `~/.claude/.credentials.json` works correctly, and the README/example can recommend that without workaround caveats. Decide in Phase 5.

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

**During Phase 2 (smoke run on WSL Ubuntu-24.04, `auth_method=file`, `~/.claude/.credentials.json`):**

- **Build vs. pull.** First `./run-claude.sh smoke` triggered a from-scratch local build of `claude-code` (no local image present, no `IMAGE_NAME` override). Build aborted at apt-install of pandoc/scipy/etc. — heavy and slow. Workaround for the smoke: set `IMAGE_NAME="ghcr.io/cdowin/claude-code-docker:latest"` in `claude-docker.conf` and pre-pull. **Action item:** README Phase-5 should make the GHCR-image quickstart the default-recommended path for Linux/WSL hosts; the current fall-through-to-build behavior is sluggish and not what a casual user wants.
- **F1 — dual-mount overlap on `auth_method=file`.** With `CREDENTIALS_FILE=$HOME/.claude/.credentials.json` (canonical Linux path per `claude-docker.conf.example:22`), the smoke fails in entrypoint:
  ```
  cp: '/mnt/host-credentials.json' and '/home/claude/.claude/.credentials.json' are the same file
  ```
  Mechanism: `run-claude.sh:232` mounts `$CLAUDE_DIR` (rw) and `:238` mounts `$CREDS_FILE` ro at `/mnt/host-credentials.json`. Both reach the same inode when creds are under the .claude dir. macOS Keychain flow is unaffected because that path uses `mktemp` for `$CREDS_FILE`. See Phase 4 sub-chunk 4d for fix.
- **F2 — container `chown` mangles host `~/.claude` ownership.** `entrypoint.sh:12` runs `chown -R claude:claude /home/claude/.claude` as root inside the container. On Linux/WSL, the bind-mounted host dir gets its ownership flipped to the container's `claude` UID (1001 — next free after `node:22-slim`'s `node` at 1000), which doesn't match the WSL user's UID (1002). After the smoke run, host-side `~/.claude` becomes unwriteable by the WSL user — broke a subsequent `claude/install.sh` attempt that wanted to mkdir `~/.claude/downloads`. macOS Docker Desktop hides this via mount-layer ownership translation. Recovery during Phase 2: `mv ~/.claude ~/.claude.broken-by-f2 && mkdir ~/.claude` (no sudo needed). See Phase 4 sub-chunk 4d for fix; relevant history is `2e04eba` (UID matching, added) → `839ef7a` (reverted to chown). **Independent verification:** F1 reproduced identically against an OAuth-derived `~/.claude/.credentials.json` written by a fresh native `claude /login` flow inside WSL — confirms the bug is intrinsic to the mount logic, not an artifact of how creds were copied from Windows.
- **F3 — host script doesn't degrade gracefully in non-TTY contexts.** [run-claude.sh:260](run-claude.sh#L260) and [:287](run-claude.sh#L287) blindly `exec docker exec -it "$CONTAINER_NAME" gosu claude claude ...` after the container is up. In a non-interactive shell (CI, scripts, agent harnesses) this exits 1 with `the input device is not a TTY`, masking the fact that the container actually booted fine. Test: when stdin is not a TTY, the script either skips the auto-attach (printing "container ready, attach with: docker exec ...") or returns 0. Fix: gate the `-it` exec on `[ -t 0 ]` or `[ -t 1 ]`.
- **Smoke success with F1 worked around.** With `CREDENTIALS_FILE=$HOME/.claude-creds-for-docker.json` (outside `~/.claude`) and `IMAGE_NAME=ghcr.io/cdowin/claude-code-docker:latest`, the container boots cleanly: firewall configured, suid bits stripped, `Container ready. Waiting for connections...`. `docker exec claude-smoke gosu claude claude --version` → `2.1.118 (Claude Code)`. Confirms the rest of the pipeline (image pull, container init, mounts other than the cred overlap) works on WSL.

**Phase 3 findings (Windows submodule line endings):**

- `git submodule add` on Windows under default `core.autocrlf=true` checked out all three bats submodules' shell scripts as CRLF, breaking `bats` execution. bats-core ships its own `.gitattributes` pinning `*.sh` to LF, but the submodule's own attributes don't apply during the parent's clone-time autocrlf conversion. Workaround used in Phase 3: `git config core.autocrlf input` inside each submodule + `git rm --cached -r . && git reset --hard`.
- This won't bite Linux/macOS clones or CI (which runs Linux). It will bite anyone cloning on Windows. Phase 5 README should call this out in the WSL section, recommending one of: (a) set `git config --global core.autocrlf input` before cloning, (b) run a one-shot fix script after `git submodule update --init`, or (c) clone inside WSL home (which uses the WSL distro's git, with sensible defaults).
- Parent `.gitattributes` does not affect submodule working trees because parent only tracks the submodule pointer (SHA), not the submodule's files — so we can't fix this from the parent repo alone.

**Phase 4 lessons (added during 4a/4b — apply to remaining sub-chunks and Phase 5):**

- **F1 and F2 are coupled.** F1's fix (skip the explicit cred mount when creds are inside CLAUDE_DIR) only works once F2 is fixed too: without UID matching, the in-container `claude` user (UID 1001 historically) can't read host-owned mode-600 `.credentials.json` exposed via the dir mount. The two fixes work together. If we ever revisit, don't try to land one without the other on Linux.
- **GHCR image lag.** Until the upstream PR merges and CI rebuilds, `ghcr.io/cdowin/claude-code-docker:latest` does not carry our entrypoint changes. Anyone running our `run-claude.sh` against that image gets only the host-side fix; the F2 entrypoint logic needs a new image. Phase 5 README should mention this and document the test-image-overlay recipe (FROM ghcr base + COPY entrypoint + COPY init-firewall, ~5 sec build) or use `--build` for full local rebuild (~5 min).
- **`usermod -u` auto-chowns the user's home directory** (per Debian/Ubuntu shadow-utils). On a bind-mounted home that's exactly the propagation we're trying to avoid. The fix uses direct `sed` edits to `/etc/passwd` and `/etc/group` instead — portable across base distros and avoids the home walk entirely. Don't replace those sed lines with `usermod` cleanups in a future refactor.
- **State-corrupting bugs need a clean baseline before "after" verification.** The first F2 smoke run was against an already-corrupted `~/.claude` (left mangled by prior bug-affected runs); the "after" reading still showed corruption — but it was *prior* corruption persisting, plus a *new* entrypoint bug (usermod home-walk). Easy to mistake for "fix didn't work." Reset state (`chgrp -R betzj2 ~/.claude` if owner is still you, or recreate dir from a backup) before each verification cycle.

**Verifications of the originally-suspected sub-chunks (4a/4b/4c):**

- **4a — Timezone detection.** [run-claude.sh:272](run-claude.sh#L272)'s `cat /etc/timezone 2>/dev/null || readlink /etc/localtime ...` correctly extracted `America/New_York` from WSL Ubuntu-24.04 and propagated it as the container's `TZ` env. **No fix needed for the WSL case;** Phase 4 should still add a regression test for the `/etc/timezone` absent path (Arch and some other distros don't have it).
- **4b — Keychain guard.** [run-claude.sh:106](run-claude.sh#L106)'s `command -v security` check sits inside the `case "$AUTH_METHOD" in keychain)` branch, so it's only evaluated when the user actively chose keychain auth. We used `auth_method=file`, so this branch was never entered; not a portability bug. **UX nit, not a bug:** [claude-docker.conf.example:17](claude-docker.conf.example#L17) defaults to `AUTH_METHOD="keychain"` uncommented — a Linux/WSL user who copies the example without editing will hit the (correct, well-formatted) error message. Worth considering a non-keychain default in the example for the upstream PR, or a "detect-platform" line in the comment.
- **4c — `gh auth token` fallback.** [run-claude.sh:243](run-claude.sh#L243)'s `if command -v gh &>/dev/null` guard works as designed — with `gh` absent on the WSL host, the entire token-extraction block is silently skipped. **No fix needed;** Phase 4 should add a regression test that asserts the script still completes successfully when `gh` is missing.

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
