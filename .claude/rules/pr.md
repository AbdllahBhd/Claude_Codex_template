# Pull Request & Git Rules

> Loaded via CLAUDE.md. How Claude should handle branches, commits, and pull requests.

## Branching

- Never commit directly to `main` or `master`.
- Branch names: `<type>/<short-description>` — e.g. `feat/user-auth`, `fix/login-redirect`, `chore/update-deps`.

## Commits

- Use Conventional Commits:
  - `feat: add password reset flow`
  - `fix: handle empty cart on checkout`
  - `refactor: extract payment client`
  - `test: cover order cancellation`
  - `docs: update API readme`
  - `chore: bump dependencies`
- Subject line: imperative mood, under 72 characters, no trailing period.
- One logical change per commit. Don't mix a refactor with a feature.
- Never use `--no-verify`, never amend or force-push unless explicitly asked.

- Paths with spaces: quote every path in commands and scripts. Renames use
  anchored patterns (`git mv "old dir/x" "new dir/x"`, `sed 's#^old/#new/#'`),
  never a bare substring that also hits other paths.

## Two machines, one branch

When the same branch is worked from more than one machine:

- At session start, compare `HEAD` with `origin/<branch>` before editing.
- When diverged: create a backup branch, then `git merge`. Never rebase or
  force-push — the other machine already has the old history.
- Generated files (l10n output, lockfiles, codegen): never hand-merge —
  resolve the sources and regenerate.
- Append-only logs (status, changelog, checklists): on conflict keep both
  sides, local entries first.

## Before Opening a PR

1. Run the full test suite — all green.
2. Run the linter — no new warnings.
3. Review your own diff: remove debug logs, stray comments, and unrelated changes.

## PR Description Template

```markdown
## What
One or two sentences: what this PR does.

## Why
The problem or requirement driving the change (link the issue).

## How
Key implementation decisions worth a reviewer's attention.

## Testing
How this was verified (tests added, manual steps).
```

- Keep PRs small: aim for under ~400 changed lines. Split larger work.
- Mark draft PRs as draft. Never merge your own PR without review unless the repo rules allow it.
