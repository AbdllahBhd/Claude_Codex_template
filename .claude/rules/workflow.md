# Engineering Workflow Rules

> Loaded via CLAUDE.md. Process discipline: how work gets planned, built, verified,
> and reviewed. These rules apply to Claude, Codex, and any agent reading AGENTS.md.

## Single source of truth (multi-tool)

- Durable knowledge lives ONLY in repo files: `CLAUDE.md`, `.claude/rules/`,
  `.claude/skills/`, `SPEC.md`, `task_plan.md`. Never store project rules or
  lessons in any tool's private memory (Claude user memory, Codex /memories) —
  the other tool and other machines can't see it there.
- When asked to "remember" something project-related, write it into the right
  repo file (see the routing in `/retro`), not into private memory.
- When choosing a memory/indexing tool, prefer one that stores its state as
  files in the repo — that state is then shared across tools and laptops via git.

## Interview → spec (large features)

- For a large or fuzzy feature, interview the user BEFORE planning: ask about
  technical approach, UI/UX, edge cases, and tradeoffs — dig into the hard parts
  they might not have considered, skip the obvious.
- End the interview with the pro-gap check: state what a senior specialist in
  this domain would add that the user did NOT ask for — delivered as decision
  requests (reporting.md's five-part format), never as silently added scope.
- Write the result to `SPEC.md`: self-contained, naming the files and interfaces
  involved, what is OUT of scope, and an end-to-end verification step.
- Recommend executing the spec in a fresh session with clean context.

## Plan first (non-trivial work)

- Any task that touches **more than 2 files**, adds a feature, or changes behavior
  starts with a short written plan BEFORE any code: what changes, which files, how
  it will be verified. Wait for the user's go-ahead on the plan.
- For multi-session work, keep the plan in `task_plan.md` at the repo root and update
  it as steps complete — plans must survive a restart; memory does not.
- Keep `task_plan.md` under ~300 lines: move finished tasks (with their
  evidence) to `docs/plan-archive.md`. It is re-read constantly; audited
  projects grew it to 120–535 KB (`hooks/session-guard.sh` warns).
- Trivial fixes (typo, one-liner, rename) skip planning. When unsure, plan.

## Plan quality (large features & new projects)

- A plan is a professional document, straight to the point: **Objective** (one
  sentence) · **In scope / Out of scope** · **Approach** (the decision and its why,
  not a survey of options) · **Ordered steps, each ending with how that step is
  verified** · **Files/components touched** · **Risks & open questions**.
- For a NEW project (or new module), the plan includes the folder structure —
  follow the recognized best-practice layout for the stack via the
  `project-structure` skill. Clean architecture only where it earns its weight;
  the skill says when.
- **Adversarial plan review before presenting:** for large features and new
  projects, have the draft plan reviewed in a fresh context before showing it —
  ONE subagent prompted as a critical plan reviewer (gaps, wrong assumptions,
  missing verification — not style), or an advisor call when the advisor is
  on. The 11-agent `llm-council` (opt-in, `skills-optional/`) only when the
  user asks to council it. The review also checks every task's "Done when" for the two failure
  modes: too weak (satisfiable without the real work) and wrong/too strict
  (tests the wrong thing, fences out files the task must touch). Address the
  findings, then present the plan noting it was reviewed and what changed.
  Present it only when it would pass a senior engineer's bar.

## Per-task goals (acceptance criteria in the plan)

- Every task in `task_plan.md` carries its own `Done when:` with three clauses,
  all checkable from files or command output:
  1. **Proof of the new behavior** — named test/command + expected result.
  2. **Nothing broken** — the project's standing gates (analyzer, suite).
  3. **Scope fence** — "no files changed outside <paths>".
- A task may be marked `[x]` ONLY when its Done-when evidence was produced and
  shown. A checked box means "evidence existed", never "felt finished".
- If execution reveals a Done-when is wrong (e.g. the fence excludes a file the
  task genuinely needs), propose an amendment to the plan file and say why —
  never silently reinterpret the goal. Plan edits are visible in git.
- **Every presented plan ends with a ready-to-paste `/goal` line**, e.g.:
  `/goal every task in task_plan.md is checked off per its own "Done when", and the project's quality gates pass`
  The user sets it; the AI never invokes /goal itself (the worker must not
  appoint its own judge).

## Precedence with plugins (superpowers and others)

Plugin skills supply TECHNIQUE; these rules define the REQUIRED ARTIFACTS and
OUTCOMES. On any conflict, this file and the other `.claude/rules/` win:

- A plan produced with superpowers `writing-plans` (or any other method) must
  still land in `task_plan.md` in the Plan-quality structure above, with
  per-task `Done when:` clauses and the closing `/goal` line. Superpowers
  shapes the thinking; our format is the deliverable.
- `brainstorming` serves the Interview → spec step for large/fuzzy features.
  The trivial-fix exemption in "Plan first" OVERRIDES its "use before any
  creative work" trigger — no brainstorming ceremony for typo-sized changes.
- Branch integration follows `delivery.md` (gates → review → merge to
  `develop` → propose next task), not `finishing-a-development-branch`'s own
  menu of options.
- **Design generators** (the vendored `impeccable`, or ui-ux-pro-max etc.)
  propose the visual language ONLY in projects without their own design system.
  Where a design system exists, its tokens/components win and generators serve
  in review/critique mode only (see `ui-quality` rule zero). Never two
  generator doctrines in one project.

## Test-driven by default

- Before writing or fixing tests, load the `testing-patterns` skill (stack
  conventions); for new behavior use superpowers `test-driven-development`.
- For new behavior: write the failing test FIRST, see it fail, implement, see it pass.
- For bug fixes: write a test that reproduces the bug before touching the fix.
- Never write tests after the fact that merely assert what the code already does.
- A red/green signal beats re-reading your own code. Iterate against tests, not vibes.

## Definition of done (enforced by hooks/done-gate.sh)

A task is done ONLY when all of these are true — never claim done otherwise:

1. Lint passes with no new warnings.
2. Typecheck passes (if the project has one).
3. The tests matching the change's blast radius are green (see Verification
   economy below — the FULL suite is required at the delivery merge, not at
   every step).
4. The diff has been self-reviewed: no debug logs, no dead code, no unrelated changes.

If a gate cannot run (e.g. no test script yet), say so explicitly instead of
implying it passed.

The Stop gate skips when nothing changed since its last pass, and reports
"NOT RUN" (without blocking) when the environment is confirmed down (Docker,
wp-env, UNC path). That notice reaches the user, not you: so never write
"gates pass" from the Stop hook's silence — state which gate commands YOU ran
and their output, and treat a NOT RUN as not passed.
Stack detection: npm, composer, Flutter/Dart; any other stack sets
`DONE_GATE_CMD`. Localhost-first projects (owner checks before any gate) set
`DONE_GATE_MODE=manual` in `.claude/settings.json` `env`.

Choose the cheapest evidence that directly proves each claim (focused test,
analyzer output, filtered log, DB assertion); screenshots prove rendering and
layout only. Keep local checks, deploy output and real-device/account
acceptance distinct in reports.

## Verification economy (scale the checks to the change)

Running everything for everything wastes the user's time. Decide the blast
radius FIRST, verify accordingly, and say which level you chose and why:

- **Cosmetic/visual only** (colors, spacing, copy, assets, style tokens):
  lint/analyzer + LOOK at the rendered result. No test suite.
- **Localized logic** (one module/feature): targeted tests for the touched
  files/module only.
- **Shared core** (contracts, data models, auth, utilities many features use):
  the full relevant suite.
- When unsure, err ONE level up — not all the way to everything.

Avoid re-running what cannot have changed: record in `task_plan.md` which
suites ran green at which commit; a suite needs re-running only when later
diffs touch code it covers. The merge gate is scoped by `scripts/gate-scope.sh`
(cosmetic / targeted / full, driven by the project's `.claude/gate-core-paths`;
no file = full, the safe default). The FULL suite is mandatory before a
release and when the user asks. The Stop hook enforces the floor (lint +
typecheck); `DONE_GATE_FULL=1` forces the full suite on a stop.
Code that is UI-in-code (Dart widgets, JSX/TSX) cannot be classified by file
type: there the scope comes from the core-paths file plus targeted tests for
the touched feature.

## Primary sources for external facts

- When correctness depends on a fact outside this repo — a library's API, a
  framework behavior, a spec/standard, a service's limits — consult the PRIMARY
  source: official docs for the installed version, the changelog, or the
  dependency's actual code in node_modules/vendor. Not blog posts, not tutorial
  summaries, not memory of an older version.
- Name the source used in the briefing ("per expo-camera 17.x docs: ...").
  An external fact stated without a source is a guess wearing a suit.
- Memory of an API is a hypothesis, not a fact — cheap to verify, expensive
  to be wrong about.

## Context discipline

- Do not read whole directories "to get familiar" — delegate broad exploration to a
  subagent (Explore) and keep only the conclusions in the main conversation.
- Read only the parts of files relevant to the task when files are large.
- Long research, log-dumping, or multi-file audits belong in subagents whose reports
  come back small.
- **One task = one session.** A new task, branch or feature starts a fresh
  session (or `/clear`) carrying over only `task_plan.md`. Every message
  re-reads the whole context: in audited projects, 400k–970k-token sessions
  spanning up to 20 branches were 65–87% of all cost. `hooks/session-guard.sh`
  warns on a branch change and past 250k tokens — relay it, don't ignore it.
- **Name the model on every subagent call.** Search, build, mechanical edits
  and browser checks: `sonnet` (or `haiku` for pure lookups). Reviews,
  architecture and hard debugging: the session model. An omitted model
  inherits the most expensive one.
- **Brief build subagents tightly:** the files to touch, the interfaces to
  keep, what done looks like, and a "read only what you need" line. Open-ended
  build agents ran to 15–64M tokens each in audited projects.
- **Screenshots stay out of the main thread.** Visual checks run in a
  subagent that returns text ("button clipped at 375px"); never re-read the
  same image. Each image is re-paid on every later message.
- Pipe long command output through `tail`/`grep`; never dump full test or
  build logs into the conversation.
- **Stay in this project.** Work in a sibling repo belongs in that repo's own
  session (`hooks/repo-guard.sh` warns when a command leaves the project).

## Skills at their step (load them — they do not auto-load reliably)

- Writing/fixing tests → `testing-patterns` · new behavior → `test-driven-development`
- Any bug after one failed fix → `systematic-debugging`
- Any screen/component/layout → `ui-quality` · any animation → `motion`
- API endpoint → `api-conventions` · new project/plugin/module → `project-structure`
- About to claim done → `verification-before-completion`
(`hooks/skill-nudge.sh` reminds once per session when test/UI files are edited.)

## Windows / WSL projects

- A project that lives in WSL is opened FROM WSL (Claude Code running in
  Linux), never through `\\wsl.localhost\...` from Windows: UNC paths break
  npm/CMD and gates, and `wsl.exe` wrappers churn retries.
- In Git Bash, prefix commands that take Linux paths with
  `MSYS_NO_PATHCONV=1` (e.g. docker/wp-env paths).
- Shell scripts keep LF endings (`.gitattributes` enforces it).

## Adversarial review

- Every change gets exactly ONE independent code review with fresh context
  (`code-reviewer` agent) — the author must not be the only reviewer, and the
  same commits are never code-reviewed twice:
  - Plan executed task-by-task with per-task reviews (superpowers
    `subagent-driven-development` — its spec+quality pair per task counts as
    that task's one review)? Then the delivery review covers only the commits
    no task review saw — usually just the integration.
  - Otherwise one review of the branch diff at delivery (delivery.md step 2).
  - A fix is re-checked by reviewing ONLY the fix diff; max 2 fix rounds,
    then escalate to the user instead of looping.
- The `security-auditor` agent is a separate, additional pass: run it before a
  release and whenever the diff touches auth, payments, input handling, file
  access or secrets — not on every branch.
- Treat review findings as work items: fix or explicitly rebut each one; never
  silently ignore them.

## When things go wrong

- Two failed attempts at the same fix = stop, load superpowers
  `systematic-debugging`, re-read the actual error, and question the diagnosis
  instead of trying a third variation of the same guess.
- Never "fix" a failing test by weakening the assertion unless the test is provably
  wrong — say so and explain why.
- Never disable a linter rule inline to make a warning disappear without flagging it.
