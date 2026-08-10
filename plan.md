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
10. Do not edit source code while performing this plan.

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
- **Phase 3 — README compression and continuity:** in progress.
- **Next checkpoint:** review only the first paragraph under `Shell` and propose
  its exact replacement before editing.

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
  `8912770 Clarify unmapped object wrappers`. Each pairs its README change with
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
- Current local checkpoint (uncommitted): folded the rejected generated-backing
  model into the binding rule; preserved the use-site/test-shaped decision,
  all three backing strategies, `Bindable(model).x` write-through fact, and
  probe-verified sample; added the verified file-scope reason and kept
  `@MainActor`; moved the no-backing `@State` contrast after the sample.
- Next checkpoint: review `QueryCore`. Preserve the verified
  `_SwiftData_SwiftUI` interface parity — exactly `wrappedValue`, `fetchError`,
  and `modelContext`, with no `projectedValue` — and the bare-value memberwise
  construction `Core(items: [item], ...)` with no `QueryCore` spelling.
- Expect the largest later merges around the wrapper mapping, `QueryCore`, and
  `Notes on the rows`, which repeat rules at different depths.
- Reconcile `Previews: one hand-written wrapper away` with the scenario material
  now present earlier in the README.
- Preserve load-bearing verification evidence while merging; a "verified
  directly" clause is not filler merely because the rule appears elsewhere.

- Merge paragraphs that defend the same design decision.
- State a rule once, then link back to it.
- Remove experimental chronology when only the resulting constraint matters to
  a user.
- Retain honest limitations and exact compiler consequences.
- Improve transitions so the reference still reads as one continuous argument.
- Target roughly a 10% reduction across the README, but never cut to meet a
  quota.

Review and approve each feature section before continuing.

## Phase 4: README code and prose

Audit every code sample after its surrounding prose is stable.

- Give each sample one primary claim.
- Remove fields and comments that do not prove that claim.
- Keep examples minimal and idiomatic.
- Probe-compile every touched sample against the real package and macro
  expansion; plausible syntax is not sufficient.
- Ensure names match the terminology used in the paragraph.
- Put the consequence immediately after the line that demonstrates it.
- Reuse an existing example only when doing so reduces explanation; do not force
  one example through unrelated APIs.

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
- review the final diff for accidental tone changes or lost qualifications.

## Completion rule

The work is complete when the documents are easier to navigate, all retained
technical claims are at least as precise as before, the README still sounds
like the articles, `CLAUDE.md` remains self-sufficient and is faster for an
agent or maintainer to consult, and `CoreFlowExample/SPEC.md` agrees with both.
No phase proceeds through an unapproved change in thesis or voice.
