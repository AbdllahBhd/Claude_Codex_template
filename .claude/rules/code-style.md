# Code Style Rules

> Loaded via CLAUDE.md. These rules apply to ALL code Claude writes in this project.
> Adjust them to match your team's actual style.

## General

- Match the style of the surrounding code before applying any rule here.
- Prefer small, focused functions (under ~40 lines). Extract helpers when logic branches grow.
- No dead code: delete unused imports, variables, and commented-out blocks.
- No `TODO` comments without an issue/ticket reference.

## Naming

- **Variables / functions:** `camelCase`
- **Classes / types / components:** `PascalCase`
- **Constants:** `UPPER_SNAKE_CASE`
- **Files:** `kebab-case` (e.g. `user-service.ts`), except components which match the component name.
- Names describe intent, not implementation: `retryDelayMs`, not `num2`.

## TypeScript / JavaScript (adapt to your language)

- Prefer `const` over `let`; never use `var`.
- Prefer explicit return types on exported functions.
- No `any` — use `unknown` and narrow, or define a proper type.
- Use early returns over deep nesting.
- Async: always `await` or explicitly handle the promise; no floating promises.

## Error Handling

- Never swallow errors silently (`catch {}` is forbidden).
- Throw `Error` subclasses with descriptive messages, not strings.
- At boundaries (API handlers, CLI entry points), catch, log, and return a clean error.

## Comments

- Comment **why**, never **what**. The code says what.
- Keep JSDoc on exported/public functions only.
- Don't add comments that narrate your changes ("added this to fix X") — that belongs in the commit message.

## Formatting

- Formatting is owned by the formatter (Prettier/ESLint/etc.) — never hand-format against it.
- Run `npm run lint` after edits; fix what it reports.
