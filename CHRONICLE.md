# CoreFlow project chronicle — all sessions compiled

Local record, untracked. Compiled 2026-08-10 from four Claude Code session
transcripts in this project plus the working files they produced.

## Session 1–2 (Jul 30) — example-app generator

Two short sessions getting `CoreFlowExample`'s `generate.sh` working: the
example app's Swift sources regenerate from `SPEC.md` via a headless claude
invocation; these sessions debugged that pipeline.

## Session 3 (Aug 4) — @UnstructuredTask is born

Ported the standalone `~/dev/TaskState` package into CoreFlow, then rejected
the runtime-wrapper design in favor of a per-property macro so mutations log
the property's actual name through `\.testLog`. Named `@UnstructuredTask`
(stores an unstructured `Task`, gives it the two structure guarantees it
lacks: cancel-on-replace, cancel-on-teardown; avoids a one-letter-apart
`@TaskState`/`@TestState` pair). Task slot always starts `nil`; lifecycle
lives in a `TaskStorage` class held in `State` (`willSet` cancels
replacement, `deinit` cancels on teardown, identity-guarded against
self-assignment); payload is stable `task`/`nil`.

## Session 4 (Aug 5–10) — the marathon

One continuous session (summarized and resumed multiple times) covering five
arcs:

### Arc 1: @TestFocusState

Designed through many rejected alternatives (binding interception is
impossible: `FocusState<T>.Binding` has no public initializer and no macro
can wrap a foreign setter — receiving-side support deliberately dropped,
owner-side only). Final design: computed property over a real self-initialized
`FocusState<T>` peer; the property logs, the projection wires. Set the
family-wide policy: bad shapes THROW from expansion (a silent skip can
compile as unmanaged state — the compiler does not error on macro-added
accessors over an initialized var). `@Shell` substitutes it for `@FocusState`.

### Arc 2: coverage investigation → upstream bug report

Discovered Swift emits NO coverage instrumentation for functions in
macro-expansion buffers (zero counters under any filename);
`#sourceLocation` remaps correctly but cannot help — the gate is emission,
not mapping. Built two minimal reproducers (`CoverageRepro`,
`CoverageReproTwin`), posted to the Swift forums
(https://forums.swift.org/t/88824 — Tony Allevato: "file an issue; I highly
doubt this is intentional"), drafted the GitHub issue. Also hit and
documented the delegation redesign dead end (built, run green, abandoned)
and the mirror-macro impossibility ("macro expansion cannot introduce
extension").

### Arc 3: the documentation campaign (~35 commits, 7 phases)

GPT drafted, Claude reviewed with probe-everything discipline, user
committed. README: compressed at constant weight (10.5k words), every sample
compiled/run, every quoted diagnostic capture-matched, two headings deleted,
four overclaims replaced with mechanisms ("the log IS the behavior" → "the
log is the evidence"), conclusion added ("The point"), and one real
consumer-facing bug found by a live resolve probe: `package: "CoreFlow"` →
`package: "swift-core-flow"`. CLAUDE.md: rebuilt from a 946-line
accumulation into a ~1,400-line self-sufficient spec across 8 checkpoints —
one source-contradicted claim corrected (UnstructuredTask initializer
guard), two never-recorded verified facts added (release elimination of
Core; the generated `$name: Binding<T?>`), an 11-item accepted-loss registry
created, all diagrams later render-validated with real mermaid-cli.
Phase 7 closed twice (first closure measured the diff, not the spec — the
lesson is recorded). Plan removed at HEAD, readable at commit `f7ed90a`.

### Arc 4: the article corpus

Reviewed and finished "TDD: Death by a Thousand Mocks" (the manifesto):
TypeScript samples probe-verified (strict tsc + runtime log assertions),
Mock Roles author order corrected via Crossref (Freeman first), SwiftUI
funnel coda added linking the two published pieces. Triaged GPT feedback at
~20% signal: accepted the `credit < order.total` domain-bug fix, layer-first
precision, self-contained literals, one "Two honest limits" paragraph;
rejected all hedging of mechanism-backed claims. Also probed the published
"TDD Is Dead. Long Live TDD." Swift samples — all compile under Swift 6
strict concurrency, the log test passes as printed. Defended the masterclass
against a critique that quoted headlines while ignoring their attached
mechanisms (one clause conceded: the `@Observable` opt-in exception).
Packed everything into `~/dev/article-dataflow/tdd-death/` — manifesto,
index README, 22 reference notes, 3 verbatim snapshots, and `handoff.md`
(the authoritative state document).

### Arc 5: new doctrine (unpublished, strongest available material)

Three arguments developed in conversation, recorded in the handoff:

1. **Material, not reactivity, bounds the method** — core/shell works
   everywhere; declarative UI extends its reach into the view layer because
   views became values; object-material reactive systems get nothing.
2. **"The network is reactive so the nodes don't have to be"** — a node's
   write is the last thing it ever does; it dies in the wave it triggers and
   the result arrives as its successor's creation inputs. That contract is
   what closes the unit at the boundary event and makes the log complete
   evidence.
3. **Ian Cooper inherited, not refuted** — "test the public interface" is
   really "couple tests only to refactoring-stable contracts"; data coupling
   gives every node such a contract, so the rule applies fractally. RTL's
   "test like a user" is the same rule frozen at the coarsest grain.

## Standing state (as of compilation)

- CoreFlow: pushed through `e249d73`; tests 62 XCTest + 39 Swift Testing,
  green. Example-app generated sources wiped by a failed generator run —
  recover with `cd CoreFlowExample && sh generate.sh` (needs claude login),
  then `sh test.sh`.
- GitHub coverage issue: drafted (ISSUE.md + reproducers were throwaway
  files), forum thread awaiting the filed-issue link.
- Errata list: Mock Roles author order in the published TheOtherTDD.
- Next planned piece: the React variant
  (`React-Death-by-a-Thousand-Mocks.md`) — plan in the handoff.
