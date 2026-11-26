# Plan — release the T11 follow-ups to `main`

**Objective:** `main` carries the T11 follow-ups (eedd5f1) and the T12 record, so `sync-template.sh --ref` and `TEMPLATE_REF`, which default to `main`, deliver them to projects.

**Evidence:** `main` = `origin/main` = 918b981, an ancestor of `develop` = `origin/develop` = 8d432c1. The finished v3 rollout plan (T0–T12) is archived in `docs/plan-archive.md` under `## 2026-11-26 — template v3 rollout (T0–T12)`.

**In scope:** `task_plan.md`, `docs/plan-archive.md`, merging `chore/release-t11` into `develop`, and fast-forwarding `main`.
**Out of scope:** project re-syncs (each one gets its own session in its project), and any code change.

**Approach:** archive, gate (the full suite plus a security audit, per workflow.md: before a release), then fast-forward `main` to `develop`. No merge commit lands on `main`, so `main` and `develop` point to the same commit. Nothing is pushed without the owner's yes.

## Tasks

- [x] **R1 — Archive the v3 rollout plan.**
  Done when: (1) `diff` of `git show develop:task_plan.md` against the archived section shows only the heading line; (2) `wc -l task_plan.md` < 300; (3) no files changed outside `task_plan.md`, `docs/plan-archive.md`.
- [x] **R2 — Release gate.**
  Done when: (1) `bash scripts/test-hooks.sh 2>&1 | tail -1` prints `passed: 193  failed: 0`; (2) the `security-auditor` pass over `git diff 918b981..develop -- .claude/hooks scripts` has no unaddressed Critical/High finding; (3) no files changed outside R1's paths.
- [x] **R3 — Merge to `develop`.** `docs: archive the template v3 rollout plan`, merged `--no-ff`.
  Done when: (1) `git log develop -1` is that merge; (2) suite still `failed: 0` on `develop`; (3) the merge diff touches only R1's paths.
- [x] **R4 — Release `main` (owner's yes required).** Fast-forward `main` to `develop`, then push both.
  Done when: (1) `git ls-remote origin refs/heads/main` and `refs/heads/develop` equal local `main` and `develop`; (2) `main` = `develop`; (3) nothing else pushed.

## Follow-up — harden sync-template exclude/keep (`fix/sync-keep-exclude`)

**Objective:** fix audit findings 1, 2, 4 and 5 before any project re-syncs onto `.claude/template-exclude` / `.claude/template-keep`. Finding 3 is an owner decision and is out of scope.

- [ ] **S1 — Keep, exclude and done-gate hardening.** `sync-template.sh` keeps a keep-listed file only when it matches no template version. It names every excluded or kept path, and warns when a path is `.claude/settings.json` or under `.claude/hooks/` (not `local/`). `done-gate.sh` rejects an `.fvmrc` pin with `/` or `..`, and reports NOT RUN when `mktemp -d` fails.
  Done when: (1) the new `scripts/test-hooks.sh` cases (keep on an old version is updated, keep on a modified file is kept, paths are listed, the hooks warning, bad pin = NOT RUN) went red → green; (2) `bash scripts/test-hooks.sh 2>&1 | tail -1` prints `failed: 0`; (3) no files changed outside `scripts/sync-template.sh`, `scripts/test-hooks.sh`, `.claude/hooks/done-gate.sh`, `task_plan.md`.

## Carried forward (from the v3 rollout)

- **Cost re-measure:** on or after 2026-12-09, run `scripts/usage-report.py` and compare against the 2026-11-25 audit.
- **bash 3.2:** the fix in 40bb166 has never run on a real bash 3.2. Owner question: does any machine run macOS? If none does, it is N/A.
- **T10 live emulator smoke** was skipped. Its first real run will be in DoWee or GRdLines.
- **Other machine:** `git pull` each project. In the InstaReels main checkout, local `develop` must move ad38e78 → 13e2f43.
- **Project follow-ups, once `main` has T11.** Each runs in its own project session, after a re-sync:
  - InstaReels: use `.claude/template-exclude` + `.claude/template-keep` (its 7 adapted files) instead of manual exclusion.
  - GRdLines: drop the pure-Dart dispatch from its wrapper.
  - DoWee: drop its interim `DONE_GATE_MODE=manual`.
- **R2 security audit, Low findings (code changes, out of this release's scope; one template session):**
  1. `sync-template.sh`: exclude/keep entries only print counts. A broad entry (`.claude/`, `.claude/hooks/*`, or `.claude/settings.json`) silently freezes safety-hook updates. Print each path and warn on hooks/settings.
  2. `sync-template.sh:119`: the keep check runs before `known_version` (confirmed), so a listed file still equal to an old template version is kept forever. Apply keep only to truly modified files.
  3. `done-gate.sh:172-188`: editing `.fvmrc` or `scripts/flutter.sh --which` turns the Flutter BLOCK into NOT RUN. Consider blocking when those files changed and `SDK_NOTE` is set.
  4. Info: reject an `.fvmrc` `PIN` that contains `/` or `..`. 5. Info (existing code): `done-gate.sh:80`'s `mktemp -d` fallback to a predictable `/tmp` path.

## Verification log

| Task | Command | Result | Commit |
|---|---|---|---|
| R1 | `diff <(git show develop:task_plan.md) <archived section>`; `wc -l task_plan.md` | only line 1 differs (heading); 46 lines | 8d432c1 |
| R2 | `bash scripts/test-hooks.sh 2>&1 \| tail -1` | `passed: 193  failed: 0` | 8d432c1 |
| R2 | `security-auditor` (opus) on `git diff 918b981..develop -- .claude/hooks scripts` | no Critical/High; 3 Low + 2 Info, carried forward | 8d432c1 |
| R3 | `git log develop -1 --oneline` | `05fe27f Merge branch 'chore/release-t11' into develop` | 05fe27f |
| R4 | `git ls-remote origin refs/heads/main refs/heads/develop` | both 05fe27f | 05fe27f |

/goal every task in task_plan.md is checked off per its own "Done when", and scripts/test-hooks.sh reports failed: 0
