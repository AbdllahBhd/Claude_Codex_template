# Local rules — example (copy to `local-<topic>.md`)

> Project-owned rules live in `.claude/rules/local-*.md`. Claude Code loads
> every `.md` in `.claude/rules/` at launch; Codex reads them via AGENTS.md.
> Template sync never overwrites `local-*.md`, so put project deviations here
> instead of editing the template's rule files.

- <One rule per line, only what differs from the template rules.>
- <Scope a file to paths with YAML frontmatter, e.g. `paths: ["src/api/**"]`.>
