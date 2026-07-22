# TODO

- **Delete `outFlowProperties` (FlowableRendering.swift) — it's the identity
  function.** Its filter (non-private, or private with a recognized
  source-of-truth wrapper) passes everything `collectStoredProperties` lets
  through: every other combination is already a diagnostic
  (`sourceOfTruthMustBePrivate` / `callerSuppliedWrapperMustNotBePrivate` /
  `plainPrivatePropertyNotAllowed` / `unsupportedPrivateWrapper`). Pass
  `properties` straight through in `renderShell` and the `OutFlow` renderers.

- **Collapse `ShellHostKind` (ShellMacro.swift).** Since the host-side `body`
  delegation was removed, the enum's only consumer is the three-way
  `conformance` string switch in `renderShell` — replace enum +
  `detectHostKind` + switch with one function returning `": View"` /
  `": ViewModifier"` / `""`.

- **Decide what the generated `core` computed property is for.** It's back in
  `renderShell` (capturing a `Core` off the live instance) but nothing
  consumes it yet — usage TBD.

- NOT doing: unifying `renderShell`'s field-decl branches with
  `outFlowFieldType` — same wrapper→substitution mapping spelled twice
  (`@QueryCore var x: T` vs `QueryCore<T>`), but `FocusState<T>.Binding` and
  the plain-`let` rows don't fit one shape; the shared table would be worse
  than the duplication.
