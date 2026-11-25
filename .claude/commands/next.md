---
description: Pick the ONE next task, write docs/handoff.md, and send the user to a fresh session — never starts the work
allowed-tools: Read, Write, Grep, Glob, Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git switch -c:*)
---

# /next — choose the next task, hand it to a fresh session

Use after pulling changes or finishing a task ("what's next?"). This command
only PREPARES the next task: a fresh session does it. Hint (optional): $ARGUMENTS

Never start the work here. Carrying a finished task's context into the next one
was the single biggest cost in audited projects (delivery.md step 6).

## Steps

1. **Read the state** — only these, nothing else:
   - `task_plan.md` (first unchecked task, its `Done when:`, Risks);
   - `git log -5 --oneline`;
   - `git status --short`, the current branch, and whether `develop` exists.
   If `task_plan.md` is missing or fully checked, say so and propose the next
   task from the roadmap or open issues instead.
2. **Pick ONE task** and present it in the reporting.md decision format, compact:
   What · Why (one line) · The decision (A: start it (recommended) · B: other
   task · C: stop) · Relation · Cost. Uncommitted changes or an unmerged branch
   come first: name them as the blocker instead of a new task. A task already
   half-done in the tree is proposed as "finish task N", not as a new task.
3. **Write `docs/handoff.md`** (git-ignored, local state — overwrite it) per
   reporting.md "Handoff prompt": Task · Repo + branch (the branch to create,
   `<type>/<short-description>` per pr.md, from `develop`) · Done (last commits)
   · Next steps with how each is verified · Test/verify commands · Constraints
   · Do NOT redo. Concrete names only, readable by a session that saw nothing.
   Show it in a code block.
4. **Branch only on the user's yes:** after they pick, create the branch from
   `develop` (`git switch -c <branch> develop`; `origin/develop` when there is
   no local `develop`). No yes → no branch.
5. **Stop.** Tell the user to start a fresh session (or `/clear`) and paste
   `docs/handoff.md` as the first message. Do not read code, edit files other
   than the handoff, or run tests for the next task. Never start the work.
