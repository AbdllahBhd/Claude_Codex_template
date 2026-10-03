# Claude Code Project Structure Template

A **copy-paste-ready** configuration template for [Claude Code](https://claude.com/claude-code).
Drop these files into any project and Claude instantly knows your conventions, commands,
rules, and workflows.

```
your-project/
├── CATALOG.md                     ← Menu of 40 verified ecosystem tools + one-line installs
├── AGENTS.md                      ← Pointer for Codex/Cursor/Gemini → reads CLAUDE.md
├── CLAUDE.md                      ← Project memory (committed, shared with the team)
├── CLAUDE.local.md                ← YOUR personal memory (git-ignored)
├── .mcp.json                      ← Project MCP servers (external tools for Claude)
├── .gitignore                     ← Keeps personal/secret files out of git
└── .claude/
    ├── settings.json              ← Team settings: permissions + hooks (committed)
    ├── settings.local.json        ← YOUR personal settings (git-ignored)
    ├── rules/                     ← Convention files loaded into every session
    │   ├── code-style.md          ← Naming, formatting, error handling
    │   ├── api-conventions.md     ← Endpoint design, error envelopes, validation
    │   ├── pr.md                  ← Branching, commits, PR workflow
    │   └── workflow.md            ← Plan-first, TDD, review discipline, done criteria
    ├── commands/                  ← Custom slash commands (you type /deploy, /retro)
    │   ├── deploy.md              ← /deploy — guarded deployment checklist
    │   ├── install.md             ← /install — install tools from CATALOG.md
    │   └── retro.md               ← /retro — write session lessons into the rules
    ├── skills/                    ← Skills Claude loads on demand when relevant
    │   └── testing-patterns/
    │       └── SKILL.md           ← How tests are written in this project
    ├── agents/                    ← Specialized subagents Claude can delegate to
    │   ├── code-reviewer.md       ← Senior reviewer (read-only)
    │   └── security-auditor.md    ← Defensive security audits (read-only)
    └── hooks/
        ├── validate-code.sh       ← After every edit: blocks secrets, flags debug code
        └── done-gate.sh           ← When Claude says "done": lint+typecheck+tests must pass
```

---

## 🚀 How to use: NEW project

1. **Copy everything** from this template into your new project root:
   `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `CATALOG.md`, `.mcp.json`, `.gitignore`,
   and the whole `.claude/` folder. (If the template lives in a git repo: clone it,
   then delete the inner `.git` folder.)
2. **Fill in CLAUDE.md** — the fast way: open Claude Code in the project and say
   *"Read the codebase and fill in CLAUDE.md with the real stack, commands, and
   architecture"* (or run `/init` and merge the result). For a brand-new empty
   project, fill in the placeholders by hand as the project takes shape.
3. **Fill in `CLAUDE.local.md`** with your machine-specific stuff (ports, DB URL).
4. **Prune where it pays** (see the cost table below): rewrite or delete `rules/`
   files that don't match this stack; delete unused servers from `.mcp.json`;
   put your real deploy commands in `.claude/commands/deploy.md`. Leave irrelevant
   skills/agents — they cost almost nothing while dormant.
5. **Install day-one tools from [CATALOG.md](CATALOG.md)** if needed
   (typical: superpowers once per laptop, context7 per project).
6. **Verify:** open Claude Code, type `/install` — if the catalog menu appears,
   everything is loaded.

## 🔄 How to use: EXISTING project (already using Claude or Codex)

Don't blind-copy — you'd overwrite instructions you already refined. Merge instead:

1. **Inventory what's there:** look for existing `CLAUDE.md`, `AGENTS.md`,
   `.claude/` folder, `.cursor/rules/`, `.mcp.json`.
2. **Merge memory files (most important step):**
   - Existing `CLAUDE.md`? Keep it — it contains real, learned knowledge about the
     project, which beats template boilerplate. Add only what it's missing from the
     template (e.g. the `@.claude/rules/...` import lines, a Hard Constraints section).
   - Existing `AGENTS.md` (Codex project)? Two options: (a) keep `AGENTS.md` as the
     master and make `CLAUDE.md` the pointer instead — same trick, reversed — or
     (b) move its content into `CLAUDE.md` and replace `AGENTS.md` with the
     template's pointer version. Pick whichever file has more real content as master.
   - Never end up with two full files — one master + one pointer, always.
3. **Copy the additive folders** — these are safe because they're new files:
   `.claude/rules/`, `commands/`, `skills/`, `agents/`, `hooks/`, and `CATALOG.md`.
   If a folder already exists, copy file-by-file and skip name collisions.
4. **Merge configs carefully (don't overwrite):**
   - Existing `.claude/settings.json`: manually add the template's `deny` rules and
     hook wiring into it, keeping their `allow` list (it reflects real approved usage).
   - Existing `.mcp.json`: add template servers they don't have; never delete theirs.
   - `.gitignore`: append the template's Claude-related lines if missing.
5. **Then prune and verify** exactly like steps 4–6 for a new project.

Easiest path for step 2–4: copy the template into a temp folder next to the project
and tell Claude Code: *"Merge the template in ../template into this project without
losing any existing instructions — existing content wins on conflict."*

## 🤖 Using the same template with Codex / Cursor / Gemini

The knowledge layer is tool-agnostic by design:

- **`AGENTS.md`** (the open standard Codex, Cursor, and Gemini CLI read) is a pointer
  to `CLAUDE.md` — every tool gets the same instructions, maintained in one place.
  Edit `CLAUDE.md` and the `rules/` files only; never write content into the pointer.
- **MCP servers** from CATALOG.md work in all these tools; only registration differs
  (Claude: `.mcp.json` / `claude mcp add` · Codex: `~/.codex/config.toml` · each
  tool's docs have the one-liner).
- **Claude-only parts** (ignored harmlessly by other tools): `.claude/settings.json`
  permissions & hooks, `commands/`, `agents/`, and skill auto-triggering. Port the
  *ideas* per tool if you need them (e.g. Codex prompts live in `~/.codex/prompts`).

---

## 📖 What each piece does (and when it loads)

### `CLAUDE.md` — Project memory *(loads: every session, always)*
The first thing Claude reads. Put your project description, essential commands,
architecture notes, and hard constraints here. The `@.claude/rules/...` lines at the
bottom import the rule files, so they load automatically too.
**Golden rule: keep it short.** Every line is loaded into every conversation — only
include things Claude needs *every time*.

### `CLAUDE.local.md` — Personal memory *(loads: every session, your machine only)*
Same idea, but git-ignored. Local ports, your DB URL, personal preferences. Teammates
each have their own version and never conflict with yours.

### `.mcp.json` — MCP servers *(loads: on startup, after one-time approval)*
Gives Claude external tools (GitHub, databases, browsers, APIs...) via the Model
Context Protocol. Because it's committed, every teammate gets the same tools.
Secrets go in environment variables (`${GITHUB_TOKEN}`), never in this file.

### `.claude/settings.json` — Team settings *(always active)*
Two jobs:
- **Permissions:** pre-approve safe commands (`npm test`, `git diff`...) so Claude
  doesn't ask every time, and hard-deny dangerous ones (`rm -rf`, reading `.env`,
  force-push). `deny` always beats `allow`.
- **Hooks:** wires `hooks/validate-code.sh` to run after every `Edit`/`Write`.

### `.claude/settings.local.json` — Personal settings *(always active, git-ignored)*
Your personal overrides: extra permissions, env vars, model choice. Wins over
`settings.json` on your machine.

### `.claude/rules/*.md` — Conventions *(loaded via CLAUDE.md imports)*
One file per topic. Claude follows these when writing code, designing APIs, and
making commits/PRs. Add more files (e.g. `database.md`, `react.md`) and reference
them from `CLAUDE.md` with `@.claude/rules/your-file.md`.

### `.claude/commands/*.md` — Slash commands *(run when YOU type them)*
Each `.md` file becomes a `/command` named after the file. `$ARGUMENTS` in the file
is replaced by whatever you type after the command:
- `/deploy` → runs the checklist for staging; `/deploy production` → requires confirmation.
- `/retro` → mines the whole session; `/retro testing` → focuses on one topic.
The `allowed-tools` frontmatter limits what the command can do — keep it tight.

### `.claude/skills/<name>/SKILL.md` — Skills *(loaded by Claude when relevant)*
Unlike rules (always loaded), skills load **on demand**: Claude reads only the
`description` up front, and pulls in the full skill when the task matches it. Perfect
for detailed knowledge that would bloat `CLAUDE.md` — testing patterns, migration
guides, domain glossaries. A skill folder can also contain extra reference files and
scripts next to `SKILL.md`.

### `.claude/agents/*.md` — Subagents *(delegated to automatically or on request)*
Specialized workers with their own prompt, own tool list, and **own context window**
(they don't eat your conversation's context). The `description` tells Claude when to
delegate — "use proactively after writing code" makes the code-reviewer run
automatically after big changes. Both bundled agents are read-only by design: they
report, you decide.

### `.claude/hooks/*.sh` — Hooks *(run automatically by the harness)*
Deterministic scripts — not AI — that fire on events. The bundled one runs after
every file edit and:
1. **Blocks** hardcoded secrets (exit code 2 forces Claude to fix it immediately).
2. **Warns** about leftover `console.log` / `print` debug statements.
3. Optionally auto-formats with Prettier (commented out — enable if you use it).
On Windows, hooks run through Git Bash, which ships with Git — nothing extra to install.

---

## 🧠 Mental model: which mechanism do I use?

| I want Claude to...                              | Put it in           |
| ------------------------------------------------ | ------------------- |
| Always know a fact about the project             | `CLAUDE.md`         |
| Always follow a coding convention                | `.claude/rules/`    |
| Know something only on *my* machine              | `CLAUDE.local.md`   |
| Run a repeatable workflow when *I* trigger it    | `.claude/commands/` |
| Apply deep knowledge only when a task needs it   | `.claude/skills/`   |
| Delegate a role to a focused specialist          | `.claude/agents/`   |
| **Guarantee** something happens (not just hope)  | `.claude/hooks/`    |
| Not ask permission for safe commands             | `settings.json` allowlist |
| Use an external tool/service                     | `.mcp.json`         |

Key insight: **memory and rules are suggestions Claude follows; hooks and permission
denies are guarantees the harness enforces.** Use hooks for anything that must never
be skipped.

---

## ✅ Committed vs. git-ignored

| Committed (shared with team)  | Git-ignored (personal)        |
| ----------------------------- | ----------------------------- |
| `CLAUDE.md`                   | `CLAUDE.local.md`             |
| `.mcp.json`                   | `.claude/settings.local.json` |
| `.claude/settings.json`       | `.env` files                  |
| `rules/`, `commands/`, `skills/`, `agents/`, `hooks/` | |

The provided `.gitignore` already handles this split.

---

## 🧰 Adding ecosystem tools — the `/install` command

Don't bundle third-party tools into this template. [CATALOG.md](CATALOG.md) is a verified
menu of 40 popular Claude Code ecosystem tools (plugins, skills, MCP servers, CLIs).
When a project needs a capability, install it then — you get the current version, and
the template stays tiny.

**The only command to remember:**

```
/install               ← shows the menu of all 40 tools
/install context7      ← installs that tool (fetches latest from GitHub)
/install ui-ux         ← partial names work too
```

Claude looks the tool up in CATALOG.md, runs the right install for its type (MCP
server, skill copy, CLI), and verifies it worked. The only exception: plugins
(like superpowers) install via Claude Code's own `/plugin` command, so `/install`
hands you the two lines to paste. You never need to open CATALOG.md manually —
it's the data; `/install` is the interface.

## 🎓 The senior-engineer layer

Three mechanisms turn this from "Claude knows my preferences" into "Claude provably
ships working code and improves every week":

1. **The done-gate** (`hooks/done-gate.sh`, wired to the Stop event): when Claude
   tries to finish a task, the hook runs lint, typecheck, and tests. If anything
   fails, Claude is *blocked from stopping* and must fix it first. "Done" becomes a
   verified fact, not a claim. Disable temporarily with `SKIP_DONE_GATE=1`; adapt
   the project-type detection for non-npm stacks.
2. **The workflow rules** (`rules/workflow.md`): plan-first for non-trivial work,
   test-driven by default, context discipline (delegate exploration to subagents),
   and adversarial review (the code-reviewer agent checks every significant diff,
   the security-auditor before releases). Codex inherits all of this via AGENTS.md.
3. **The learning flywheel** (`/retro`): run it at the end of a work session. It
   mines the conversation for every correction, failure, and stated preference, and
   writes them into the right rule file. Twenty sessions later, your rules contain
   twenty sessions of distilled experience — that's what "senior" actually is.

Suggested habit: `/retro` before you close a session; the built-in `/code-review`
before you merge anything significant; let the done-gate handle the rest automatically.

## ⚡ Command reference: built-in vs. created by this template

Two kinds of slash commands exist, and it matters which is which: **built-ins** ship
with the tool itself (exist in every project, documented by the vendor), while
**template commands** exist only because a `.md` file sits in `.claude/commands/`
of this project. Verified against the official docs on **2026-10-03**:
[Claude Code commands reference](https://code.claude.com/docs/en/slash-commands) ·
[Codex CLI commands reference](https://developers.openai.com/codex/cli/slash-commands.md).

### ✍️ Created by this template (Claude Code only — type the command + Enter)

| Command | What it does | Usage examples |
|---|---|---|
| `/deploy` | Pre-deploy gate (clean tree → lint → tests → build), then your deploy command | `/deploy` → staging · `/deploy production` → asks you to confirm first |
| `/install` | Installs a tool from [CATALOG.md](CATALOG.md) and verifies it | `/install` → show the menu · `/install context7` · partial names OK |
| `/retro` | Mines the session for corrections/lessons and writes them into the rule files | `/retro` at the end of a work session · `/retro testing` → focus on one topic |

These are just files — `deploy.md`, `install.md`, `retro.md` in
`.claude/commands/`. Edit the file to change the behavior; delete it to remove the
command; copy the folder to another project and the commands exist there too.

> **Code review is deliberately NOT a custom command:** Claude Code's built-in
> reviewer (`/review`, also `/code-review` with effort levels low→ultra, `--fix`,
> `--comment`) is stronger at finding real bugs — multi-agent verification, graded
> confidence, PR integration. Use it for correctness. Conventions compliance is
> covered separately: the rules files are always loaded, and the `code-reviewer`
> subagent checks diffs against them (the workflow rule runs it on significant
> changes automatically).

### 🏭 Built into Claude Code (every project, no template needed)

Most useful day to day: `/init` (generate CLAUDE.md from the codebase), `/clear`
(fresh session), `/compact` (summarize to free context), `/cost` (token usage),
`/memory` (edit CLAUDE.md files), `/model`, `/permissions`, `/agents` (manage
subagents), `/mcp`, `/plugin` (marketplaces & plugins), `/sandbox`,
`/pr_comments`, `/doctor`, `/help`. Full list: type `/` in a session, or see the
[official reference](https://code.claude.com/docs/en/slash-commands).

### 🏭 Built into Codex CLI (this template's commands do NOT appear there)

Codex has its own ~50 built-ins; the closest equivalents to this template's
workflow: `/review` (reviews your working tree), `/plan` (plan mode), `/compact`,
`/diff`, `/status` + `/usage` (config & token usage), `/memories`, `/skills`,
`/mcp`. Full list in the
[official reference](https://developers.openai.com/codex/cli/slash-commands.md).

Two Codex commands deserve special care in a project using this template:

- **`/init` generates an AGENTS.md scaffold** — do NOT run it here; it would
  clobber the pointer `AGENTS.md`. The pointer already gives Codex everything.
- **`/import` imports a Claude Code setup** — useful on a fresh machine: it can
  carry your Claude Code configuration over into Codex.

For the template's custom workflows in Codex, ask in plain words instead — e.g.
*"do a retro on this session and update the rule files"* or *"read CATALOG.md and
install context7"*. The knowledge is in shared files, so this works; only the
one-word shortcut is Claude-specific.

## 🛠 Extending the template

- **New rule:** add `.claude/rules/my-topic.md`, reference it from `CLAUDE.md`.
- **New command:** add `.claude/commands/my-command.md` → instantly available as `/my-command`.
- **New skill:** add `.claude/skills/my-skill/SKILL.md` with `name` + `description` frontmatter.
- **New agent:** add `.claude/agents/my-agent.md` with `name`, `description`, `tools` frontmatter.
- **New hook:** add the script to `.claude/hooks/` and wire it in `settings.json` under `hooks`.

Keep everything small and specific. A focused 30-line rule file beats a 300-line
manifesto Claude has to wade through every session.
