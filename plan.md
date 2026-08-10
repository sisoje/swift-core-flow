# Documentation improvement plan

## Objective

Improve `README.md` and `CLAUDE.md` without replacing their argument, voice, or
technical density. Edits should be surgical: clarify, compress, and connect the
existing material rather than inventing a new narrative.

The authorial and conceptual baseline is:

- `../article-dataflow/DataFlowMasterclass.md`
- `../article-dataflow/proposals/TheOtherTDD-draft.md`

The intended voice is provocative first, mechanically rigorous second. Do not
soften a deliberate thesis merely to make the prose sound neutral.

## Working method

1. Work on one paragraph, sample, or tightly related group at a time.
2. Propose the exact change before editing when it involves tone or argument.
3. Preserve every technical claim unless its removal is explicitly approved.
4. Apply the approved edit and show its focused diff.
5. Update this plan immediately after every approved checkpoint: record what
   completed, the current phase status, and the exact next step before any
   commit is created.
6. Commit each README checkpoint together with its matching `plan.md` status
   update. Never commit README prose and plan bookkeeping separately.
7. Stage, commit, amend, reset, or push only when the user explicitly requests
   that Git action. Approval of prose authorizes the file edit, not a commit.
8. When explicitly requested, amend only while a checkpoint commit remains
   local and unpushed. Never amend a pushed commit.
9. Record commit hashes only for commits that already exist. Refer to an
   uncommitted or in-progress checkpoint by description or intended message,
   never by an anticipated hash.
10. A checkpoint committed with this plan must be labeled completed in that
    commit; do not commit a self-expiring "current local checkpoint" status.
11. Do not edit source code while performing this plan.

## Editing criteria

For every change:

- preserve the provocative voice;
- shorten without losing information;
- remove repetition, filler, and unnecessary qualification;
- prefer precise mechanisms over generic architectural language;
- keep transitions causal so each section follows from the previous one;
- make code and prose demonstrate the same claim;
- use the established vocabulary consistently;
- challenge a weak assumption by making it rigorous, not by quietly changing
  the thesis;
- avoid large structural rewrites until the local prose is settled.

Established vocabulary includes **node**, **network**, **transformation**,
**wave**, **source of truth**, **self-loop**, **boundary event**, **machinery**,
**host**, **twin**, **seam**, **shell**, **core**, **scenario**, and
**execution log**.

## Current status

- **Phase 1 — README opening:** completed.
- **Phase 2 — README structure and navigation:** completed.
- **Phase 3 — README compression and continuity:** completed.
- **Phase 4 — README code and prose:** completed.
- **Phase 5 — README conclusion:** next.
- **Next checkpoint:** propose the exact short conclusion before editing; make
  the consequence sharp without summarizing the feature catalog.

## Phase 1: README opening — completed

### Completed: `Why`

- Restored the two-punch thesis: a SwiftUI view is not UI; its `body` never
  draws anything.
- Clarified that `body` computes the actions attached to the description too.
- Compressed the ViewModel argument without softening it.
- Replaced vague mocking language with the concrete inability to substitute
  dependencies.
- Kept the three runtime constraints: tests cannot run the logic directly,
  substitute dependencies, or reuse `body` through a conformance.
- Removed the hedge "not necessarily."

Phase commits:

- `74d2a38 Tighten README introduction`
- `46295d5 Refine README answer and vocabulary`

### Completed: `The answer`

Reviewed its three paragraphs separately:

1. Tightened the runnable-twin answer and connected it directly to the runtime
   constraints established in `Why`.
2. Preserved the node/source-of-truth model while removing repeated setup and
   correcting the `@AppStorage`/`@Query` ownership overclaim.
3. Stated the adoption boundary and `ObservableObject` consequence with the
   same confidence and vocabulary as the articles.

The opening now reads as one argument: misconception, runtime constraint,
generated seam, data-flow model, adoption boundary.

## Phase 2: README structure and navigation — completed

Review headings and section order without rewriting their contents first.

Completed:

- Replaced the second top-level heading `# What` with `## Installation`, leaving
  `# CoreFlow` as the document's single title.
- Moved the package-identity sentence to the end of `The answer`, where it
  widens from the `@Shell` mechanism to the whole package.
- Made `Installation` open directly with the dependency snippet.
- Preserved the masterclass paragraph as the bridge into the API index.

Final phase commit: `dcef576 Clarify README section hierarchy`.

Closure check:

- Verified the new `## Installation` boundary exists exactly once.
- Re-verified that `#what` is absent and unreferenced in `README.md`,
  `CLAUDE.md`, and `CoreFlowExample/SPEC.md`.
- Verified the package-identity sentence remains immediately before
  `Installation`, followed by the dependency snippet and then `What's inside`.
- Kept the check scoped to the Phase 2 changes; the full three-document anchor
  audit remains Phase 7 work.
- Closed without reordering feature sections. Their order is conceptual and
  dependency-led: `Shell`, the test-support family its mapping introduces, then
  the independent macros and utility. Mirroring the API table would create
  churn without a demonstrated navigation gain.

- Keep the feature table as the quick API index.
- Move material only when it clearly interrupts the main explanation.
- Prefer links to repeated explanations.
- Keep advanced compiler constraints available, but decide whether each belongs
  in the main path or a limitations subsection.

Approve the revised skeleton before moving any section.

## Phase 3: README compression and continuity

Proceed one feature section at a time, beginning with `Shell`.

Current checkpoint:

- Completed the first paragraph under `Shell`: mapped both names in the pattern
  (host to shell, `Core` to functional core), introduced the runnable-twin
  relationship, replaced the broad observability claim with the actual boundary
  mapping, preserved constructibility/assertability anywhere, and stated live
  event-channel removal in terms of waves.
- Completed the second paragraph under `Shell`: stated the two stored-property
  rules, replaced the inaccurate "mockable stand-in" umbrella with "test
  boundaries," retained the complete copied-member list (including static
  members), and preserved the initializer and separate-extension constraints.
- Phase 3 commits so far: `ec9c2b2 Tighten Shell introduction`,
  `6482979 Clarify Shell generation rules`, and
  `37ea1e5 Clarify substituted wrapper mapping`, and
  `9e393f0 Consolidate copied wrapper rules`, and
  `8912770 Clarify unmapped object wrappers`, and
  `07651f1 Clarify binding backing strategies`, and
  `30e8807 Clarify QueryCore interface parity`, and
  `976b02a Clarify why Core is nominal`, and
  `23d7ee2 Close README compression phase`. Each pairs its README change with
  the matching plan checkpoint.
- Completed checkpoint: left the probe-verified
  `Card`/`CardScenario` sample unchanged; tightened the three-term glossary;
  grounded **boundary event** as instrumented state writes and action calls;
  and replaced both occurrences of "the log IS the behavior" with the rigorous
  evidence claim.
- Completed checkpoint: tightened the **Substituted** rule;
  preserved every mapping's reason, privacy and memberwise-initializer
  constraints, anti-hoisting evidence doctrine, `@FocusState` impossibility
  proof, links, and semantic-whitelist boundary; left the probe-verified sample
  unchanged.
- Completed checkpoint: consolidated the **Copied verbatim**
  rule with its machinery rationale and removed the unlinked duplicate
  subsection with zero information loss — Phase 3's first net heading deletion;
  preserved the `@GestureState(reset:)` byte-for-byte fact,
  `TrickyDragCardUITests` live verification, environment mocking story,
  self-initialization proof, private-copy sealing rules, and "static members"
  in the earlier copied-member list.
- Completed checkpoint: renamed the mapping table's source
  column from architectural role **Shell** to source type **Host**; replaced the
  `ObservableObject` dependency-graph overclaim with the actual missing
  value-shaped boundary and aliasing mechanism; retained the explicit
  ViewModel-shaped-state link to `Why`. The wrapper mapping reference is now
  complete.
- Completed checkpoint: folded the rejected generated-backing
  model into the binding rule; preserved the use-site/test-shaped decision,
  all three backing strategies, `Bindable(model).x` write-through fact, and
  probe-verified sample; added the verified file-scope reason and kept
  `@MainActor`; moved the no-backing `@State` contrast after the sample.
- Completed checkpoint: split `QueryCore` into interface
  parity, copied-body consequences, and memberwise-initializer ergonomics;
  preserved the verified exact-three-member surface and bold
  **no `projectedValue`** fact, stated that `modelContext` remains
  environment-fed like the live wrapper's, and retained bare-value construction
  with no `QueryCore` spelling.
- Completed checkpoint: made the nominal-type conclusion lead
  the argument; replaced vague live-hosting language with the operative `View`
  conformance; distinguished holding fields from carrying copied logic and
  adopting protocols; preserved the verbatim compiler error as a fenced block.
- Completed checkpoint: replaced `Notes on the rows` with `Two verbatim edge
  cases`; preserved the binding write-through behavior, both `@ViewBuilder`
  forms, exact diagnostic, and attribute distinction; removed no inbound anchor.
- Completed checkpoint: tightened the preview limitation around its working-host
  control case, preserved the five-way verification and file-scope type-position
  failure, and connected the solution directly to the earlier scenario.
- Completed Phase 3 audit: read the full `Shell` chapter for continuity and
  checked relocated verification clauses. Removed the duplicated `@ViewBuilder`
  initializer fact while retaining its verification marker below, and retained
  the independently verified wrapper-type-versus-wrapped-type initializer rules
  in the no-generated-init argument.
- Merge paragraphs that defend the same design decision.
- State a rule once, then link back to it.
- Remove experimental chronology when only the resulting constraint matters to
  a user.
- Retain honest limitations and exact compiler consequences.
- Improve transitions so the reference still reads as one continuous argument.
- Target roughly a 10% reduction across the README, but never cut to meet a
  quota.

Phase 3 is complete. It removed two headings, replaced four overclaims with
mechanisms, and retained every verified fact.

## Phase 4: README code and prose

Audit every code sample after its surrounding prose is stable.

Completed checkpoints:

- Phase 4 commits so far: `b3cbfff Tighten README test-support samples` and
  `52bd825 Fix Capability sample and record probes`.
- Audited the `Card`/`CardScenario`, binding write-through,
  `ButtonTestHost`, `DownloadButton`, and `LoginScenario` samples together.
- Left the first two probe-verified samples and `DownloadButton` unchanged.
- Removed a third copy of the `@TestAction` getter mechanism from the
  `ButtonTestHost` comment and made the action-to-recorded-evidence sequence
  explicit.
- Made `LoginScenario` self-contained with its `Field` and `email` declarations;
  kept the real projected-binding fact only in its existing explanatory bullet.
- Compiled both touched samples against the real package and macro expansion.
  Ran the payload probe and observed
  `Optional(CoreFlowTests.LoginScenario.Field.password)`, confirming the README's
  placeholder-module spelling `Optional(MyApp.LoginScenario.Field.password)`.
- Audited every `Flowable` and `Capability` sample as one batch. Left the
  `User`, `@Observable` one-field `Counter`, SwiftUI `Card`, `makeFlow(_:)`, and
  `InFlow` samples unchanged because each line still proves an adjacent rule.
- Compile-probed those samples together against the real package, including
  stacked `@Flowable`/`@Observable`, labeled and differently labeled tuple
  conversion, labeled `InFlow` forwarding, one-field collapse without `.0`,
  and the stored-value `@ViewBuilder` initializer shape.
- Re-ran all 20 `FlowableTests` and all nine `CapabilityTests`; every displayed
  generated-code block in this batch matches its locked macro expansion.
- Changed the flagship `Capability` example from a struct with a no-op
  `increment` placeholder to a final class whose nonmutating method really
  changes state. The runtime probe confirmed that computed-property fields are
  snapshots while captured method closures remain connected to the instance:
  cached `doubled` stayed `0`, and a fresh capability read `2` after increment.
- Audited every `#pick` and `Reflector` sample together. Corrected the flagship
  comments and adjacent prose to distinguish labeled expansion literals from
  positional static result types; made the tuple-KeyPath result explicit; and
  reformatted cross-arity nesting to expose its overload structure.
- Compiled and ran every successful sample in that batch, including the `=>`
  rename, one- and two-source picks, native tuple KeyPaths with the inferred
  `WritableKeyPath<(a: Int, b: String), Int>` type, two-statement composition,
  cross-arity nesting, repeated `from:` grouping, generated `InFlow`, and both
  Reflector label shapes.
- Compiled the intentional same-overload nesting failure and captured the exact
  diagnostic: `recursive expansion of macro 'pick(from:_:)'`.
- Re-ran all 16 `PickMacroTests`, the eight `#pick` `EndToEndTests` (plus the
  separately selected test-support test), and all five `ReflectorTests`; all
  passed, and the displayed `#pick` expansions remain locked by the macro tests.
- Replaced the universal Reflector safety claim with its actual evidence and
  limit: current `Mirror` behavior was verified for value types with reference,
  closure, and array fields, but reflecting uninitialized storage remains an
  implementation-dependent runtime technique. The implementation listing and
  the rest of the verified value-type limitation section remain unchanged.
- Completed the final Phase 4 audit. Corrected the Shell diagram so copied
  runtime machinery reaches `Core`, added the missing `@FocusState` source,
  split test boundaries from verbatim machinery, and replaced the false “no
  environment” arrow with the actual avoided requirements: no live view,
  external storage, or SwiftData stack. Renamed both explanatory node references
  and replaced the in-scope “with mocks” wording with “supplied test boundaries.”
- No Mermaid parser was available. Structurally audited all three diagrams
  instead: every node identifier resolves, the Shell edges match the wrapper
  mapping, and both Flowable diagrams remain consistent with their adjacent
  prose. The two Flowable diagrams required no edit.
- A real scratch-package resolution found the displayed installation identity
  was wrong: SwiftPM reported `unknown package 'CoreFlow'` and named
  `swift-core-flow` as valid. Changed the product dependency to
  `package: "swift-core-flow"`; the corrected manifest resolved release 1.0.2
  and swift-syntax 603.0.2 successfully.
- Re-probed the tuple-conformance diagnostic. The compiler emitted
  `error: type '(x: Int, y: String)' cannot conform to 'Equatable'
  [#ProtocolTypeNonConformance]` and the corresponding `note:` line. The README
  deliberately retains the two message texts while explicitly documenting that
  source locations, severity markers, and the diagnostic identifier are omitted.
- Re-probed the arbitrary `total:` label against the real macro. Its primary
  diagnostic matches `error: extra argument 'total' in macro expansion`; the
  README now also records the emitted follow-on key-path-inference error. The
  previously captured same-overload diagnostic remains unchanged.
- Restored `public` on the displayed `Reflector.fieldNames` implementation so
  the signature and body match `Sources/CoreFlow/Reflector.swift` exactly.
  Left `DownloadButton` and all remaining isolated examples unchanged.
- Ran the complete test suite after removing every probe source: all 62 XCTest
  tests and all 39 Swift Testing tests passed. The macro-expansion suites lock
  every displayed generated-code block.

- Give each sample one primary claim.
- Remove fields and comments that do not prove that claim.
- Keep examples minimal and idiomatic.
- Probe-compile every touched sample against the real package and macro
  expansion; plausible syntax is not sufficient.
- Ensure names match the terminology used in the paragraph.
- Put the consequence immediately after the line that demonstrates it.
- Reuse an existing example only when doing so reduces explanation; do not force
  one example through unrelated APIs.

Phase 4 is complete: every touched Swift sample was compiled, displayed
generated code is expansion-locked, quoted diagnostics were compared against
captured output with normalization recorded, and no probe source remains.

## Phase 5: README conclusion

Add or sharpen the closing takeaway only after the reference body is settled.
It should restate the consequence, not summarize every feature:

- behavior stays where it was written;
- runtime boundaries become observable or injectable;
- tests read boundary evidence rather than execute effects;
- adoption can proceed one node at a time.

Keep the conclusion short and provocative.

## Phase 6: CLAUDE.md agent and maintainer pass

Treat `CLAUDE.md` as both agent context and a maintainer specification, not a
second public article. It must remain self-sufficient: a session reading only
`CLAUDE.md` must know every rule, verified fact, and rejected design needed to
work safely in the repository.

1. Put package invariants and build commands first.
2. Separate normative rules from implementation mechanisms.
3. Separate both from verified compiler limitations and rejected designs.
4. Consolidate rules shared by the logged-property macro family.
5. Convert repeated wrapper behavior into a precise mapping table where that is
   clearer than prose.
6. Preserve experimental evidence that prevents maintainers from repeating dead
   ends, but move it out of the operational path.
7. Compress duplication internally, but never delete required context into the
   README or make `CLAUDE.md` depend on another document for a rule, verified
   fact, or dead end.
8. Mirror the README's Reflector safety correction: replace the claim that
   reading only `.label` makes uninitialized reflection safe with the verified,
   implementation-dependent framing, while preserving the top-level class trap
   and value-type observations.
9. Correct the installation product dependency to
   `.product(name: "CoreFlow", package: "swift-core-flow")`; a real scratch
   resolution proved the existing `package: "CoreFlow"` spelling invalid.

Propose the new `CLAUDE.md` skeleton before moving any content.

## Phase 7: consistency audit

After both documents are stable, audit `README.md`, `CLAUDE.md`, and
`CoreFlowExample/SPEC.md` together:

- unify terminology, heading style, punctuation, and identifier formatting;
- check every internal anchor and external link;
- compare public claims in the README with maintainer invariants in
  `CLAUDE.md`;
- check scenario names, wrapper mappings, vocabulary, and "verified live"
  claims against `CoreFlowExample/SPEC.md`;
- check code/prose agreement;
- remove remaining duplicated conclusions and filler transitions;
- review the two out-of-scope “with mocks” occurrences for established
  test-boundary vocabulary without changing the diagrams already approved;
- review the final diff for accidental tone changes or lost qualifications.

## Completion rule

The work is complete when the documents are easier to navigate, all retained
technical claims are at least as precise as before, the README still sounds
like the articles, `CLAUDE.md` remains self-sufficient and is faster for an
agent or maintainer to consult, and `CoreFlowExample/SPEC.md` agrees with both.
No phase proceeds through an unapproved change in thesis or voice.
