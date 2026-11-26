# Plan archive

Finished plans moved out of `task_plan.md` (workflow.md, Plan first). Newest first.

---

## 2026-11-26 — template v3 rollout (T0–T12)

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
| UnityGames/game1 | `UnityGames/game1` | `game1/.claude/worktrees/chore-rules`, clean | area gates in the done-gate (T8 found them; T0 said none); `graphify-out/cache/last_query_stamp` changes constantly |
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
- [x] **T7 — GRdLines.** Proof 2 must show `dart analyze` running per workspace member. Merge in `GRdLines-close-plan2`.
- [x] **T8 — UnityGames/game1.** Merge in `.claude/worktrees/chore-rules`.
- [x] **T9 — Video Generator.** Quote the path everywhere. There is no remote, so it is excluded from T12.
- [x] **T10 — InstaReels.** Owner decision first: create `develop` from `main` (per `delivery.md`), or sync onto a branch cut from `main` and merge into `main` only with the owner's yes. Second owner decision: whether to take the 1157 vendored skill files. They are template-owned, so `--apply` adds them. If not, give the project a list of excluded paths to skip; that may need a sync-template option, logged for T11.
  **Decided 2026-11-26:** (1) `develop` created from `main`, merge there. (2) Content-only: the 1135 new paths InstaReels had at d6a1206 and removed afterwards (owner's 2026-11-17 strip, 56096bb) are removed again after `--apply`, plus the coding-only additions since (`.claude/hooks/skill-nudge.sh`, `scripts/android-emu.sh`, `scripts/android-ui.sh`, `scripts/fixtures/ui-*.xml`, `scripts/test-hooks.sh`). The template files the project adapted for content work stay locally modified (`workflow.md`, deepen, retro, `.codex/config.toml`, `AGENTS.md`). (3) Keep repo-guard, session-guard and delegate-guard; no done-gate, no skill-nudge.
  **Done-when amendment (owner decision 2):** in clause 1, the excluded paths above count as "kept with a reason" (they show as `new`), and so do the 5 adapted files (they show as `locally modified`). Clause 2: done-gate is excluded, so record "no stack gate, done-gate excluded by owner" instead of the trace. Skipping these paths on every sync becomes T11 (o).
- [x] **T11 — Template follow-ups.** From T1:
  - (a) `skill-nudge.sh`: add `*/template/*.html` to the UI glob, with a test case. → b56ba20
  - (b) test case: a project with no stack and no `DONE_GATE_CMD` passes through the done-gate silently. → b1307c2
  - (c) `docs/template-files.md`: make `.gitattributes` project-owned (owner yes, 2026-11-25). → 42a7120
  - (d) `scripts/test-hooks.sh` ships to projects, but its ownership audit fails there. Skip that audit when the repo isn't the template. → af60657

  From T3:
  - (e) done-gate `ENV_DOWN`: add wp-env's `has not yet been initiali[sz]ed`, with a test case. AllaghenBrand's old hook had it; it is harmless there while the gate stays manual. → 4131537

  From T4:
  - (f) port StoreCore's dropped done-gate cases upstream: the ANSI-wrapped `FOUND n ERRORS` phpcs marker blocks despite env-down text, and `Error: connect ENOENT /var/run/docker.sock` → NOT RUN. The second fails on v3 (`ENOENT.*docker` was dropped), so the fix adds it to `ENV_DOWN`. → 39415e3

  From T6:
  - (g) done-gate: a missing pinned Flutter (`scripts/flutter.sh` exits 127, "not found") should be NOT RUN to the user, not a code failure (DoWee's old hook did it via `flutter.sh --which`); also add the indented `  error • … • file:line` / `warning` / `info` analyze lines and `Some tests failed` to `CODE_ERR`. Port DoWee's 7 dropped Flutter cases into `scripts/test-hooks.sh`. → fedab5e
  - (h) `sync-template.sh` settings merge: a project's own fields on a template hook (DoWee's Stop `timeout: 600`) are reset to the template's (300) on every sync. Keep the project's per-hook fields; add a test case. → 9b5a682
  - (i) `validate-code.sh`: Dart bare `print(` note and `*.mjs` in the JS debug-leftover glob (DoWee had both). → aec980a

  From T7:
  - (j) done-gate FVM lookup: with `.fvmrc`, no `scripts/flutter.sh` and no `fvm` on PATH, v3 falls back to any global `flutter`, even one that does not match the pin (GRdLines: global 3.24.4 vs pinned 3.47.5). Look in `${FVM_CACHE_PATH:-~/fvm}/versions/<pin>/bin` first, and never gate with an unpinned SDK (NOT RUN instead); add a test case. → 49b1763
  - (k) done-gate with only the wrapper: `DART` stays empty, so pure-Dart members get `flutter analyze`/`flutter test`. `flutter test` fails grlines_core's vector tests (`Isolate.resolvePackageUriSync`), and CI uses `dart test`. Derive `DART` from the wrapper's SDK (`--which` → sibling `dart`) and run `dart analyze --fatal-infos` (parity with `flutter analyze`, which treats infos as fatal). Once fixed, GRdLines' wrapper can drop its pure-Dart dispatch. → de4545d
  - (l) `workspace_members`: a column-0 `- item` ends the block, trailing comments and CRLF are kept, and a listed member that is missing is skipped silently. GRdLines' old gate failed on a missing member. → 8337c48

  From T8:
  - (m) done-gate: `cd "$ROOT" || exit 0` fails open, so a wrong `CLAUDE_PROJECT_DIR` silently disables every gate (game1's old hook blocked). Decide fail-closed (exit 2) vs. a user note; add a test case. → 8d19494
  - (n) done-gate keeps only `tail -30` of a gate's log, so a local gate with several failing checks loses the earliest labels (game1 caps each check at 8 lines). Consider a larger tail for `local-*` gates or printing labels first. → 3518acf

  From T10:
  - (o) `sync-template.sh`: a per-project skip list (e.g. `.claude/template-exclude`, prefixes allowed). Matched paths are neither added by `--apply` nor shown as `new`; add a test case. InstaReels needs it for its 1142 excluded paths, best expressed as prefixes. → c083b89, 2d73ef1
  - (p) the "locally modified" advice is wrong for adapted template files kept on purpose (InstaReels' 7). Consider a `.claude/template-keep` list that silences them, with a test case. → 1d4a0f1, 2d73ef1

  Owner decisions (2026-11-26): (m) → NOT RUN user note (like the UNC case), not fail-closed. (o) and (p) are both in T11. Go-ahead given for the 5-group plan: done-gate env/markers (e, f, g), done-gate SDK (j, k, l), done-gate robustness (b, m, n), sync-template (h, o, p), single fixes (a, c, d, i). Each is test-first, with one commit per follow-up.
  Evidence (2026-11-26, at 2d73ef1): `bash scripts/test-hooks.sh` → `passed: 189  failed: 0`, rc 0 (157 at b425b7a). Each fix had a failing case first. (b) passed at once: it is new coverage, checked by a deliberate break of the hook (1 FAIL), then restored. (c) and (d) are test-file and docs changes checked by their own new cases. Fence: every change is in this template repo. No project repo was written; DoWee was only read (`git show`) to port its cases.
  Delivery: gate-scope `TIER=full`, and the full suite is test-hooks.sh. Review (opus code-reviewer): approve after fixing 1 medium. (1) With no base, the project's hook fields won over the template's → de83940. Low/nits fixed in 2a43155: member paths with spaces, the wp-env pattern also matched Flutter's "Binding has not yet been initialized", `--which` must name a file, a comment on fvm's cache config. Fix-diff review (opus): approve with 1 warning, fixed in df68bda (gates run with stdin closed). Nit skipped: `RAN` labels split on spaces, display only. Final: `passed: 193  failed: 0`.
  Every template bug logged in T1–T10 gets a fix on a template branch (TDD in `scripts/test-hooks.sh`), or is deferred by the owner.
  Done when: each follow-up line in the Verification log is either linked to a commit or marked deferred by the owner. The template's `bash scripts/test-hooks.sh` reports `failed: 0`. No files changed outside the template repo.
- [x] **T12 — Push (owner decision).** Ask once, listing the 9 pushable projects and their `develop` heads. On a yes, push each one and remove `/mnt/disque-d/Develope/_v3-rollout`.
  InstaReels (owner decision, asked with the push): its feature work merges into `main`, so v3 sits only on `develop` (2 commits ahead of `main`: eb41db0 and the merge; `main` has nothing new, so it is a fast-forward). Merge `develop` into `main`, or switch the project's flow to `develop`? No action without a yes.
  Done when: for every pushed project, `git -C <P> log origin/develop -1` equals the local `develop`; the folder is gone; no other files changed.
  Evidence (2026-11-26, owner yes "push all 3"): `ls-remote origin refs/heads/develop` == local `develop` for all 9. Already on the remote before T12 (pushed outside this task), each stamped `commit 918b981`: portfolio b67cbf5, AllaghenBrand fd718aa, StoreCoreTemplate 5d4d088, SghiraBrand 0fdf097, DoWee 45eef04, GRdLines 06a6609, game1 8140216. Pushed in T12: Lemqes fd5ee52..c698f3c (fast-forward; includes the owner's `docs: archive the m4 plan`), template `develop` 918b981..eedd5f1 (template `main` already 918b981). InstaReels: `develop` was pushed by a parallel InstaReels session as ad38e78 (contains the v3 merge 2864d3e), so `push` said up to date. `/mnt/disque-d/Develope/_v3-rollout` did not exist. Video Generator: no remote.
  InstaReels decision: merge `develop` into `main`. Not done here: `origin/main` moved to 7c12c1a (4 commits not in `develop`) and the checkout is in active use, so it is a task for an InstaReels session.

## Verification log
| Project | Dry run (new / updated / locally modified / removed) | Settings hooks kept/dropped | Gates | Review | Merged |
|---|---|---|---|---|---|
| portfolio | T0: 17 / 16 / 6 / 2 · est. 20 min. T1: d02845c (34 applied). Kept with the owner's yes: skill-nudge.sh (v3 plus `*/template/*.html`) and .gitattributes (v3 plus text=auto and a binary list). workflow.md's 2 lines moved to `local-gates.md`. llm-council copies deleted. Re-run of the dry run: `no changes` apart from those 2 | +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; nothing dropped | done-gate: rc 0, silent, 0 `run_gate` (no stack gate). Tier full = `pytest -m "not launch"` (scratch venv): 535 passed, 0 failed; 8 `launch` tests NOT RUN (they need real user input) | sonnet: approve. Coverage-loss warning rebutted: test-hooks.sh can't run in projects, so both cases go upstream in T11. Wording nit skipped | b67cbf5 (--no-ff; branch was develop before and after); worktree removed |
| Lemqes | T0: 24 / 19 / 0 / 2 · est. 15 min. T2: d755e91 (44 applied). No locally modified files. llm-council copies deleted. Re-run of the dry run: `no changes to apply.` | Kept its 3 (validate-code, sync-codex-on-edit, done-gate; now via `$CLAUDE_PROJECT_DIR`). +repo-guard, +session-guard, +skill-nudge (owner yes, 2026-11-25), +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; nothing dropped | done-gate: rc 0, `run_gate` lint + typecheck, both 0. Tier full = `npm test`: flutter test `+1248: All tests passed!`; `supabase test db` Files=18, Tests=993, PASS | sonnet: approve, no findings. Nit (done-gate unverified on Flutter) answered by the done-gate trace | fd5ee52 (--no-ff; branch was develop before and after); worktree removed |
| AllaghenBrand | T0: 19 / 15 / 6 / 2 · est. 45 min. T3: cf423c7 (35 applied); dry run 19 / 15 / 6 / 2 as T0. done-gate drift: escaping and 2 ENV_DOWN texts are in v3; `has not yet been initialized` → T11 (e); manual-mode and 8896-probe notes → `local-gates.md` (probe stays in settings env). delivery.md B1–B7 interim gate dropped (project plan marks B1–B7 done; full suite on every merge, noted in `local-gates.md`). workflow.md and pr.md project lines → `local-gates.md` + `local-workflow.md`. test-hooks.sh Allaghen cases dropped (template-owned; T11 (d)). Kept with the owner's yes: .gitattributes (`* text=auto eol=lf` + 7 binary types + v3). llm-council copies deleted. Re-run of the dry run: `no changes` apart from .gitattributes | Kept all project hooks and env (`DONE_GATE_MODE=manual`, `DONE_GATE_ENV_PROBE`). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Dropped the re-added pre-v3 allows (Read/Grep/Glob(**), `npm run build`, git add, git commit): 25acacf kept the project's own allow-list on purpose | Tier full. From the worktree: eslint rc 0; manual done-gate rc 0, 0 `run_gate` (as configured). After the merge, main checkout, wp-env started (owner yes, 2026-11-25): `npm run lint` rc 0 (phpcs 22/22, eslint clean); `npm test` `OK (19 tests, 169 assertions)`; `core:check` OK (70374ba); done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0 | sonnet: approve. Medium (a stopped wp-env would block the automatic gate) fixed in 4cd7056. Nit (probe untested once the test-hooks cases are gone) rebutted: the sync keeps the project's env. Nit on B1–B7 history in CLAUDE.md skipped (history only) | fd718aa (--no-ff; branch was develop before and after); worktree and `_v3-rollout` removed; wp-env left running |
| StoreCoreTemplate | T0: 16 / 8 / 4 / 0 · est. 30 min. T4: 3f95830 (25 applied); dry run 16 / 8 / 4 / 0 as T0. done-gate drift: the escaping and the WSL/ENOENT docker texts are in v3; the port-8892 probe → `DONE_GATE_ENV_PORT=8892` in settings env; the broader `ENOENT.*docker`/`docker\.sock` patterns were dropped (v3's `spawn docker ENOENT` and `Cannot connect to the Docker daemon` cover the real messages) → T11 (f). Manual-mode, port and scoped-merge-gate notes → `local-gates.md` (cb28823; StoreCore HAS `.claude/gate-core-paths`, so gate-scope prints `targeted`, not `full`). AGENTS.md's StoreCore line was already in CLAUDE.md. test-hooks.sh StoreCore cases dropped (template-owned; T11 (d), (f)). Kept: .gitattributes, a superset of v3 (`*.cmd` covers v3's `scripts/*.cmd`; adds text=auto, binary types, import fixtures), same as T1/T3. No llm-council copies (only the template's `skills-optional/`). Re-run of the dry run: `no changes` apart from .gitattributes | Kept all project hooks, allows and env (`DONE_GATE_MODE=manual`). +`DONE_GATE_ENV_PORT=8892`, +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing re-added: StoreCore's own allow-list already had Read/Grep/Glob(**), build, git add/commit | Tier targeted (no core path touched; no app code changed). From the worktree (haiku): eslint rc 0, no output; settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; manual done-gate rc 0, 0 `run_gate` (as configured); tree clean. After the merge, main checkout, wp-env started (owner yes, 2026-11-25): `npm run lint` rc 0 (phpcs 267/267, eslint clean); `npm test` `OK (1126 tests, 33230 assertions)`; done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0. No `wp-content/` change, so no AllaghenBrand `core:check` needed | sonnet: request changes (2 medium, 2 nits), no fix commits. Medium 1 (test-hooks.sh 155/157 in the project: README and ownership audit) rebutted: T11 (d), not a project gate. Medium 2 (StoreCore done-gate cases gone) rebutted: v3 covers the 8892-vs-other-port probe and `user_note` escaping; the ANSI phpcs marker still blocks (`FOUND [0-9]+ ERRORS?` is unanchored); its regression cases → T11 (f). Nit ("has not yet been initialized" unverified) kept: T3 saw that text from wp-env, and the old StoreCore test saw `✖ Environment not initialized`, so both forms exist. Nit (adb allows in a WordPress repo) skipped: harmless, same as every project | 5d4d088 (--no-ff; branch was develop before and after); worktree and `_v3-rollout` removed; wp-env left running |
| SghiraBrand | T0: 16 / 8 / 4 / 0 · est. 30 min. T5: 2a0be9f (25 applied); dry run 16 / 8 / 4 / 0 as T0. done-gate drift: the escaping and the `spawn docker ENOENT`/WSL texts are in v3; the probe stays in settings env (`DONE_GATE_ENV_PROBE`, wp-env `cli`); no template gap. delivery.md "design approval before the gate" (owner 2026-11-12) → `local-delivery.md`, word for word. Gate notes (probe, `node_modules`, path-bound wp-env, gate-core-paths) → `local-gates.md` (fixed in 2498791). test-hooks.sh SghiraBrand cases dropped (template-owned; v3 lines 70–99 cover service-not-running, probe up/down, `spawn docker ENOENT`, escaping; T11 (d)). Kept: .gitattributes, a superset of v3 (`*.cmd` covers `scripts/*.cmd`; adds text=auto, binary types, import fixtures), same as T1/T3/T4. No llm-council copies. Re-run of the dry run: `no changes to apply.` apart from .gitattributes; stamp `commit 918b981…` | Kept all project hooks, allows and env (`DONE_GATE_ENV_PROBE`; automatic gate, no `DONE_GATE_MODE`). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing re-added: history (374b0e5, 936a10b) never dropped anything | Tier targeted (`.claude/gate-core-paths` exists; no core path or app code touched). From the worktree after `npm ci` (haiku): eslint rc 0, no output; settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; done-gate (auto, project env): rc 0, `run_gate lint` → NOT RUN (wp-env not initialised for the worktree); tree clean. After the merge (owner yes, 2026-11-25): no checkout had `develop` (the main checkout is on `chore/b6-production-cutover`), so a temporary `develop` worktree at `Develope/SghiraBrand-v3-gates` (a sibling of `StoreCoreTemplate`, which `.wp-env.json` mounts) ran `npm ci` + `npm run env:start` (rc 0, seed done). From it (haiku): `npm run lint` rc 0 (phpcs 239/239, eslint clean); `npm test` `OK (41 tests, 502 assertions)`; done-gate with `DONE_GATE_MODE=auto`: rc 0, `run_gate lint` 0, no NOT RUN. Then `wp-env destroy --force` and the worktree was removed; AllaghenBrand's (8896) and StoreCore's (8892) wp-env left running | sonnet: approve. Medium (local-gates claimed a missing `node_modules` gives NOT RUN; it actually blocks as a lint failure, since `wp-env: not found` is not in `ENV_DOWN`) fixed in 2498791, with the nit on the probe's 60 s timeout and failure-path-only use. Nit (dropped project assertion that settings wires the wp-env probe) skipped: test-hooks.sh is template-owned and not a project gate (T11 (d)) | 7ef9859 (--no-ff, made in the rollout worktree; main checkout stayed on `chore/b6-production-cutover` cbaa0fa); worktree and `_v3-rollout` removed |
| DoWee | T0: 17 / 14 / 8 / 2 · est. 90 min. T6: 03814690 (32 applied); dry run 17 / 14 / 8 / 2 as T0. done-gate drift: FVM via `scripts/flutter.sh`, `user_note` escaping and the unchanged-tree skip are in v3; the missing-SDK NOT RUN and the extra Flutter `CODE_ERR` markers → T11 (g) (interim: `DONE_GATE_MODE=manual` in that machine's `settings.local.json`, noted in `local-gates.md`). validate-code drift (Dart `print(` note, `.mjs`, Supabase wording) is not a gate → T11 (i). Rules → `local-code-style.md`, `local-git.md`, `local-reporting.md`, `local-workflow.md`, `local-gates.md`; delivery.md had nothing project-specific (old pre-gate-scope step 1); the full-gate-before-merge rule stays in CLAUDE.md. test-hooks.sh DoWee cases dropped (template-owned; T11 (d), (g)). llm-council copies deleted. No .gitattributes drift. Re-run of the dry run: no locally modified or removed line; only `merge .claude/settings.json` (Stop timeout 600 → 300), kept with a reason (T11 (h)); stamp `commit 918b981…` | Kept all project hooks, allows and denies (no env block). +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow; template allow order taken (cosmetic). Stop timeout kept at 600 (a188a61f set it for `DONE_GATE_FULL` tests; the merge resets it, T11 (h)). Nothing dropped: history (86d6aa7b, c799899a, a188a61f) never removed a template hook | Tier full (`^scripts/` is a core path). From the worktree after `scripts/flutter.sh pub get` (haiku): settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts; done-gate (auto): rc 0, one `run_gate analyze bash …/scripts/flutter.sh analyze --no-pub`, silent. `bash scripts/gate.sh` (the owner's full gate, CLAUDE.md): 12 PASS (analyze + test for root, admin_console, dowee_design; both web builds; website check and layout; backend edge tests and SQL suites) and 1 FAIL, Lighthouse `/contact` performance 0. Re-run of `npm run lighthouse` alone: rc 0, `/contact` 100, so a flaky run (no `website/` change on the branch); tree clean | sonnet: approve, no critical/high/medium. Nit 3 (manual mode turns the whole Stop gate off) fixed in 25015046. Nit 1 (the restore-600 step relies on memory) → T11 (h). Nit 2 (list `local-*.md` in CLAUDE.md) skipped: they auto-load and AGENTS.md points to them | 673883ea (--no-ff, made in the rollout worktree; the main checkout stayed on `feat/android-app-links` 5a2216c9, clean). CLAUDE.md asks for the owner's yes before a merge to develop: taken as given by the T6 request. Worktree and `_v3-rollout` removed |
| GRdLines | T0: 26 / 16 / 4 / 2 · est. 60 min. T7: 709142d (43 applied); dry run 26 / 16 / 4 / 2, same as T0. done-gate drift (base 7050904, 120 lines): FVM PATH pin, per-member analyze/test and `user_note` escaping are in v3. The root `dart format` check → `.claude/hooks/local/dart-format.sh`. Missing pinned SDK: the old hook gave a non-blocking message, it now blocks with exit 127 → T11 (g). v3 had no FVM fallback without `fvm` on PATH (it would gate with the global 3.24.4) → new project wrapper `scripts/flutter.sh` (DoWee's shape, no `.flutter-sdk` branch) and T11 (j). Pure-Dart members under the wrapper ran `flutter test` → wrapper dispatches them to the pinned `dart analyze --fatal-infos` / `dart test` (7a70acf), with T11 (k). Missing-member failure and awk tolerance → T11 (l). sync-codex-on-edit drift is the old ROOT cd; v3 is equivalent, so nothing kept. Rules → `local-code-style.md` (Dart lints, no `dynamic`, exception types) and `local-reporting.md` (plain-words decisions). No .gitattributes before; v3's added. llm-council copies deleted. Re-run of the dry run: `no changes to apply.`; stamp `commit 918b981…` | Kept its 3 (validate-code, sync-codex-on-edit, done-gate; Stop timeout 300 unchanged) and its allow-list. Added: +repo-guard, +session-guard, +skill-nudge (owner yes, 2026-11-25), +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing dropped: history (8c6571f, 69f30b3) never removed a template hook | Tier full (no `.claude/gate-core-paths`). From the worktree after `scripts/flutter.sh pub get` (haiku): settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks and scripts. done-gate (auto): rc 0, 5 `run_gate` (`analyze` for core, engine, online, mobile via `scripts/flutter.sh` + `local-dart-format`). done-gate with `DONE_GATE_FULL=1`: first rc 2 (core `flutter test` `+133 -2`, vector tests, `Isolate.resolvePackageUriSync`; reproduced on re-run). After 7a70acf: rc 0, 9 `run_gate` (analyze + tests ×4, format). Wrapper exec traces: core `…/3.47.5/bin/dart analyze --fatal-infos` and `dart test` (vectors `+21`), mobile `…/flutter analyze --no-pub`. Direct, as CI runs them (pinned PATH): core analyze `No issues found!`, `+135: All tests passed!`, `gen_vectors --check` up to date; engine `No issues found!`, `+335`; online analyze `No issues found!` (its tests need a Supabase stack: NOT RUN, env); mobile `No issues found!`, `+517 ~5: All tests passed!`. APK and iOS builds not run (no app code changed); tree clean | sonnet: approve, 2 nits; both fixed (0c49bd1 awk keeps column-0 items; ff944dd rule points to the pinned wrapper). The gate run then found the `flutter test` regression the review missed; fixed in 7a70acf. Fix-diff review (sonnet): approve, 2 warnings fixed in 6b5c9ac (empty `args` under `set -u` on bash < 4.4; a PATH `flutter` paired with PATH `dart`), checked on the cache, pure-Dart and PATH branches. Nits (cwd-relative pubspec check; flutter-only flags forwarded to dart) skipped: the gate always runs from the member directory | 957cded (--no-ff, in `GRdLines-close-plan2`; main checkout stayed on `feat/ai-h4` 90ee38a, clean). No merge-approval rule in GRdLines' CLAUDE.md. Worktree and `_v3-rollout` removed |
| UnityGames/game1 | T0: 26 / 17 / 2 / 2 · est. 45 min. T8: dry run 26 / 17 / 2 / 2, same as T0; d6e77aaa (44 applied). done-gate drift (base a5878a5, 108 lines) is NOT a stackless hook: it is the project's 4-area gate (stages `python3 Tools/check_levels.py`; prototype and original `node` tests/route checks; unity `bash Tools/unity_check.sh`, Roslyn compile + C# tests), each cached by a per-area fingerprint in `.git/done-gate/`. Moved verbatim into `.claude/hooks/local/game-areas.sh` (exit 1 + failures on stdout); v3 covers the npm part. Project test `.claude/hooks/done-gate.test.sh` kept with a reason (project-owned, adapted): it now drives v3 + the local script; `reset_fixture` also clears `done-gate.last`; the "bad project directory blocks" case dropped (v3 passes with exit 0 when it cannot cd, template-owned) → T11 (m). workflow.md drift (base 54fea7d, 5 lines: the Stop-hook note) → `local-workflow.md`; `CLAUDE.md` pointer names the local script. llm-council copies deleted. Re-run of the dry run: `no changes to apply.`; stamp `commit 918b981…` | Kept: graphify hook-guard ×2 (PreToolUse), validate-code, sync-codex-on-edit, done-gate (Stop timeout 300 unchanged) and its allow-list. Added: +repo-guard, +session-guard, +skill-nudge (owner yes, 2026-11-25), +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow. Nothing dropped: history (971d1d02, 197ed376) never removed a template hook | Tier full (no `.claude/gate-core-paths`). haiku: settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks, scripts and `Tools/*.sh`; `done-gate.test.sh` 28 ok, `All done-gate tests passed.` (old suite 29, 1 dropped as above). Its done-gate trace was refused (its command `rm -rf`'d the gate state); run by me instead with no state present (nothing deleted): rc 0, `run_gate local-game-areas`, all 4 areas recorded (`original prototype stages unity`); second run skipped, rc 0, 0.03 s. After the fixes: rc 0 in 27 s (every area re-checked, the script's hash changed). Directly: `check_levels.py` `12 of 12 stages passed`; prototype `game.test.js` rc 0, `art.test.js` `Art regression checks passed`, `verify-routes.js` `60/60 …`; original `verify-routes.js` `28/28 …`; `unity_check.sh` `79/79 tests passed`, `0 compile error(s), 0 failed test(s)`. Unity play-test not run (no game code changed); tree clean | sonnet: approve; W1 local rule demanded a full gate at every merge (fixed 86a3c1eb); W2 failure tail could cut a block's label under v3's `tail -30` (fixed ae394ae2: 8 lines per check); W3/N2 test notes the template's bad-dir case and tests the per-area cache directly (424241cd); N1 (`llm-council` in CLAUDE.md) rebutted: no such line; N3 no action. Optional `.claude/gate-core-paths` left to the owner. Fix-diff review (sonnet): approve, 1 nit (only the last three failing checks keep labels) fixed in the comment | 81402163 (--no-ff, in `.claude/worktrees/chore-rules`; main checkout stayed on `feat/unity-tales-slice1` ed445896, only `last_query_stamp` modified). No merge-approval rule in game1's CLAUDE.md. Worktree and `_v3-rollout` removed |
| Video Generator | T0: 24 / 16 / 3 / 2 · est. 25 min. T9: dry run 24 / 16 / 3 / 2, same as T0; 094f8c4 (41 applied). done-gate drift (base 7050904, 9 lines): the tests ran on every stop instead of only with `DONE_GATE_FULL=1` (suite = ~10 s offline smoke render) → `"env": {"DONE_GATE_FULL": "1"}` in `settings.json`; nothing else in the hook was project-specific, no `hooks/local` needed. workflow.md drift (base 315869f, 3 lines: `pgrep -f` self-match, bracket pattern) → `local-workflow.md` (complements v3's Windows / WSL note), plus the `DONE_GATE_FULL` reason (e18b0f5). CATALOG.md drift (base 1360d12, 34 lines: researched video skills) → `docs/skill-research.md` (`docs/*` is project-owned per `docs/template-files.md`, so it is the step-3 destination here) and a one-line `CLAUDE.md` pointer. No .gitattributes before; v3's added (no tracked file rewritten). llm-council copies deleted (only other mention: `activate-design.sh off`, an `rm -rf` of the old path, harmless). Re-run of the dry run: `no changes to apply.`; stamp `commit 918b981…` | Kept its 3 (validate-code, sync-codex-on-edit, done-gate; Stop timeout 300 unchanged) and its allow/deny lists. Added: +repo-guard, +session-guard, +skill-nudge (owner yes, 2026-11-26), +delegate-guard (×2 matchers), +4 adb read-only perms, +autoCompactWindow, +env `DONE_GATE_FULL=1`. Nothing dropped: its only settings commit (0040bf6, 2026-11-08) predates those 3 hooks (template 42de232, 2026-11-23), so they were never removed on purpose | Tier full (no `.claude/gate-core-paths`). From the worktree after `npm ci` (haiku): settings.json and launch.json.example valid JSON; `bash -n` clean on all hooks, `scripts/*.sh`, `voice/*.sh`; `npm run lint` rc 0, no warnings; `npm test` rc 0, `tests 58`, `pass 55`, `fail 0`, `skipped 3`. done-gate (auto, `DONE_GATE_FULL=1`, no prior state): rc 0, 2 `run_gate` (`lint npm run lint`, `tests npm test`); second run rc 0 in 0.035 s (skip). Tree clean. No render or voice run (no app code changed) | sonnet: approve, 2 nits. N2 (the every-stop reason only lived in the old hook comment) fixed in e18b0f5. N1 (`scripts/sync-codex.cmd` is LF under `eol=crlf`) rebutted: `ls-files --eol` shows `i/lf`, the correct index form for `eol=crlf`, same as in the template. Fix-diff review (sonnet): approve | 111333c (--no-ff, in the rollout worktree: `develop` was checked out nowhere; main checkout stayed on `feat/tafsut-storyteller-voice` 7ef219d, its 7 uncommitted files untouched). No merge-approval rule in its CLAUDE.md. Worktree and `_v3-rollout` removed. No remote: not in T12 |
| InstaReels | T0 (from `main`): 1157 / 1 / 9 / 2 · est. 60 min + vendored-skills decision. T10: `develop` created from `main` (63823eb; old `origin/develop` d6a1206 is its ancestor, so T12 fast-forwards). Dry run 1157 / 1 / 9 / 2, same as T0; eb41db0 (1159 applied), then content-only per owner decision 2: the 1142 excluded paths (the 1135 of the 56096bb strip + skill-nudge.sh, android-emu/ui.sh, `scripts/fixtures/ui-*.xml`, test-hooks.sh) removed again, llm-council copies deleted. pr.md project lines → `local-git.md` ("main" → "main (or develop)"); reporting.md lines → `local-reporting.md`, word for word; AGENTS.md gained voice-direction.md and "every local-*.md"; CLAUDE.md @-imports both local files. v3 .gitattributes taken (`git add --renormalize .` rewrites no tracked file). Re-run of the dry run: 1142 `new` = the exclusion list exactly (`cmp`), 7 `locally modified` = the adapted files kept with a reason (workflow.md, deepen and retro skill + command, `.codex/config.toml`, AGENTS.md), nothing else; stamp `commit 918b981…`. Skipping the excluded paths on every sync → T11 (o); keep-list for adapted files → T11 (p) | Kept all project permissions and hooks (now via `$CLAUDE_PROJECT_DIR`). Added: +repo-guard, +session-guard, +delegate-guard, +autoCompactWindow. Not added (owner decision 3): done-gate, skill-nudge, npm and adb permissions. Codex config's only hook is validate-code.sh | No stack gate, done-gate excluded by owner. gate-scope (template copy): TIER=full (no `.claude/gate-core-paths`); the project has no test suite. From the worktree (haiku), all rc 0: settings JSON valid; `bash -n` on all hooks and scripts; `py_compile` on `scripts/reels/*.py` and usage-report.py; all 6 settings hook commands point to existing files; smoke runs of delegate-guard, repo-guard, session-guard, validate-code; `sync-codex.sh` leaves a clean tree | sonnet: approve, 3 nits, all rebutted. (1) `sync-codex.sh:44` comment names superpowers: template-owned, the project does not edit it. (2) "main (or develop)" in local-git.md: intended, `develop` now exists. (3) AGENTS.md "every local-*.md" also matches local-example.md: the template's own placeholder, same as v3 wording | 2864d3e (--no-ff, in the rollout worktree: `develop` was checked out nowhere; main checkout stayed on `chore/after-tk01-merge` cfee78f, its 13 uncommitted files untouched, `cmp` of `status --porcelain` before/after). No merge-approval rule in its CLAUDE.md. Fence: `diff --name-status develop^1...chore/template-v3` = the 26 paths of eb41db0; `git diff --stat` empty for them in the main checkout. Worktree and `_v3-rollout` removed. Note: feature work merges into `main`, so v3 sits only on `develop` (decision request in T12) |

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

---

## Archived 2026-11-25 — template v3: fix, make updatable, cut cost, add device testing

Released: `develop` and `main` at 918b981, pushed 2026-11-25 (suite 157/0 on both).

**Objective:** make the template's guarantees reach every project and actually cut cost, and give browser/emulator testing ready-made tools instead of per-session reinvention.

**Evidence (audit 2026-11-25, this machine):** 10 project repos, 74 Claude main sessions + 618 subagent runs, 163 Codex rollouts. ≈ $4,170 API-equivalent; ~52% is cache-reads of long contexts (avg Opus main-thread turn 360k; compaction only at ~966k). 16 "pulled changes, what's next" sessions = $822. 50% of Agent calls name no model (inherit Opus). 3,982 browser calls and 2,732 images in main threads. An adb helper (`ui.sh`) was rebuilt and sourced 329 times; 1,220 `sleep`s ≈ 1 h of blind waiting; the boot loop was rewritten ~17 times. No project has a template remote; 5 of 10 repos have none of the Nov changes; DoWee, StoreCore and Allaghen hand-merged done-gate. SghiraBrand and StoreCore each fixed a done-gate notice bug the template still has.

**In scope:** `.claude/hooks/`, `.claude/settings.json`, `.claude/launch.json.example`, `.claude/template-version`, `.codex/config.toml`, `.claude/rules/`, `.claude/commands/`, `.claude/skills/testing-patterns/`, `scripts/` (incl. `scripts/fixtures/`), `CLAUDE.md`, `AGENTS.md`, `README.md`, `CATALOG.md`, `.agents/skills/` (regenerated by `scripts/sync-codex.sh`), `.gitignore`, `docs/`, `task_plan.md`.
**Out of scope:** rolling v3 into the 10 projects (next plan — this plan makes that rollout cheap); merging `develop` into `main` (owner decision, see Risks); vendored plugins (superpowers, impeccable); any project repo; Codex equivalents of Claude-only PreToolUse/UserPromptSubmit hooks.

**Approach:** bug fixes first, so they ride the next rollout. Then the update path, because every later task is worthless until projects can receive it. Then cost (hard caps and enforcement beat more advice — the advice already exists and was ignored), then testing tools promoted from what sessions proved works. Hooks stay dependency-free bash (Windows/WSL machines too); `sync-template.sh` and `usage-report.py` may use python3 (manual tools, not hooks). Every new hook/script behaviour gets a case in `scripts/test-hooks.sh` written first (red → green), with fake binaries on `PATH` where a real device or Docker is needed. **Every task that adds a tracked file also adds it to `docs/template-files.md`** (T3's test enforces this from T3 on).

**Baseline:** `bash scripts/test-hooks.sh` → 50 passed, 0 failed on Linux at eebc4f8 (Windows log said 51; T1 finds which case is platform-skipped).

## Tasks

- [x] **T1 — done-gate notices survive any message (bug U1).** `user_note` (done-gate.sh:36-39) escapes only `\` and `"`; also escape `\r`, `\n`, `\t` and strip other control chars, backslash first. Record in the Verification log which case is skipped on Linux.
  Done when: (1) new cases: a failing gate whose log tail has newlines/tabs AND a literal `\n` yields a `systemMessage` line that `python3 -c 'import json,sys; json.loads(sys.stdin.read())'` accepts (SKIP printed if no python3) — red before, green after; (2) full suite green; (3) no files changed outside `done-gate.sh`, `scripts/test-hooks.sh`, `task_plan.md`.

- [x] **T2 — environment probe fits multi-site machines (bug U2).** ENV_DOWN gains `spawn docker ENOENT` and `could not be found in this WSL`. New `DONE_GATE_ENV_PORT`: env up = `ports=$(timeout 10 docker ps --format '{{.Ports}}')` then `[[ $ports == *":$PORT->"* ]]` (no pipe into `grep -q`: SIGPIPE under pipefail, per StoreCore). Document `DONE_GATE_ENV_PROBE`/`_PORT` in the hook header and README hooks section (Allaghen curl example).
  Done when: (1) cases with a fake `docker` on PATH: own port published + lint error → blocks (exit 2); only another port published + env-down log → NOT RUN (exit 0); `spawn docker ENOENT` log with docker absent → NOT RUN; (2) suite green; (3) fence: `done-gate.sh`, `scripts/test-hooks.sh`, `README.md`, `task_plan.md`.

- [x] **T3 — File ownership is explicit; local customisation has its own files.**
  - `docs/template-files.md`: machine-readable table, one path or glob per line with owner `template` / `project` / `merged` (`.claude/settings.json` = merged: template owns `hooks` + `permissions`, project owns `env`; CLAUDE.md, `.mcp.json`, `task_plan.md`, `SPEC.md` = project; AGENTS.md and `.codex/config.toml` = template).
  - Project additions live in `.claude/rules/local-*.md` (+ `local-example.md` shipped as the format). First verify in the Claude Code memory docs whether `.claude/rules/*.md` auto-loads; if not, CLAUDE.md's template section gets one `@.claude/rules/local.md` index line (an `@` import doesn't glob). AGENTS.md gets "also read every `.claude/rules/local-*.md`" for Codex.
  - Hook behaviour is configured only via settings `env` (`DONE_GATE_CMD`, `DONE_GATE_MODE`, `DONE_GATE_ENV_*`, `CONTEXT_WARN_TOKENS`) plus `.claude/hooks/local/*.sh`, which done-gate runs as extra gates.
  Done when: (1) cases: `.claude/hooks/local/extra.sh` exit 1 → gate blocks, exit 0 → passes; a test compares `git ls-files` against `docs/template-files.md` globs and fails on any unlisted path; the memory-docs URL and finding are recorded under Risks; (2) suite green; (3) fence: `done-gate.sh`, `scripts/test-hooks.sh`, `CLAUDE.md`, `AGENTS.md`, `.claude/rules/local-example.md`, `docs/template-files.md`, `README.md`, `task_plan.md`.

- [x] **T4 — `scripts/sync-template.sh`: pull template updates into a project.** `bash scripts/sync-template.sh <template-dir> [--ref <branch>] [--apply]` (default ref = the branch the owner names for releases, see Risks). Reads `docs/template-files.md` from the template. Per template-owned file: **new**, **unchanged**, **updated** (project blob equals ANY historical blob of that path in the template — `git log --format=%H -- <path>` + `git rev-parse <c>:<path>` — so a never-synced but unmodified old copy is safe to update; once `.claude/template-version` exists, its commit is the base), **locally modified** (no historical match: never overwritten; diff printed with "move this into local-*"), **removed upstream** (listed, never deleted). `merged` files: python3 merges template `hooks` + `permissions` into the project's settings.json and keeps its `env` (without python3: print the diff and stop). `--apply` copies new+updated, merges, runs `scripts/sync-codex.sh`, writes `.claude/template-version` (commit + date). Never commits, never touches project-owned paths.
  Done when: (1) a case builds two temp repos — template with 2 commits; project with: a hook equal to the OLD template version, a locally modified rule, a custom settings `env` key, a file removed upstream; dry run → updated / locally modified / removed-upstream listed, `git status` clean; `--apply` → old hook updated, modified rule untouched, settings has the template's new hook AND the project's env key, stamp written; second `--apply` → no changes; (2) suite green + `bash -n`; (3) fence: `scripts/sync-template.sh`, `scripts/test-hooks.sh`, `README.md` (replaces the `-X ours` section), `.claude/template-version`, `docs/template-files.md`, `task_plan.md`.

- [x] **T5 — Projects learn they are behind.** On the first prompt of a session, session-guard reads `$TEMPLATE_DIR` (machine path: set in `.claude/settings.local.json` `env` or the shell, never committed) and runs `timeout 5 git -C "$TEMPLATE_DIR" rev-list --count <stamp>..<TEMPLATE_REF>` (no fetch). Behind → one line "template is N commits newer — run `scripts/sync-template.sh` (dry run)". No stamp → "never synced — run a dry run". Unset/unreadable dir or unknown stamp commit → silent.
  Done when: (1) cases: behind → notice once per session; up to date → silent; no stamp → never-synced line; TEMPLATE_DIR unset → silent; stamp commit absent from TEMPLATE_DIR → silent; (2) suite green; (3) fence: `session-guard.sh`, `scripts/test-hooks.sh`, `README.md`, `task_plan.md`.

- [x] **T6 — Context is capped, not just warned about.** Expected candidates to confirm in the primary sources (Claude Code settings/env-var docs, model-config docs): an auto-compact percentage override env var (≈30% of a 1M window ≈ 300k) and/or a model alias without the 1M (`[1m]`) window. Record exact names + URLs under Risks, then set them in settings.json `env`/`model`. session-guard's 150k text becomes: "finish the current step, then write `docs/handoff.md` and tell the user to start a fresh session — do not start a new step".
  Done when: (1) Risks cites the doc URL(s) and setting names; a test asserts settings.json is valid JSON with those keys and values; 160k transcript → message contains "finish the current step" and "do not start a new step" (red before); (2) suite green; (3) fence: `settings.json`, `session-guard.sh`, `scripts/test-hooks.sh`, `.claude/rules/reporting.md`, `task_plan.md`. If the docs offer no such setting, amend this task (say why) to wording-only — never invent a key.

- [x] **T7 — `/next` command.** `.claude/commands/next.md`: read `task_plan.md`, `git log -5`, `git status`; pick ONE next task with a one-line why (reporting.md decision format); write `docs/handoff.md` (git-ignored, local); create the branch only on the user's yes; tell the user to start a fresh session with the handoff. Never starts the work. delivery.md steps 5–6 point to `/next` instead of restating it. sync-codex already mirrors commands → `$next`.
  Done when: (1) command file has those steps; README commands table lists it; `.agents/skills/next/` exists after sync; a `/next` dry run in a scratch copy of this repo writes a handoff and stops (excerpt in the Verification log); (2) suite green; (3) fence: `.claude/commands/next.md`, `.claude/rules/delivery.md`, `README.md`, `.agents/`, `docs/template-files.md`, `task_plan.md`.

- [x] **T8 — `delegate-guard` hook and fan-out cap.** PreToolUse `Agent|Task`: no `model` in the input AND the `subagent_type` has no agent file with a `model:` line other than `inherit` → once-per-session `additionalContext` warning pointing to workflow.md's model table (code-reviewer/security-auditor are `inherit` on purpose: silent). `DELEGATE_GUARD=strict` → deny (exit 2); `=off` → silent. PreToolUse `mcp__Claude_Browser__.*|mcp__claude-in-chrome__.*`: if the hooks docs expose a field that marks subagent calls (verify; record under Risks), remind main-thread callers once per session to move browser checks to a `sonnet` subagent; otherwise remind every caller once per session. workflow.md: ≤4–6 parallel subagents per wave; implementer subagents report back after ~60 turns. AGENTS.md: same cap for Codex `spawn_agent` + one task = one session.
  Done when: (1) cases: general-purpose without model → warning once, not deny; code-reviewer without model → silent; with model → silent; strict → exit 2; off → silent; browser call → reminder once per session (and main/subagent split if the field exists); grep shows the cap lines in workflow.md and AGENTS.md; (2) suite green; (3) fence: `.claude/hooks/delegate-guard.sh`, `settings.json`, `scripts/test-hooks.sh`, workflow.md, AGENTS.md, `README.md`, `docs/template-files.md`, `task_plan.md`.

- [x] **T9 — `scripts/android-emu.sh up|down|status`.** `up`: `setsid nohup emulator -avd "$AVD" -no-snapshot-save -no-audio [${EMU_HEADLESS:+-no-window}] </dev/null >log 2>&1 &`; bounded wait (`timeout 240 adb wait-for-device` + `sys.boot_completed` loop); free-space check on /data with `-wipe-data` advice. `down`: stop emulator + gradle daemon. `status`: device, boot state, free RAM, heavy processes.
  Done when: (1) cases with fake `adb`/`emulator` on PATH: `up` returns 0 when getprop flips to 1, exit 1 with a message after the (test-shortened) timeout; low /data → advice printed; `down` calls `adb emu kill`; (2) suite green + `bash -n`; (3) fence: the script, `scripts/test-hooks.sh`, `README.md`, `docs/template-files.md`, `task_plan.md`.

- [x] **T10 — `scripts/android-ui.sh`.** `dump | tap "<text>" | wait-for "<text>" [secs] | shot <file> | type <s> | key <k> | swipe | back`, via `uiautomator dump` + `exec-out screencap`, `ADB_SERIAL` overridable. `wait-for` polls the dump (no blind `sleep`) and names an ANR dialog if one appears.
  Done when: (1) cases with fake `adb` + fixture dumps: `tap "Save"` sends `input tap` at the bounds centre; `wait-for` → 0 when text appears, 1 on timeout, prints "ANR" on the ANR fixture; (2) suite green + `bash -n`; (3) fence: the script, `scripts/fixtures/`, `scripts/test-hooks.sh`, `README.md`, `docs/template-files.md`, `task_plan.md`.
  Optional, separate: one live smoke on this machine (`android-emu.sh up` → `android-ui.sh wait-for` launcher text → `shot` → `down`) only with the owner's go-ahead (emulator loads the NVMe); recorded in the Verification log.

- [x] **T11 — Browser and device testing guidance.** `testing-patterns` gains "Browser checks" (screenshot after navigate/resize and before any coordinate click; prefer `find` refs; batches ≤25 real actions; local pages via `.claude/launch.json`, never `file://` with spaces; `python3` in launch.json; canvas apps (Flutter web, games) verify via JS state or integration tests; dismiss "Leave site?" first; Codex `playwright-cli`: curl-retry the server before `open`) and "Android/device checks" (T9/T10 scripts; UI dump before screenshot; ≤1 screenshot per state; one emulator/server per session, stopped at task end; check heavy processes first; turn manual flows into `integration_test -d <id>`). Ship `.claude/launch.json.example`. Allowlist read-only adb commands in settings.json `permissions`.
  Done when: (1) grep shows the section headings and the strings "≤25", "file://", "uiautomator dump"; `launch.json.example` parses as JSON; settings.json allows `adb devices`, `adb exec-out screencap`, `adb shell uiautomator dump`, `adb shell getprop`; `.agents/skills/testing-patterns` matches after sync; (2) suite green; (3) fence: testing-patterns (both copies), `.claude/launch.json.example`, `settings.json`, `README.md`, `docs/template-files.md`, `task_plan.md`.

- [x] **T12 — done-gate: FVM and Dart workspaces (U4, code).** When `.fvmrc` exists, Flutter/Dart gates run via `scripts/flutter.sh` if present, else `fvm flutter`/`fvm dart` (DoWee, Lemqes). A pub workspace root (`workspace:` in pubspec.yaml) runs `dart analyze` per member package (GRdLines).
  Done when: (1) cases: `.fvmrc` + fake `fvm` → gate runs `fvm flutter analyze` (not plain `flutter`); workspace fixture with 2 members → analyze runs in both; (2) suite green; (3) fence: `done-gate.sh`, `scripts/test-hooks.sh`, `scripts/fixtures/`, `task_plan.md`.

- [x] **T13 — Text lessons from projects (U4, docs).** testing-patterns: "destructive integration runs refuse non-local DB hosts" (Lemqes); wp-env: "stopping from the host leaves PHPUnit running in the container" and "no lint/wp-env command while e2e runs"; self-seeding Playwright `globalSetup`, `workers: 1` (StoreCore). workflow.md: "`pgrep -f`/`pkill -f` match their own command line" and "never edit a shell script bash is running" (Video Generator); "no unscoped migration push" and "resume labelled test records, never reseed" (DoWee). pr.md: "quote paths with spaces; anchored renames". CATALOG: staging-WordPress MCP via dotenv-cli.
  Done when: (1) grep finds each exact string: "non-local", "PHPUnit running in the container", "globalSetup", "pgrep -f", "running shell script", "unscoped", "test_label"/"labelled", "anchored", "dotenv-cli"; (2) suite green; sync-codex run; (3) fence: testing-patterns (both copies), workflow.md, pr.md, CATALOG.md, `task_plan.md`.

- [x] **T14 — Repeatable usage report.** `scripts/usage-report.py [--project <path>] [--since D] [--until D]` (python3 stdlib, read-only): per project/model tokens and $ (dated price table at top), max context per session, sessions >150k / >400k, subagent share, Agent calls without model, main-thread browser calls/images; merges all mount-path variants of the project dir; dedups usage by message id.
  Done when (amended 2026-11-25, owner-approved: the audit's price assumptions were never recorded): (1) `--until 2026-11-25` over all projects reports ≈ $4,170 ±10% with the documented price table and ≈50% Agent calls without model; a fixture JSONL in test-hooks gives exact expected totals (SKIP without python3); (2) suite green; (3) fence: the script, `scripts/fixtures/`, `scripts/test-hooks.sh`, `README.md`, `docs/template-files.md`, `task_plan.md`.

- [x] **T15 — Delivery.** `bash scripts/gate-scope.sh` tier; full `scripts/test-hooks.sh`; `bash -n` on all `.sh`; one code-reviewer pass on the branch diff (fix or rebut each finding, max 2 fix rounds); README "What's new in v3" + update instructions; merge `chore/template-v3` into `develop`, not pushed without the owner's yes.
  Done when: (1) review findings table in the Verification log; (2) suite green at the merge commit; (3) `git diff --name-only develop...` lists only In-scope paths.

## Verification log
| Suite | Commit | Result |
|---|---|---|
| scripts/test-hooks.sh (Linux) | eebc4f8 | 50 passed, 0 failed (baseline) |
| T1 notice JSON case: red (detail missing) → green | 51050b9 | 51 passed, 0 failed. Linux-skipped case = repo-guard "escaped Windows path" (Git Bash `pwd -W` only) → Windows 51 vs Linux 50 |
| T2 env-port/ENOENT/WSL cases: 3 red → green (port-published case passed before: real docker up) | cc792b6 | 55 passed, 0 failed |
| T3 local-gate + ownership cases: 2 red → green; negative check (CATALOG row removed → "unlisted paths CATALOG.md") | 0610815 | 58 passed, 0 failed |
| T4 sync-template: 10 cases red (script missing) → green; `bash -n` ok. Default ref = `$TEMPLATE_REF` or `main` (owner decision pending) | 8b2eda1 | 68 passed, 0 failed |
| T5 template-behind cases: 2 red (behind, never synced) → green; silent cases passed before by construction | 47a6e56 | 75 passed, 0 failed |
| T6 wording + autoCompactWindow cases: 2 red → green | b87ebf8 | 77 passed, 0 failed |
| T7 /next cases: 4 red → green; sonnet dry run in a scratch clone: presented one decision (blocker first), wrote git-ignored `docs/handoff.md` ("# Handoff — T7 `/next` command…"), no branch, stopped. Its 2 gaps fixed: no local `develop` → `origin/develop`; half-done task → "finish task N" | 222bd98 | 81 passed, 0 failed |
| T8 delegate-guard: 12 cases (9 hook + wiring + 2 cap greps) red → green | b915afc | 95 passed, 0 failed |
| T9 android-emu: 6 cases (fake adb/emulator: boot, timeout, low /data, down, status) red → green; `bash -n` ok | 0a1c1fc | 101 passed, 0 failed |
| T10 android-ui: 11 cases (fake adb + 3 fixture dumps: tap centre/content-desc/missing, wait-for appear/timeout/ANR, shot, type, back, ADB_SERIAL) red → green; `bash -n` ok. Live emulator smoke NOT run (needs owner go-ahead) | 050fe56 | 112 passed, 0 failed |
| T11 guidance: 4 cases (sections + strings, .agents sync, launch.json.example parses, adb allow-list) red → green | fe0523b | 116 passed, 0 failed |
| T12 FVM/workspace: 3 cases (fake fvm/flutter/dart: `.fvmrc` → fvm, `.fvmrc`+wrapper → wrapper, 2-member workspace → analyze in both) red → green; fixtures built inline in the test (no `scripts/fixtures/` file needed) | 0514b21 | 119 passed, 0 failed |
| T13 lessons: 10 grep cases red → green ("running shell script" phrased "Never edit a running shell script"; CATALOG entry names no specific WP MCP package — unverified, left as placeholder); sync-codex run | 30bccee | 129 passed, 0 failed |
| T14 usage-report: 3 fixture cases red → green (exact totals, dedup, mount merge, --until, no-model, main-thread browser/images). Real run `--until 2026-11-25`: **$3,945.54 (−5.4% vs $4,170: outside ±5%)**, 298/582 Agent calls without model (51% ✓), 2,732 main-thread images (exact ✓), 3,715 main browser calls (audit 3,982 counted all threads), 75 sessions (audit 74), 71 >150k / 41 >400k, subagents 20%. Box left unchecked: amendment proposed under Risks | 1497e47 | 132 passed, 0 failed |
| T14 amended Done-when (±10%, owner-approved). Re-run after the id-less fix: $3,958.02 (−5.1%), 298/583 Agent calls without model (51%) | 3e4c53b | ✓ |
| T15 review fixes 1–13: each case red → green (22 new/changed cases), split commits each tested on their staged snapshot; finding 7 rebutted with real-log evidence | 3ae4ba4 | 154 passed, 0 failed |
| T15 re-review round 1 (A–E): 3 red → green, split commits tested per snapshot; `bash -n` all `.sh` ok; gate-scope TIER=full; `git diff --name-only develop...` → 0 paths outside In scope | dd0c1da | 157 passed, 0 failed |
| Plan review (fresh-context subagent) | draft 1 | 15 findings (2 critical, 8 major, 5 minor) — all adopted in this version |

## T15 review findings (code-reviewer, opus, `develop...55e6e2a`): verdict "request changes"
| # | Sev | Where | Finding | Status |
|---|---|---|---|---|
| 1 | major | done-gate.sh:156-161 | `.fvmrc`+`scripts/flutter.sh`+workspace → members analyzed with global `dart`; should use `$FLUTTER analyze --no-pub` per member (absolute wrapper path), `full` → tests per member; add `.fvmrc` workspace test | fixed d0b7558 (members: flutter members/wrapper-only → `$FLUTTER analyze --no-pub`, absolute wrapper, `full` → tests per member; global dart never paired with the wrapper) |
| 2 | major | sync-template.sh:108-115 | settings merge replaces project `hooks` wholesale and re-adds removed allow rules; merge hooks per event keeping project-only commands; dry run prints `diff -u`; test with a project-only hook | fixed bccb666 (three-way vs stamped base: per-event hook merge, project-only kept, `.claude/hooks/` non-local entries template-owned; removed allow rules stay removed; dry run prints `diff -u`) |
| 3 | major | android-ui.sh:105-108 | failed `uiautomator dump` → stale `/sdcard/ui.xml` read; `rm -f` before dump, fail unless output has "dumped to"; fake adb failure case | fixed 93b7baa |
| 4 | major | android-ui.sh, android-emu.sh | Git Bash rewrites `/sdcard`, `/data` for adb.exe; `export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'` | fixed ce55861 (grep case: real Git Bash not available on Linux) |
| 5 | major | android-emu.sh:22-49 | phone attached + no ADB_SERIAL → "more than one device"; start with `-port`, set `ADB_SERIAL=emulator-<port>`, `kill -0 $!` in poll loop | fixed fc95eaa (`-port` free even port, `ADB_SERIAL=emulator-<port>`, `kill -0` fail-fast; `wait-for-device`/`timeout` dropped; down/status target emulators only) |
| 6 | minor | usage-report.py:118,129 | `mid`/tool id `None` dedups every later id-less line; dedup only when id set | fixed 358ed7c |
| 7 | minor | usage-report.py:128 | first line per id wins; verify whether early lines carry partial `output_tokens`, else keep max | rebutted: in the 40 newest real `~/.claude/projects/*/*.jsonl`, 8,904 ids repeat across lines and all carry identical `usage` (0 differ) — first line wins is correct |
| 8 | minor | usage-report.py:70 | validate `--since/--until` with `date.fromisoformat`; say UTC | fixed 775e920 |
| 9 | minor | usage-report.py:61 | `media-[^-]+-` fails for user names with `.`/`-`; document or `--alias` | fixed 3e4c53b (current user's mangled name stripped first; other users' dotted names documented in `project_key`) |
| 10 | minor | delegate-guard.sh:40 | plugin types (`x:y`) / name≠filename never found → false warn/deny in strict; skip `:` types, read frontmatter only | fixed 856d1a5 (`x:y` → silent; lookup by frontmatter `name:`; `model:` read from frontmatter only) |
| 11 | minor | delegate-guard.sh:33,43 | `TYPE` unescaped in JSON (trailing `\`); strip to `[A-Za-z0-9:_-]` | fixed ef6260f (stripped to `[A-Za-z0-9:_-]`) |
| 12 | minor | sync-template.sh:83,90,156 | quoted non-ASCII paths (`core.quotePath`); writes through symlinks outside project; use `-z`, skip symlinked paths | fixed cc86773 |
| 13 | minor | sync-template.sh:36,127,160 | relative TPL resolved after `cd`; `open()` w/o encoding; sync-codex failure ignored before stamp | fixed 3ae4ba4 (TPL resolved before `cd`; `encoding="utf-8"`; sync-codex failure → exit 1, no stamp) |

## T15 re-review (code-reviewer, opus, `74a40ac..068b4a6`): verdict "request changes" — fix round 1 of 2
Findings 1, 3–13 judged resolved, 2 partial, rebuttal 7 accepted. New:
| # | Sev | Finding | Status |
|---|---|---|---|
| A | major | real `{matcher, hooks}` groups compared whole: a project edit to a template group dropped both the template hook and the project's local one | fixed 6fcbc6c (merge per command inside each matcher; dict-shaped test) |
| B | major | allow rules the template removed were kept forever | fixed 6fcbc6c (three-way drop; test) |
| C | minor | `"${arr[@]}"` on empty arrays under `set -u` aborts on bash < 4.4 (macOS 3.2) | fixed 40bb166 (`${a[@]+"${a[@]}"}`; no bash 3.2 here to run it) |
| D | nit | exported `CDPATH` makes `cd` print → bad TPL | fixed 40bb166 |
| E | nit | `status` with only a phone printed the phone's boot state | fixed dd0c1da (test) |
Decision: a project's change to a template hook's own fields (e.g. `timeout`) is overwritten by the template's version — the template owns its hooks; changes belong in `.claude/hooks/local/`.

## Risks & open questions
- **Release branch (owner decision):** `main` is 12 commits behind `develop`. T4/T5 default `--ref`/`TEMPLATE_REF` to whichever branch the owner names; recommend merging `develop` → `main` after T15 and syncing from `main`.
- **T3/T6/T8 depend on documented behaviour** (rules auto-loading, compaction/model settings, subagent field in hook input). Each task records the doc URL and has a stated fallback; no undocumented keys.
- **T3 finding (rules loading):** https://code.claude.com/docs/en/memory — "Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`", discovered recursively. So `local-*.md` needs no `@` index line; CLAUDE.md only gets a pointer sentence.
- **T6 finding (context cap):** https://code.claude.com/docs/en/model-config — settings key `autoCompactWindow` (token count ≥100000; "Claude Code caps it at the model's context window", so 300000 is harmless on 200K models). Native-1M models otherwise compact "at about 967K tokens". Chosen over `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (env var overrides `/autocompact` and the setting, so a project could not adjust) and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (percentage of the window, can only lower; default % undocumented). `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` (200K hold) not set: too aggressive for long plan runs — owner can add it per project.
- **T8 finding (subagent marker):** https://code.claude.com/docs/en/hooks — hook input carries `agent_id`/`agent_type` only when the hook fires inside a subagent; subagent tool is `Agent`, its `tool_input` has `subagent_type` and optional `model`. So the browser reminder is main-thread only. Explicit `model:` in an agent file (incl. `inherit`) counts as a deliberate choice: silent.
- **T4 merges settings.json with python3**; on machines without it, the sync prints a diff and stops for that file.
- **T10 live smoke loads the machine** (emulator + NVMe); optional, needs the owner's go-ahead at that step.
- **Disk mounted at three paths** (`/media/abdellah/disque-D`, `/run/media/…`, `/mnt/disque-d`): Claude history and memory split per path. Owner fix (fstab), not template code; T14 merges the variants when reporting.
- Codex still gets only PostToolUse/Stop hooks; T5/T8 are Claude-only.
- **T14 amendment — accepted by the owner 2026-11-25 (±10%):** the audit's $4,170 method is not recorded anywhere (prices used, Codex rollouts included or not). The script prices from the claude-api skill docs (Opus 5.5 $4/$20, cache read $0.20, 1h write $8, 5m write $5) and gets $3,945.54. Proposal: Done-when (1) becomes "within ±10% of the audit, with the documented price table" (the other audit figures match exactly), or the owner supplies the audit's price assumptions.
- Cost figures are list-price estimates, not the bill; re-measure with T14 two weeks after the rollout plan.

/goal every task in task_plan.md is checked off per its own "Done when", and scripts/test-hooks.sh plus bash -n on all hooks and scripts pass

---

## Archived 2026-11-25 — roll out session handoff to the 5 projects

**Objective:** bring the session-handoff change (template ae522c7, merged in 460abcb) into the 5 projects without losing their own hook customisations.

**In scope:** per project, on `chore/session-handoff` from `develop`: `.claude/hooks/session-guard.sh` (threshold 150k, handoff message, wrapper), `.claude/rules/reporting.md` (Handoff prompt section + Context management line), `.claude/rules/workflow.md` (advisor bullet, 150k line), README hooks paragraph if present, `.gitignore` `docs/handoff.md`, `scripts/test-hooks.sh` cases.
**Out of scope:** pushing (needs the user's yes); any other template change; whole-file overwrites.

**Approach:** hand-merge each hunk of ae522c7 into each project, keeping project edits (DoWee and StoreCore customised their hooks). Projects in WSL are edited via `wsl.exe -d Ubuntu`.

## Tasks

- [x] **T0 — Verify the context-size estimate against the hooks docs.**
  Done when: the result and its source are recorded under Risks below; no code change needed (none was).
- [x] **T1 — portfolio** (`D:\abdellah\portfolio`).
- [x] **T2 — DoWee** (`D:\abdellah\DoWee`, customised hooks).
- [x] **T3 — SghiraBrand** (WSL `~/SghiraBrand`).
- [x] **T4 — StoreCoreTemplate** (WSL `~/StoreCoreTemplate`, customised hooks).
- [x] **T5 — AllaghenBrand** (WSL `~/AllaghenBrand`).
  Done when (each of T1–T5): (1) `bash scripts/test-hooks.sh` all green, including the 150k/handoff cases; (2) `bash -n` on all hooks (part of the suite); (3) only the in-scope files above changed, project customisations still present in the diff context; branch merged into `develop`, not pushed.

## Verification log
| Suite | Commit | Result |
|---|---|---|
| template scripts/test-hooks.sh | 1605988 | 51 passed, 0 failed |
| portfolio scripts/test-hooks.sh | 37aba19 | 53 passed, 0 failed |
| DoWee scripts/test-hooks.sh | 3d934b6d | 58 passed, 0 failed |
| SghiraBrand scripts/test-hooks.sh | f86bc34 | 57 passed, 0 failed |
| StoreCoreTemplate scripts/test-hooks.sh | 34de5cf | 57 passed, 0 failed |
| AllaghenBrand scripts/test-hooks.sh | ee4e4f4 | 62 passed, 0 failed |

## Risks & open questions
- **Context-size estimate — verified 2026-11-25.** Per the official hooks reference (https://code.claude.com/docs/en/hooks), the `UserPromptSubmit` input is `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `prompt` (+ `session_title`), with no token or context field. `context_tokens` is documented only on `SessionStart` (resume/fork) and `PreModelSwitch`/`PostModelSwitch`, so it can't serve a per-prompt check. Rich `context_window` fields exist only in the statusLine input (https://code.claude.com/docs/en/statusline). So session-guard keeps parsing the transcript's last `usage` (input + cache_creation + cache_read). Known gaps: the docs say the transcript "may lag" the live conversation, and the docs' `context_tokens` also counts the last response's output tokens, so our figure runs slightly low. That's fine for a warning threshold.
- Codex does not get the UserPromptSubmit/PreToolUse hooks.
- DoWee and StoreCore customised their hooks, so they need a manual merge.

/goal every task in task_plan.md is checked off per its own "Done when", and scripts/test-hooks.sh passes in the template and all 5 projects

---

## Archived 2026-11-25 — usage optimisation (T1–T11, all done)


**Objective:** cut token usage and wasted time in projects built from this template while keeping or improving result quality.

**Evidence:** session-log audits of DoWee, portfolio, StoreCoreTemplate, SghiraBrand, AllaghenBrand (2026-11-23). Main-thread cache reads in very long multi-task sessions are 65–87% of cost; hooks silently failed on relative paths (~490 times); 70–90% of WordPress gate blocks were Docker/wp-env being down; plan files grew to 120–535 KB; nearly all subagents ran on Opus; most skills never triggered.

**In scope:** `.claude/hooks/`, `.claude/settings.json`, `.codex/config.toml`, `.claude/rules/`, `.claude/skills/` (template's own), `.mcp.json`, `.gitattributes`, README/CATALOG sections they touch, `.agents/skills/` (generated).
**Out of scope:** rolling changes into the 5 projects (separate follow-up); vendored plugin content (superpowers, impeccable) beyond file modes; Codex-side equivalents of new Claude-only hooks.

**Approach:** fix the guarantees first (hooks that silently don't run), then the biggest cost driver (session length) with a cheap warning hook plus a hard rule, then rule edits that steer subagents and reviews. Hooks stay dependency-free bash (no jq/python required — neither is guaranteed on Windows).

## Tasks

- [x] **T1 — Hooks run from any cwd; line endings and exec bits fixed.**
  Hook commands use `"$CLAUDE_PROJECT_DIR"`; each script `cd`s to the project root; `.gitattributes` forces LF on `*.sh`; exec bit on all hook scripts incl. vendored superpowers `hooks/`.
  Done when: (1) `scripts/test-hooks.sh` runs each hook from a subdirectory and gets no "No such file", secret check still blocks a planted fake key; (2) `bash -n` passes on all hooks; (3) no files changed outside hooks/settings/.codex/.gitattributes/scripts.

- [x] **T2 — done-gate is honest and cheap.**
  Skips when the working tree is unchanged since its last pass; reports "NOT RUN" (no block) when Docker/wp-env/env is down; detects npm, composer, Flutter/Dart; `DONE_GATE_MODE=manual` turns it off for localhost-first projects (owner runs gates by hand). Env-down needs log text + no code-error markers + a failing environment probe.
  Done when: (1) `scripts/test-hooks.sh` cases pass: unchanged tree → skip, env-down output → exit 0 + NOT RUN, real lint failure → exit 2, manual mode → exit 0; (2) bash -n; (3) fence: done-gate.sh, test script, workflow.md DoD line, README hooks section.

- [x] **T3 — Session-boundary warning (UserPromptSubmit hook).**
  Warns Claude (which tells the user) when the git branch changed since the session's first prompt or the last context passed `CONTEXT_WARN_TOKENS` (default 250000); once per crossing. delivery.md step 6 + reporting.md make "new task = new session" a hard rule.
  Done when: (1) test cases: branch change → warning text, small context → silent, big context → warning once; (2) bash -n; (3) fence: new hook, settings.json, delivery.md, reporting.md, test script, README.

- [x] **T4 — task_plan.md stays small.**
  Rule: archive finished tasks to `docs/plan-archive.md` when the plan passes ~300 lines; T3's hook also warns when task_plan.md exceeds 300 lines / 40 KB.
  Done when: (1) test case: 400-line plan → warning; (2) suite above green; (3) fence: workflow.md, T3 hook.

- [x] **T5 — Subagent model routing.** Rule: search/build/mechanical/browser-check subagents get an explicit cheaper model; reviews and architecture stay on the session model; build agents get scoped briefs.
  Done when: rule present in workflow.md Context discipline; no other files changed.

- [x] **T6 — Screenshots stay out of the main thread.** Rule: visual checks run in a subagent that returns text; never re-read the same image.
  Done when: rule present in workflow.md; fence: workflow.md.

- [x] **T7 — One review per change.** Per-task review OR one branch review, never both on the same commits; fix re-review covers only the fix diff, max 2 rounds; security-auditor only when sensitive paths change.
  Done when: workflow.md Adversarial review + delivery.md step 2 + precedence section say this consistently; fence: those two files.

- [x] **T8 — WordPress / WSL support.** Rule for WSL projects (open from WSL, `MSYS_NO_PATHCONV`); WordPress layout in `project-structure`; PHP/PHPUnit section in `testing-patterns`.
  Done when: sections present; sync-codex mirrors them; fence: those skills, workflow.md, .agents/skills.

- [x] **T9 — Cross-repo warning (PreToolUse on Bash).** Non-blocking warning when a command `cd`s or `git -C`s outside the project root.
  Done when: test cases: outside path → warning, inside path → silent; fence: new hook, settings.json, test script.

- [x] **T10 — Trim defaults, upstream owner rules.** `.mcp.json` ships no servers (examples move to CATALOG); llm-council moves to `skills-optional/`; port proven project rules (two machines one branch, owner-facing labels).
  Done when: `.mcp.json` valid JSON with empty `mcpServers`; workflow.md plan-review fallback still valid; activation path for llm-council documented; fence: those files + README/CATALOG.

- [x] **T11 — Important skills actually trigger.** Rules name the skill at the step it applies; skill descriptions list concrete triggers (paths, file types, commands); testing-patterns placeholder replaced by per-stack sections.
  Done when: descriptions updated; rules reference skills at their steps; sync-codex run; fence: skills, rules, .agents/skills.

## Verification log
| Suite | Commit | Result |
|---|---|---|
| scripts/test-hooks.sh (32 cases incl. bash -n on all hooks) | pre-commit, chore/usage-optimisation | 32 passed, 0 failed |
| session-guard on this session's real transcript | pre-commit | parsed ~191k context correctly |
| code-reviewer pass 1 | pre-commit | request changes: 2 critical (env-down misclass, %b truncation) + 13 more — all fixed except #9 (NOT RUN reaches user only: rule now says so) |
| scripts/test-hooks.sh after fixes (47 cases; tests run the exact settings.json commands) | pre-commit | 47 passed, 0 failed |

## Risks & open questions
- ~~Context size estimate unverified~~ — verified 2026-11-25 (see current plan).
- Codex does not get the new UserPromptSubmit/PreToolUse hooks in this pass.
- Projects that customised hooks (DoWee, StoreCore) need a manual merge in the rollout.

/goal every task in task_plan.md is checked off per its own "Done when", and scripts/test-hooks.sh plus bash -n on all hooks pass
