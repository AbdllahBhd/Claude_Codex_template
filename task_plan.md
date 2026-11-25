# Plan — roll out session handoff to the 5 projects

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
