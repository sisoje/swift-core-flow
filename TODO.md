# TODO

- **Collapse `ShellHostKind` (ShellMacro.swift).** Since the host-side `body`
  delegation was removed, the enum's only consumer is the three-way
  `conformance` string switch in `renderShell` — replace enum +
  `detectHostKind` + switch with one function returning `": View"` /
  `": ViewModifier"` / `""`.
