# Plan — roll template v3 out to the 10 projects

**Objective:** every project's `develop` runs template v3 (918b981), stamped in `.claude/template-version`, with no project customisation lost and no project gate broken.

**Evidence (survey 2026-11-25, this machine, read-only):** 10 primary repos under `/mnt/disque-d/Develope`. None has `.claude/template-version`. That has two effects on the first sync:
- Each file is compared to every historical template version. A hand-merged file shows as "locally modified" and is kept, not replaced.
- The settings merge base is `{}` (`sync-template.sh:115`). Every template hook and permission comes back, including ones a project dropped on purpose. Lemqes, for example, wires only 3 hooks.

Other facts that shape the plan:
- Three repos have uncommitted work in their main checkout: InstaReels (10 files), Video Generator (7), UnityGames/game1 (1).
- InstaReels has no `develop`. Video Generator has no remote.
- DoWee and GRdLines use FVM, and GRdLines is a pub workspace. AllaghenBrand and StoreCore set `DONE_GATE_MODE=manual`.
- A dry run on portfolio (by the plan reviewer) shows these as locally modified: `AGENTS.md`, `.gitattributes`, `scripts/test-hooks.sh`, `done-gate.sh`, `skill-nudge.sh`, `workflow.md`. It also shows `.claude/skills/llm-council` and `.agents/skills/llm-council` as removed upstream.
- python3 is present, so `settings.json` is three-way merged.

| Project | Path (`/mnt/disque-d/Develope/…`) | `develop` is checked out in (merge there) | Notes |
|---|---|---|---|
| portfolio | `portfolio` | main checkout, clean | pilot; no stack gate |
| Lemqes | `Lemqes` | main checkout, clean | lint via `scripts/sdk flutter` |
| AllaghenBrand | `AllaghenBrand` | main checkout, clean | hand-merged done-gate; `DONE_GATE_MODE=manual` |
| StoreCoreTemplate | `StoreCoreTemplate` | main checkout, clean | customised hooks, WordPress; `manual` |
| SghiraBrand | `SghiraBrand` | not checked out → rollout worktree | WordPress, `DONE_GATE_ENV_PROBE` via wp-env |
| DoWee | `DoWee` | not checked out → rollout worktree | customised hooks, FVM |
| GRdLines | `GRdLines` | `GRdLines-close-plan2`, clean | FVM, pub workspace |
| UnityGames/game1 | `UnityGames/game1` | `game1/.claude/worktrees/chore-rules`, clean | no stack gate; `graphify-out/cache/last_query_stamp` changes constantly |
| Video Generator | `Video Generator` | not checked out → rollout worktree | no remote, path has a space |
| InstaReels | `InstaReels` | no `develop` (see T10) | no stack gate |

**In scope:** for each of the 10 projects:
- a dry run, then `--apply`;
- the project's customisations moved to project-owned homes, so that template-owned files can take the v3 version;
- the `settings.json` merge, reviewed hook by hook;
- a decision on each removed-upstream file;
- the gates, then one commit on `chore/template-v3` and a merge to `develop`.

**Out of scope:**
- The 6 extra checkouts. They pick up v3 by merging `develop`, and two of them are only used as the merge checkout (see the table).
- The other machine: it only runs `git pull` after T12.
- The feature branches that are checked out now.
- Any app code.
- `scripts/test-hooks.sh` as a project gate. It audits the whole repo against the template's ownership table, so it can never pass in a project; it gates the template only.
- Re-measuring cost: that is its own task, on or after 2026-12-09, with `scripts/usage-report.py`.

**Approach:** each project gets a **separate worktree** at `/mnt/disque-d/Develope/_v3-rollout/<project>`, on a new `chore/template-v3` branch cut from `develop`. This leaves the checked-out feature branches and their uncommitted work untouched, needs no stash, and keeps worktree folders out of the 4 repos that do not ignore `.claude/worktrees`.

Inside that worktree, run the template's own copy: `bash "$TPL/scripts/sync-template.sh" "$TPL"`, with `TPL=/mnt/disque-d/Develope/Claude_Codex_template`. `--ref` defaults to `main`, which is 918b981.

A "locally modified" file is never force-overwritten:
1. Its project-specific part goes to its destination (see the table in step 3).
2. The file is then written from the target commit: `git -C "$TPL" show 918b981:<path> > <path>`. After that it shows as "unchanged".

The pilot comes first, then the projects with customised hooks, then the odd ones. Each merge follows `delivery.md`. All pushes wait for a single owner decision in T12.

## Per-project procedure (T1–T10 each run it)

1. `git -C <P> worktree add /mnt/disque-d/Develope/_v3-rollout/<name> -b chore/template-v3 develop`. Record the main checkout's `git rev-parse --abbrev-ref HEAD` and `HEAD`.
2. Dry run. Add a row to the Verification log with the counts per status, plus every "locally modified" and "removed upstream" path.
3. Resolve each "locally modified" path. Its project-specific part goes here:

   | Locally modified | Destination for the project's part |
   |---|---|
   | `.claude/rules/*.md` | `.claude/rules/local-<topic>.md` |
   | done-gate edits | `.claude/hooks/local/<name>.sh`, or env in `settings.json` (`DONE_GATE_*`) |
   | other `.claude/hooks/*.sh` | `.claude/hooks/local/` if it is a gate; otherwise a template follow-up (T11) |
   | `AGENTS.md` | project `CLAUDE.md` (AGENTS.md is only a pointer) |
   | `.gitattributes` | owner decision: take the template version, or keep with a reason |
   | `scripts/*` | a new project script under a non-template name |

   - If a change is really a template bug, log it for T11 and do not keep it in the project.
   - Then write the file from 918b981 (see Approach) and run the dry run again.
   - For each "removed upstream" path: delete it, or keep it with a reason. The default is to delete when the template ships a replacement (llm-council lives in `skills-optional/`).
4. Install the project's dependencies in the worktree (`npm ci` / `composer install` / `fvm flutter pub get`, whichever applies). Then `--apply`. Review the merged `.claude/settings.json` hook by hook against `develop`'s copy, and remove any re-added hook or permission the project had dropped on purpose; check `git log -p` on develop's `settings.json` for the intent.
5. Commit on `chore/template-v3`: `chore: sync template v3 (918b981)`. Then run `bash scripts/gate-scope.sh` and run the gates at the tier it prints (see Done-when 2).
6. Review: `code-reviewer` agent (**model: sonnet**), scoped to what is specific to this project:
   - the `settings.json` diff;
   - the new `local-*` files and the moved customisations;
   - the removed-upstream deletions.

   The template files themselves were reviewed in v3 T15. Fix or rebut each finding; each fix is its own commit.
7. Merge into `develop` in the checkout named in the table, then remove the rollout worktree.

## Tasks

Each project task (T1–T10) is done when all of these hold, with `<P>` = that project:
1. **Proof:** in the rollout worktree, rerunning the dry run prints `no changes to apply.`, with no "locally modified" or "removed upstream" line. The only exceptions are files kept with a reason in that project's Verification log row. `.claude/template-version` contains `commit 918b981`.
2. **Nothing broken:** the gates are run directly, by these commands, not through the hook:
   - Load the merged `settings.json` env, then run `bash -x .claude/hooks/done-gate.sh` and grep its trace for `run_gate`. Every stack gate the project has (lint, typecheck, `dart analyze` per workspace member, FVM path) appears and exits 0.
   - The tier that `gate-scope.sh` prints is green.
   - A project with no stack gate (portfolio, game1, InstaReels) records "no stack gate" instead.
   - WordPress env-probe gates that cannot run from the worktree (wp-env is tied to the project path) are recorded as "NOT RUN — env", then re-run from the merge checkout after step 7.
3. **Scope fence:** `git diff --name-only develop...chore/template-v3` lists only these:
   - template-owned paths (per `docs/template-files.md`);
   - `.claude/settings.json` (merged);
   - `.claude/template-version`;
   - new `.claude/rules/local-*.md` and `.claude/hooks/local/*`;
   - deleted removed-upstream paths;
   - the destinations named in step 3 (`CLAUDE.md`, new non-template scripts).

   In the main checkout, the branch and `HEAD` are unchanged (except at the merge, where `develop` is checked out), and `git diff --stat` is empty for every path in that list.
4. **Merged:** `develop` contains the merge, the rollout worktree is removed, and the review findings are fixed or rebutted in the Verification log.

- [x] **T0 — Survey dry run (read-only).** Results are in the Verification log. Total estimate: about 7 h of hand-merging. Run steps 1–2 for all 10 projects. InstaReels gets a worktree cut from `main`. Then delete the branches and worktrees again.
  Done when: the Verification log has one row per project with its status counts and every "locally modified" and "removed upstream" path, and an effort estimate for each project. `git -C <P> branch --list chore/template-v3` is empty for all 10, and each main checkout's branch and `HEAD` are unchanged. No files changed outside `task_plan.md`.
- [x] **T1 — portfolio** (pilot). The settings diff gets extra care: this is the first real use of the round-1 settings-merge fix (6fcbc6c). If the method has to change, amend this plan before T2.
- [x] **T2 — Lemqes.** Settings: keep only the hooks it wants. Its develop wires done-gate, sync-codex-on-edit and validate-code. Ask the owner about repo-guard, session-guard and skill-nudge.
- [x] **T3 — AllaghenBrand.** Its hand-merged done-gate parts move to `hooks/local` or env (`DONE_GATE_ENV_PROBE`/`_PORT`). Keep `DONE_GATE_MODE=manual`.
- [x] **T4 — StoreCoreTemplate.** Customised hooks. The WordPress gates run from the main checkout after the merge (Done-when 2).
- [x] **T5 — SghiraBrand.** The wp-env probe needs `node_modules`: run it after the merge, from the main checkout.
- [x] **T6 — DoWee.** Customised hooks. Proof 2 must show the done-gate running through FVM (`scripts/flutter.sh` or `fvm`).
- [ ] **T7 — GRdLines.** Proof 2 must show `dart analyze` running per workspace member. Merge in `GRdLines-close-plan2`.
- [ ] **T8 — UnityGames/game1.** Merge in `.claude/worktrees/chore-rules`.
- [ ] **T9 — Video Generator.** Quote the path everywhere. There is no remote, so it is excluded from T12.
- [ ] **T10 — InstaReels.** Owner decision first: create `develop` from `main` (per `delivery.md`), or sync onto a branch cut from `main` and merge into `main` only with the owner's yes. Second owner decision: whether to take the 1157 vendored skill files. They are template-owned, so `--apply` adds them. If not, give the project a list of excluded paths to skip; that may need a sync-template option, logged for T11.
- [ ] **T11 — Template follow-ups.** From T1:
  - (a) `skill-nudge.sh`: add `*/template/*.html` to the UI glob, with a test case.
  - (b) test case: a project with no stack and no `DONE_GATE_CMD` passes through the done-gate silently.
  - (c) `docs/template-files.md`: make `.gitattributes` project-owned (owner yes, 2026-11-25).
  - (d) `scripts/test-hooks.sh` ships to projects, but its ownership audit fails there. Skip that audit when the repo isn't the template.

  From T3:
  - (e) done-gate `ENV_DOWN`: add wp-env's `has not yet been initiali[sz]ed`, with a test case. AllaghenBrand's old hook had it; it is harmless there while the gate stays manual.

  From T4:
  - (f) port StoreCore's dropped done-gate cases upstream: the ANSI-wrapped `FOUND n ERRORS` phpcs marker blocks despite env-down text, and `Error: connect ENOENT /var/run/docker.sock` → NOT RUN. The second fails on v3 (`ENOENT.*docker` was dropped), so the fix adds it to `ENV_DOWN`.

  From T6:
  - (g) done-gate: a missing pinned Flutter (`scripts/flutter.sh` exits 127, "not found") should be NOT RUN to the user, not a code failure (DoWee's old hook did it via `flutter.sh --which`); also add the indented `  error • … • file:line` / `warning` / `info` analyze lines and `Some tests failed` to `CODE_ERR`. Port DoWee's 7 dropped Flutter cases into `scripts/test-hooks.sh`.
  - (h) `sync-template.sh` settings merge: a project's own fields on a template hook (DoWee's Stop `timeout: 600`) are reset to the template's (300) on every sync. Keep the project's per-hook fields; add a test case.
  - (i) `validate-code.sh`: Dart bare `print(` note and `*.mjs` in the JS debug-leftover glob (DoWee had both).

  Every template bug logged in T1–T10 gets a fix on a template branch (TDD in `scripts/test-hooks.sh`), or is deferred by the owner.
  Done when: each follow-up line in the Verification log is either linked to a commit or marked deferred by the owner. The template's `bash scripts/test-hooks.sh` reports `failed: 0`. No files changed outside the template repo.
- [ ] **T12 — Push (owner decision).** Ask once, listing the 9 pushable projects and their `develop` heads. On a yes, push each one and remove `/mnt/disque-d/Develope/_v3-rollout`.
  Done when: for every pushed project, `git -C <P> log origin/develop -1` equals the local `develop`; the folder is gone; no other files changed.

## Verification log
| Project | Dry run (new / updated / locally modified / removed) | Settings hooks kept/dropped | Gates | Review | Merged |
|---|---|---|---|---|---|
| portfolio | T0: 17 / 16 / 6 / 2 · est. 20 min. T1: d02845c (34 applied). Kept with the owner's yes: skill-nudge.sh (v3 plus `*/template/*.html`) and .gitattributes (v3 plus text=auto and a binary list). workflow.md's 2 lines moved to `local-gates.md`. llm-council copies deleted. Re-run of the dry run: `no changes` apart from those 2 | +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; nothing dropped | done-gate: rc 0, silent, 0 `run_gate` (no stack gate). Tier full = `pytest -m "not launch"` (scratch venv): 535 passed, 0 failed; 8 `launch` tests NOT RUN (they need real user input) | sonnet: approve. Coverage-loss warning rebutted: test-hooks.sh can't run in projects, so both cases go upstream in T11. Wording nit skipped | b67cbf5 (--no-ff; branch was develop before and after); worktree removed |
| Lemqes | T0: 24 / 19 / 0 / 2 · est. 15 min. T2: d755e91 (44 applied). No locally modified files. llm-council copies deleted. Re-run of the dry run: `no changes to apply.` | Kept its 3 (validate-code, sync-codex-on-edit, done-gate; now via `$CLAUDE_PROJECT_DIR`). +repo-guard, +session-guard, +skill-nudge (owner yes, 2026-11-25), +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; nothing dropped | done-gate: rc 0, `run_gate` lint + typecheck, both 0. Tier full = `npm test`: flutter test `+1248: All tests passed!`; `supabase test db` Files=18, Tests=993, PASS | sonnet: approve, no findings. Nit (done-gate unverified on Flutter) answered by the done-gate trace | fd5ee52 (--no-ff; branch was develop before and after); worktree removed |
| AllaghenBrand | T0: 19 / 15 / 6 / 2 · est. 45 min. T3: cf423c7 (35 applied); dry run 19 / 15 / 6 / 2 as T0. done-gate drift: escaping and 2 ENV_DOWN texts are in v3; `has not yet been initialized` → T11 (e); manual-mode and 8896-probe notes → `local-gates.md` (probe stays in settings env). delivery.md B1–B7 interim gate dropped (project plan marks B1–B7 done; full suite on every merge, noted in `local-gates.md`). workflow.md and pr.md project lines → `local-gates.md` + `local-workflow.md`. test-hooks.sh Allaghen cases dropped (template-owned; T11 (d)). Kept with the owner's yes: .gitattributes (`* text=auto eol=lf` + 7 binary types + v3). llm-council copies deleted. Re-run of the dry run: `no changes` apart from .gitattributes | Kept all project hooks and env (`DONE_GATE_MODE=manual`, `DONE_GATE_ENV_PROBE`). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Dropped the re-added pre-v3 allows (Read/Grep/Glob(**), `npm run build`, git add, git commit): 25acacf kept the project's own allow-list on purpose | Tier full. From the worktree: eslint rc 0; manual done-gate rc 0, 0 `run_gate` (as configured). After the merge, main checkout, wp-env started (owner yes, 2026-11-25): `npm run lint` rc 0 (phpcs 22/22, eslint clean); `npm test` `OK (19 tests, 169 assertions)`; `core:check` OK (70374ba); done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0 | sonnet: approve. Medium (a stopped wp-env would block the automatic gate) fixed in 4cd7056. Nit (probe untested once the test-hooks cases are gone) rebutted: the sync keeps the project's env. Nit on B1–B7 history in CLAUDE.md skipped (history only) | fd718aa (--no-ff; branch was develop before and after); worktree and `_v3-rollout` removed; wp-env left running |
| StoreCoreTemplate | T0: 16 / 8 / 4 / 0 · est. 30 min. T4: 3f95830 (25 applied); dry run 16 / 8 / 4 / 0 as T0. done-gate drift: the escaping and the WSL/ENOENT docker texts are in v3; the port-8892 probe → `DONE_GATE_ENV_PORT=8892` in settings env; the broader `ENOENT.*docker`/`docker\.sock` patterns were dropped (v3's `spawn docker ENOENT` and `Cannot connect to the Docker daemon` cover the real messages) → T11 (f). Manual-mode, port and scoped-merge-gate notes → `local-gates.md` (cb28823; StoreCore HAS `.claude/gate-core-paths`, so gate-scope prints `targeted`, not `full`). AGENTS.md's StoreCore line was already in CLAUDE.md. test-hooks.sh StoreCore cases dropped (template-owned; T11 (d), (f)). Kept: .gitattributes, a superset of v3 (`*.cmd` covers v3's `scripts/*.cmd`; adds text=auto, binary types, import fixtures), same as T1/T3. No llm-council copies (only the template's `skills-optional/`). Re-run of the dry run: `no changes` apart from .gitattributes | Kept all project hooks, allows and env (`DONE_GATE_MODE=manual`). +`DONE_GATE_ENV_PORT=8892`, +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing re-added: StoreCore's own allow-list already had Read/Grep/Glob(**), build, git add/commit | Tier targeted (no core path touched; no app code changed). From the worktree (haiku): eslint rc 0, no output; settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; manual done-gate rc 0, 0 `run_gate` (as configured); tree clean. After the merge, main checkout, wp-env started (owner yes, 2026-11-25): `npm run lint` rc 0 (phpcs 267/267, eslint clean); `npm test` `OK (1126 tests, 33230 assertions)`; done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0. No `wp-content/` change, so no AllaghenBrand `core:check` needed | sonnet: request changes (2 medium, 2 nits), no fix commits. Medium 1 (test-hooks.sh 155/157 in the project: README and ownership audit) rebutted: T11 (d), not a project gate. Medium 2 (StoreCore done-gate cases gone) rebutted: v3 covers the 8892-vs-other-port probe and `user_note` escaping; the ANSI phpcs marker still blocks (`FOUND [0-9]+ ERRORS?` is unanchored); its regression cases → T11 (f). Nit ("has not yet been initialized" unverified) kept: T3 saw that text from wp-env, and the old StoreCore test saw `✖ Environment not initialized`, so both forms exist. Nit (adb allows in a WordPress repo) skipped: harmless, same as every project | 5d4d088 (--no-ff; branch was develop before and after); worktree and `_v3-rollout` removed; wp-env left running |
| SghiraBrand | T0: 16 / 8 / 4 / 0 · est. 30 min. T5: 2a0be9f (25 applied); dry run 16 / 8 / 4 / 0 as T0. done-gate drift: the escaping and the `spawn docker ENOENT`/WSL texts are in v3; the probe stays in settings env (`DONE_GATE_ENV_PROBE`, wp-env `cli`); no template gap. delivery.md "design approval before the gate" (owner 2026-11-12) → `local-delivery.md`, word for word. Gate notes (probe, `node_modules`, path-bound wp-env, gate-core-paths) → `local-gates.md` (fixed in 2498791). test-hooks.sh SghiraBrand cases dropped (template-owned; v3 lines 70–99 cover service-not-running, probe up/down, `spawn docker ENOENT`, escaping; T11 (d)). Kept: .gitattributes, a superset of v3 (`*.cmd` covers `scripts/*.cmd`; adds text=auto, binary types, import fixtures), same as T1/T3/T4. No llm-council copies. Re-run of the dry run: `no changes to apply.` apart from .gitattributes; stamp `commit 918b981…` | Kept all project hooks, allows and env (`DONE_GATE_ENV_PROBE`; automatic gate, no `DONE_GATE_MODE`). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing re-added: history (374b0e5, 936a10b) never dropped anything | Tier targeted (`.claude/gate-core-paths` exists; no core path or app code touched). From the worktree after `npm ci` (haiku): eslint rc 0, no output; settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; done-gate (auto, project env): rc 0, `run_gate lint` → NOT RUN (wp-env not initialised for the worktree); tree clean. After the merge (owner yes, 2026-11-25): no checkout had `develop` (the main checkout is on `chore/b6-production-cutover`), so a temporary `develop` worktree at `Develope/SghiraBrand-v3-gates` (a sibling of `StoreCoreTemplate`, which `.wp-env.json` mounts) ran `npm ci` + `npm run env:start` (rc 0, seed done). From it (haiku): `npm run lint` rc 0 (phpcs 239/239, eslint clean); `npm test` `OK (41 tests, 502 assertions)`; done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0, no NOT RUN. Then `wp-env destroy --force` and the worktree was removed; AllaghenBrand's (8896) and StoreCore's (8892) wp-env left running | sonnet: approve. Medium (local-gates claimed a missing `node_modules` gives NOT RUN; it actually blocks as a lint failure, since `wp-env: not found` is not in `ENV_DOWN`) fixed in 2498791, with the nit on the probe's 60 s timeout and failure-path-only use. Nit (dropped project assertion that settings wires the wp-env probe) skipped: test-hooks.sh is template-owned and not a project gate (T11 (d)) | 7ef9859 (--no-ff, made in the rollout worktree; main checkout stayed on `chore/b6-production-cutover` cbaa0fa); worktree and `_v3-rollout` removed |
| DoWee | T0: 17 / 14 / 8 / 2 · est. 90 min. T6: 03814690 (32 applied); dry run 17 / 14 / 8 / 2 as T0. done-gate drift: FVM via `scripts/flutter.sh`, `user_note` escaping and the unchanged-tree skip are in v3; the missing-SDK NOT RUN and the extra Flutter `CODE_ERR` markers → T11 (g) (interim: `DONE_GATE_MODE=manual` in that machine's `settings.local.json`, noted in `local-gates.md`). validate-code drift (Dart `print(` note, `.mjs`, Supabase wording) is not a gate → T11 (i). Rules → `local-code-style.md`, `local-git.md`, `local-reporting.md`, `local-workflow.md`, `local-gates.md`; delivery.md had nothing project-specific (old pre-gate-scope step 1); the full-gate-before-merge rule stays in CLAUDE.md. test-hooks.sh DoWee cases dropped (template-owned; T11 (d), (g)). llm-council copies deleted. No .gitattributes drift. Re-run of the dry run: no locally modified or removed line; only `merge .claude/settings.json` (Stop timeout 600 → 300), kept with a reason (T11 (h)); stamp `commit 918b981…` | Kept all project hooks, allows and denies (no env block). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; template allow order taken (cosmetic). Stop timeout kept at 600 (a188a61f set it for `DONE_GATE_FULL` tests; the merge resets it, T11 (h)). Nothing dropped: history (86d6aa7b, c799899a, a188a61f) never removed a template hook | Tier full (`^scripts/` is a core path). From the worktree after `scripts/flutter.sh pub get` (haiku): settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; done-gate (auto): rc 0, one `run_gate analyze bash …/scripts/flutter.sh analyze --no-pub`, silent. `bash scripts/gate.sh` (the owner's full gate, CLAUDE.md): 12 PASS (analyze + test for root, admin_console, dowee_design; both web builds; website check and layout; backend edge tests and SQL suites) and 1 FAIL, Lighthouse `/contact` performance 0. Re-run of `npm run lighthouse` alone: rc 0, `/contact` 100, so a flaky run (no `website/` change on the branch); tree clean | sonnet: approve, no critical/high/medium. Nit 3 (manual mode turns the whole Stop gate off) fixed in 25015046. Nit 1 (the restore-600 step relies on memory) → T11 (h). Nit 2 (list `local-*.md` in CLAUDE.md) skipped: they auto-load and AGENTS.md points to them | 673883ea (--no-ff, made in the rollout worktree; the main checkout stayed on `feat/android-app-links` 5a2216c9, clean). CLAUDE.md asks for the owner's yes before a merge to develop: taken as given by the T6 request. Worktree and `_v3-rollout` removed |
| GRdLines | T0: 26 / 16 / 4 / 2 · est. 60 min | T0: +delegate-guard, +repo/session-guard, +skill-nudge (decide) | | | |
| UnityGames/game1 | T0: 26 / 17 / 2 / 2 · est. 45 min | T0: +delegate-guard, +repo/session-guard, +skill-nudge (decide) | | | |
| Video Generator | T0: 24 / 16 / 3 / 2 · est. 25 min | T0: +delegate-guard, +repo/session-guard, +skill-nudge (decide) | | | |
| InstaReels | T0 (from `main`): 1157 / 1 / 9 / 2 · est. 60 min + vendored-skills decision | T0: all 6 above + done-gate (decide) | | | |

**T0 detail (2026-11-25, template 918b981).** Drift is measured as lines that differ from the closest template version the file was built on (commit in brackets), not from v3. It is the size of the project's own edit.
- **Removed upstream** (every project except SghiraBrand and StoreCore): `.claude/skills/llm-council/SKILL.md` and `.agents/skills/llm-council/SKILL.md`. The default is to delete them, because llm-council now ships in `skills-optional/`.
- **Locally modified, drift in lines:**
  - **portfolio:** done-gate 7, skill-nudge 2, workflow.md 6, .gitattributes 13, AGENTS.md 2, test-hooks.sh 12.
  - **AllaghenBrand:** done-gate 21, delivery.md 12, pr.md 4, workflow.md 77, .gitattributes 9, test-hooks.sh 49.
  - **StoreCoreTemplate:** done-gate 18, .gitattributes 13, AGENTS.md 4, test-hooks.sh 25.
  - **SghiraBrand:** done-gate 8, delivery.md 10, .gitattributes 15, test-hooks.sh 38.
  - **DoWee:** done-gate 75, validate-code 14, code-style.md 25, delivery.md 13, pr.md 18, reporting.md 58, workflow.md 162, test-hooks.sh 35.
  - **GRdLines:** done-gate 120, sync-codex-on-edit 3, code-style.md 21, reporting.md 5.
  - **UnityGames/game1:** done-gate 108, workflow.md 5.
  - **Video Generator:** done-gate 9, workflow.md 3, CATALOG.md 34.
  - **InstaReels:** deepen (skill + command) 2+2, retro (skill + command) 10+10, pr.md 6, reporting.md 5, workflow.md 151, .codex/config.toml 8, AGENTS.md 29.
- **InstaReels "new" = 1157:** almost all of these are vendored skill packs it never had: `skills-optional/xias` 382, `ui-ux-pro-max` 263, `taste` 39, `skills/superpowers` 238, `impeccable` 58+58.
- **Hooks:** delegate-guard is new in v3, so it is expected everywhere. The other re-added hooks predate v3. Check `git log -p .claude/settings.json` for each project to see whether they were dropped on purpose.
- **Clean-up check:** every dry run exited 0 and wrote nothing. Afterwards all 10 main checkouts had the same branch and HEAD (compared before and after). No `chore/template-v3` branch and no `_v3-rollout` worktree are left.

## Risks & open questions
- **Plan reviewed 2026-11-25** (code-reviewer, opus): 4 critical, 4 high and 2 medium findings, all addressed above. The fixes:
  - test-hooks dropped as a project gate;
  - gates run directly, with dependencies installed;
  - "write from 918b981" replaces "restore";
  - commit comes before gate-scope;
  - settings are reviewed for re-added hooks;
  - merge checkouts are named;
  - the fence checks branch and HEAD instead of status;
  - removed-upstream files are handled;
  - the false symlink expectation is dropped;
  - WordPress probes get "NOT RUN — env" plus a re-run.
- **First sync without a stamp:** untangling locally modified files is manual work, roughly 15–45 min for each customised project, more for DoWee and StoreCore. T0 measures it.
- **The v3 round-1 fixes were never re-reviewed.** T1 is their first real use.
- **bash 3.2** (40bb166) has not been run on real bash 3.2. That only matters on macOS. Open question for the owner: does any machine run macOS? If none does, close this as N/A.
- **T10 live emulator smoke** was skipped by the owner on 2026-11-25. DoWee or GRdLines may be its first real run.
- **The other machine** must `git pull` each project after T12.

/goal every task in task_plan.md is checked off per its own "Done when", and the template's scripts/test-hooks.sh reports failed: 0
