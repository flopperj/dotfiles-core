# Review Heuristics — what a green diff hides

Canonical home for a handful of review/test heuristics shared by Scout, Ranger,
and Cyrus. Each agent carries a one-line pointer back here rather than restating
the full text, so this file is the single source of truth.

Scope is deliberately narrow: only principles **not already encoded** elsewhere
in the kit. Persistence, session protocol, git-as-safety-net, sandboxing, and
plan/spec management are owned by the pipeline skills and are not repeated here.

> **Provenance.** Distilled from autonomous-harness research — Anthropic's
> *Effective Harnesses for Long-Running Agents* (Nov 2025) and *Harness Design
> for Long-Running Apps* (Mar 2026), OpenAI's *Harness Engineering for Codex*
> (Feb 2026), and Geoffrey Huntley's *Ralph Wiggum* technique (Jul 2025), by way
> of the `crodrigues3/harness` evaluator prompt. Re-expressed for this kit's
> stack (TS/PHP/Go) and idiom — not copied verbatim.

---

## The four lies of a green diff

A passing test suite only proves the inputs the author chose to write down. These
four failure modes all show **green** and all ship broken work. Treat each as a
**correctness** finding (a test that lies is a real bug in the test), not a
coverage nit — so it survives confidence filtering rather than being dropped as a
quality nitpick.

1. **The test asserts the wrong thing.** It mocks a collaborator and checks the
   mock was *called*, but never checks the actual result. Classic shape: an error
   path test that asserts `handleError` was invoked but never asserts the `400`
   status that the AC actually requires.
   *Catch it:* read the assertion, not the mock setup. If the only assertions are
   call-count / was-called, the behavior under test is unverified.

2. **The function is dead code.** A new function exists, is unit-tested in
   isolation, and passes — but no call site wires it in. The AC ("paginate lists
   over 100") is satisfied by a `paginate()` that the route handler never calls.
   *Catch it:* grep for call sites of every new/changed symbol. A symbol tested
   only in its own spec file, imported nowhere in production paths, is dead.

3. **A placeholder hides behind the interface.** A method body is `pass` /
   `return null` / `return []` / `throw new Error('TODO')` / `// not implemented`
   that satisfies a type contract while implementing nothing. The type-checker is
   happy; the feature does nothing.
   *Catch it:* grep changed implementation files for `TODO`, `FIXME`, bare `pass`,
   `NotImplementedError`, and trivially-empty bodies on methods that the AC says
   should do work.

4. **The type/contract error tests don't catch.** A mock always supplies a
   well-formed value, so the test is green — but a production path can supply
   `undefined` / `null` / the wrong shape, and prod throws. The test encodes the
   happy mock, not the real contract.
   *Catch it:* check the branch the test *doesn't* exercise. If a param is typed
   `string | undefined` but every test passes a string, the undefined path is
   unverified and likely unhandled.

---

## Test only code you own

Before writing a test, run this filter:

> *"If I deleted this file's source and replaced it with a direct import of the
> underlying library, would this test still pass? If yes, the test is worthless."*

A test earns its place only if it would catch a regression in code **this
repository owns**.

- **Don't test** thin wrappers around a design system or third-party library
  (IDS, MCDS, Radix, shadcn/ui): that a `<Button>` renders its children, that a
  `<Dialog>` opens on trigger, that a `className` prop forwards, that an HTML
  attribute plumbs through. Those libraries have their own suites; re-testing
  them here is pure noise and maintenance debt.
- **Don't test** framework primitives — `JSON.parse`, `Math.max`, `fmt.Sprintf`,
  default-prop forwarding. Never.
- **Do test** code that encodes business logic: conditional rendering driven by
  application state, user interactions that fire callbacks, error/empty/loading
  states, and accessibility attributes that *your* code sets.

This governs *what counts* toward meaningful coverage: wrapper pass-through lines
don't earn their keep, so exclude or stop chasing them rather than gaming the
coverage percentage to hit a threshold.

---

## Enforce invariants mechanically, not in prose

A rule that lives only in documentation rots and is skipped under time pressure.
Anything that can mechanically reject invalid output should be in the loop —
linters, type-checkers, structural tests, CI gates. Custom lint messages should
carry their own remediation so the fix is obvious without a human. In an
agent-driven codebase, an encoded rule applies everywhere at once; a prose rule
applies wherever someone remembers it.

## Scope feedback to what changed

Fast feedback is the constraint on iteration count. Run the checks that exercise
the files that changed — not the whole monorepo suite — unless a release
checkpoint demands the full run. Two failure modes a whole-suite gate creates:
multi-minute cycles that throttle iteration, and unrelated pre-existing failures
that reject a correct change. Verify the diff, not the repo.

## Re-evaluate harness complexity on every model upgrade

Every prompt rule, scaffold, and gate encodes an assumption about what the model
*can't* do on its own. Those assumptions go stale as models improve. When the
model changes, strip the scaffolding that's no longer load-bearing and add only
what a newly-demonstrated ceiling requires. The interesting work moves; it
doesn't simply shrink. Prefer the simplest harness that still holds the quality
bar.
