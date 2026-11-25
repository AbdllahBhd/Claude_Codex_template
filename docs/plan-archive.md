# Plan archive

Finished plans moved out of `task_plan.md` (workflow.md, Plan first). Newest first.

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
