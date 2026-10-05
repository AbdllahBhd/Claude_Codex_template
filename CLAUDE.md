# Project Memory (CLAUDE.md)

> This file is automatically loaded by Claude Code at the start of every session.
> Keep it short and high-signal: Claude reads it every time, so every line costs context.
> Replace the placeholders below with your real project info.

## Project Overview

- **Name:** <your-project-name>
- **What it does:** <one or two sentences describing the project>
- **Tech stack:** <e.g. TypeScript, React, Node.js, PostgreSQL>
- **Package manager:** <npm | pnpm | yarn | bun>

## Essential Commands

```bash
# Install dependencies
npm install

# Run the dev server
npm run dev

# Run tests
npm test

# Lint and format
npm run lint
```

## Architecture Notes

- <Where the entry point is, e.g. `src/index.ts`>
- <Where business logic lives, e.g. `src/services/`>
- <Where tests live, e.g. `tests/` mirrors `src/`>
- <Anything non-obvious a new developer would need to know>

## Rules

Detailed conventions live in `.claude/rules/` and are loaded automatically:

- @.claude/rules/code-style.md
- @.claude/rules/pr.md
- @.claude/rules/workflow.md

API conventions load on demand as a skill (`.claude/skills/api-conventions/`) —
only sessions that touch an API pay for them.

## Session & Context Hygiene

- When compacting this conversation, always preserve the full list of modified
  files, the current task plan status, and any test commands used.
- Unrelated new task → suggest starting a fresh session instead of continuing here.

## Hard Constraints (always follow)

- Never commit secrets, API keys, or `.env` files.
- Never push directly to `main` — always work on a feature branch.
- Run the test suite before claiming a task is complete.
- Prefer editing existing files over creating new ones.
