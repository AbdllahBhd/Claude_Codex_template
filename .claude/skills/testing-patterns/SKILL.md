---
name: testing-patterns
description: Test conventions per stack (JS/TS, PHP/WordPress PHPUnit in wp-env, Flutter/Dart, Python). Use BEFORE writing, fixing, or reviewing any test — files under tests/ or test/, *.test.ts, *.spec.ts, *Test.php, *_test.dart, test_*.py, phpunit.xml, vitest/jest config — and when adding coverage or running a test suite.
---

# Testing Patterns

Universal rules first, then the section for this project's stack. The
project's actual framework and test commands live in CLAUDE.md (Essential
Commands) — they win over the defaults here.

## Universal

- **Arrange–Act–Assert**, one behavior per test; if the name needs "and", split it.
- Test names read as specifications: "returns 404 when the user does not exist".
- Priority: happy path → edge cases (empty, 0/1/max, unicode, huge) → error
  paths (invalid input, missing resource, permission denied, downstream
  failure) → a regression test for every bug fix (fails without the fix).
- Builders with defaults + targeted overrides beat shared fixtures; never
  share mutable state between tests; name magic values.
- Mock at the boundary (HTTP, DB, clock, randomness) — never the unit under
  test; prefer fakes over deep mock chains; always control time.
- Never: assert implementation details, sleep to wait, snapshot logic,
  depend on test order, leave skipped/commented tests in a PR.
- **Cost:** run the tests for the touched module, not the whole suite, until
  the delivery gate (workflow.md, Verification economy). Pipe output through
  `tail -40` — never paste full logs into the conversation.

## JavaScript / TypeScript (Vitest / Jest)

- Tests mirror the source tree: `src/services/user.ts` → `tests/services/user.test.ts`.
- `vi.useFakeTimers()` / `jest.useFakeTimers()` for anything date-based.
- Targeted run: `npx vitest run path/to/file.test.ts` (or `npx jest path`).

```ts
it("rejects orders with an empty cart", async () => {
  const cart = makeCart({ items: [] });
  const result = await submitOrder(cart);
  expect(result.ok).toBe(false);
  expect(result.error.code).toBe("EMPTY_CART");
});
```

## PHP / WordPress (PHPUnit in wp-env)

- Tests run INSIDE the container, not on the host:
  `npx wp-env run tests-cli --env-cwd=wp-content/plugins/<plugin> vendor/bin/phpunit --filter <Test>`
  (Git Bash: prefix `MSYS_NO_PATHCONV=1`). If wp-env is down, say "NOT RUN"
  — never "passed" — and start it (`npx wp-env start`) before retrying once.
- Extend `WP_UnitTestCase`; create data with the factories
  (`self::factory()->post->create([...])`, `->user->create(['role' => 'shop_manager'])`)
  — each test gets a rolled-back transaction, so never clean up by hand.
- WooCommerce: create orders/products through WC CRUD (`wc_create_order()`,
  `new WC_Product_Simple()`), and test HPOS-compatible code paths.
- Hooks/filters: assert behavior (`apply_filters(...)` result, `did_action()`),
  not that `add_action` was called.
- Translations in tests: the suite may force `WP_LANG_DIR` — load the text
  domain explicitly when asserting translated strings.
- Lint is part of testing here: `composer lint` (PHPCS, WordPress standard).

## Flutter / Dart

- `test/` mirrors `lib/`; widget tests use `testWidgets` + `pumpWidget`.
- Ongoing animations/loading states: bounded `pump(duration)` calls, never
  `pumpAndSettle()` on something that never settles.
- Time: `fakeAsync` / an injected clock.
- Targeted run: `flutter test test/features/<feature>/`.

## Python (pytest)

- `tests/` mirrors the package; fixtures in `conftest.py`, kept small.
- `freezegun` or an injected clock for time; `monkeypatch` at the boundary.
- Targeted run: `pytest tests/path/test_x.py -q`.

## Browser checks

Run them in a `sonnet` subagent that returns text (workflow.md model table);
the main thread never collects screenshots.
- Take a screenshot after every navigate or resize and before any coordinate
  click: coordinates from an older screenshot hit the wrong element. Prefer
  `find` / `read_page` refs over coordinates, and page text over images.
- Batch steps you can predict, ≤25 real actions per batch; re-screenshot
  between batches.
- Local pages: start them through `.claude/launch.json` (copy
  `.claude/launch.json.example`; `python3 -m http.server` for static files),
  never `file://` — paths with spaces break, and scripts/modules are blocked.
- Canvas apps (Flutter web, games) have no DOM to read: verify through JS state
  (`window.app…`) or the app's integration tests, not pixel hunting.
- A "Leave site?" dialog blocks every later action: dismiss it first.
- Codex `playwright-cli`: curl-retry the dev server until it answers before
  `open` (`until curl -sf http://localhost:PORT >/dev/null; do sleep 1; done`).

## Android/device checks

- Use `scripts/android-emu.sh up|status|down` and `scripts/android-ui.sh`
  (`wait-for`, `tap`, `dump`, `shot`) — never a hand-rolled boot loop or a
  blind `sleep`.
- Run `android-emu.sh status` first: an emulator, Gradle daemon or second
  server already running halves the machine. One emulator and one dev server
  per session, stopped (`android-emu.sh down`) at task end.
- Read the `uiautomator dump` (`android-ui.sh dump` / `wait-for`) before taking
  a screenshot; at most one screenshot per UI state, only to prove layout.
- A flow you clicked through twice becomes a test:
  `flutter test integration_test/<flow>_test.dart -d <device-id>`.

## Definition of done

New logic is covered, the targeted tests pass, and coverage of the touched
files did not decrease. The full suite runs at the delivery gate.
