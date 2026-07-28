# ExampleApp — regeneration spec

The Swift sources of this example are deliberately collapsed into this spec;
regenerate them from the contracts below. `project.yml` and `test.sh` are kept
verbatim next to this file and are part of the spec (targets, scheme, build
settings, the no-lldb-attach note, and the test invocation live there). Verify
a regeneration with `sh test.sh` in this directory.

The spec assumes the `@Shell` mapping where `@State` substitutes to
`@TestState private` on `Core` (Core owns and logs its own state; sealed, out
of the memberwise init, host's inline default required), `@AppStorage`/
`@SceneStorage` → `@Binding` (external storage is an injected dependency),
and unknown wrappers (`@GestureState`, `@FocusState`) copied verbatim with
their attribute arguments.

## What this example is

One app, scenario per component, covering the tricky wrappers:
`@GestureState(reset:)`, `@FocusState`, a `ViewModifier` host, an async
throwing action. Everything lives in two flat directories: `Sources/` (app
entry + one file per component, each holding host, scenario, and `#Preview {
TheScenario() }`) and `UITests/` (helper + one suite per component).

## Sources/ExampleApp.swift — entry + the log element

`enum ExampleScenario: String` — cases `dragCard = "DragCard"`,
`trickyDragCard = "TrickyDragCard"`, `focusField = "FocusField"`, `dimmer =
"Dimmer"`, `saveButton = "SaveButton"`; `static var defaultScenario` is
`.focusField` (used when `EXAMPLE_SCENARIO` is unset, so Cmd-R just works).

`@main struct ExampleApp: App`: `init()` reads
`ProcessInfo.processInfo.environment["EXAMPLE_SCENARIO"]`, falls back to
`defaultScenario`, `fatalError`s on an unknown value. `@State private var
logItems: [(String, String)] = []`. The scenario `switch` sits in a `Group`
carrying the log element — names JSON in label, values JSON in value, read by
the UI tests:

```swift
.accessibilityElement(children: .contain)
.accessibilityIdentifier("log")
.accessibilityLabel(logNamesJSON)
.accessibilityValue(logValuesJSON)
.testLog { property, value in logItems.append((property, value)) }
```

`logNamesJSON`/`logValuesJSON` are `JSONEncoder().encode` of
`logItems.map(\.0)`/`\.1` as UTF-8 strings.

## Sources/DragCard.swift — live @GestureState

Dragging must stream nonzero offsets (`maxDistance` grows — Core's own
`@State` → `@TestState` state) and snap back to zero on release
(`GestureState`'s own reset).

```swift
@Shell
struct DragCard: View {
    @GestureState private var dragOffset: CGSize = .zero
    @State private var maxDistance: CGFloat = 0
}
```

Body: `VStack(spacing: 24)` of `Text("max \(Int(maxDistance))")` (identifier
`maxLabel`), `Text("current \(Int(hypot(dragOffset.width,
dragOffset.height)))")` (`currentLabel`), and a blue
`RoundedRectangle(cornerRadius: 16)` 120×120, `.offset(dragOffset)`, with
`DragGesture().updating($dragOffset) { value, state, _ in state =
value.translation }` (`dragBox`); `.onChange(of: dragOffset)` sets
`maxDistance = max(maxDistance, hypot(new.width, new.height))`.

Scenario: bare `DragCard.Core()` — nothing to wire.

## Sources/TrickyDragCard.swift — argument-carrying @GestureState

The developer's reset behavior lives in the attribute's own arguments, and
`@Shell` copies the declaration onto `Core` byte-for-byte, so the closure
rides along. A file-scope probe makes the firing observable:

```swift
enum ResetProbe {
    nonisolated(unsafe) static var count = 0
}

@Shell
struct TrickyDragCard: View {
    @GestureState(reset: { _, _ in ResetProbe.count += 1 })
    private var dragOffset: CGSize = .zero
    @State private var resetsSeen = 0
}
```

Body: `VStack(spacing: 16)` of `Text("resets \(resetsSeen)")`
(`trickyResetsLabel`) and an orange `RoundedRectangle(cornerRadius: 16)`
100×100, `.offset(dragOffset)`, same `.updating` gesture (`trickyDragBox`);
`.onChange(of: dragOffset)` sets `resetsSeen = ResetProbe.count` when the new
value is `.zero`.

Scenario: bare `TrickyDragCard.Core()`. The copied body's write logs exactly
once per completed drag — deterministically `1` in a fresh process, so the
snapshot is stable.

## Sources/FocusField.swift — machinery vs external storage, one host

The two unsubstituted-vs-substituted halves in one host. `@FocusState` is
UI-runtime machinery: unmapped, so `Core` carries its own verbatim copy —
tapping the field moves the OS's real focus into Core's read, the toggle
button writes back out. `@AppStorage` is EXTERNAL storage, a dependency:
`Core` takes it as a `@Binding` the scenario backs and logs, so the same tap
is asserted live on one side and by mutation log on the other.

```swift
@Shell
struct FocusField: View {
    @AppStorage("focusToggleCount") private var toggleCount = 0
    @FocusState private var isFocused: Bool
}
```

Body: `VStack(spacing: 16)` of `Text(isFocused ? "focused" : "unfocused")`
(`focusStatusLabel`), `TextField("Type here", text: .constant(""))` with
`.focused($isFocused)` (`focusTextField`), and `Button("Toggle Focus") {
isFocused.toggle(); toggleCount += 1 }` (`toggleFocusButton`).

Scenario: `@TestState var toggleCount = 0`, body
`FocusField.Core(toggleCount: $toggleCount)`.

## Sources/DimmerDemo.swift — the ViewModifier host

`@Shell` on a `ViewModifier`: `body(content:)` is written once and copied
into `Core`, which gets its own `: ViewModifier` conformance.

```swift
@Shell
struct Dimmer: ViewModifier {
    @State private var isDimmed = false
}
```

`func body(content: Content) -> some View`: `VStack(spacing: 16)` of
`Text(isDimmed ? "dimmed" : "bright")` (`dimStatusLabel`), `content` with
`.opacity(isDimmed ? 0.2 : 1)`, and `Button("Toggle Dim") {
isDimmed.toggle() }` (`toggleDimButton`).

Scenario: `Text("Hello")` (identifier `dimContent`)
`.modifier(Dimmer.Core())` — Core owns `isDimmed` itself; every tap inside
the copied body logs.

## Sources/SaveButton.swift — async throwing action

An action plus an async throwing dependency — the closures ride onto `Core`
as plain memberwise parameters, `@State` becomes `@TestState`.

```swift
@Shell
struct SaveButton: View {
    @State private var userName = ""
    let onSave: (String) -> Void
    let getUserName: (_ id: String) async throws -> String
}
```

Body: `VStack(spacing: 16)` of `Text(userName.isEmpty ? "anonymous" :
userName)` (`userNameLabel`) and `Button("Save Draft")` (`saveDraftButton`)
whose action calls `onSave("draft")` then `Task { userName = (try? await
getUserName("42")) ?? "Error fetching user" }`.

Scenario — both actions logging mocks, the async one a throwing stub (a mock
needs no invented return value; the component's own fallback lands in Core's
own logged state):

```swift
@TestAction var onSave: (String) -> Void = { _ in }
@TestAction var getUserName: @Sendable (_ id: String) async throws -> String = { _ in
    throw CancellationError()
}
```

body: `SaveButton.Core(onSave: onSave, getUserName: getUserName)`.

## UITests

`LaunchHelper.swift`: `func launchExampleApp(scenario: String) ->
XCUIApplication` (nonisolated — no `@MainActor` on this one) setting
`launchEnvironment["EXAMPLE_SCENARIO"]` before `launch()` — the app is a
separate process and inherits nothing from the invoking shell (verified
directly); every test states its scenario explicitly. An `XCUIApplication`
extension adds `var log: XCUIElement { otherElements["log"] }` and `var
logValues: [String]` JSON-decoding `log.value`. Tests wait on names —
`log.wait(for: \.label, toEqual:)`, the finish line AND the names assertion —
then `XCTAssertEqual` on `logValues`. All test methods `@MainActor`, on plain
`XCTestCase`.

- `DimmerUITests.testToggleDimWritesThroughCoreViewModifier` — scenario
  `Dimmer`: `dimStatusLabel` starts `"bright"`, `dimContent` exists; tap
  `toggleDimButton` → `"dimmed"`, tap again → `"bright"` (each awaited);
  names `["isDimmed","isDimmed"]`, values `["true", "false"]`.
- `SaveButtonUITests.testTapLogsActionFetchAndStateWriteInOrder` — scenario
  `SaveButton`: `userNameLabel` starts `"anonymous"`; tap `saveDraftButton` →
  label becomes `"Error fetching user"`; names
  `["onSave","getUserName","userName"]`, values
  `["draft", "42", "Error fetching user"]`.
- `DragCardUITests.testDragUpdatesGestureStateAndResetsOnRelease` — scenario
  `DragCard`: `maxLabel`/`currentLabel` start `"max 0"`/`"current 0"`; from
  `dragBox`'s center coordinate, `press(forDuration: 0.2, thenDragTo:
  start.withOffset(CGVector(dx: 120, dy: 80)))`; then `currentLabel` returns
  to `"current 0"` (release reset) and `maxLabel` is no longer `"max 0"`.
  Values are timing-dependent — behavior asserts only, no log snapshot.
- `TrickyDragCardUITests.testCustomResetClosureFiresWhenGestureEnds` —
  scenario `TrickyDragCard`: `trickyResetsLabel` starts `"resets 0"`; drag
  from `trickyDragBox`'s center by `(80, -40)` (same press/drag call) →
  `"resets 1"`; names `["resetsSeen"]`, values `["1"]`.
- `FocusFieldUITests.testTappingFieldFocusesAndToggleButtonUnfocuses` —
  scenario `FocusField`: `focusStatusLabel` starts `"unfocused"`; tap
  `focusTextField` → `"focused"`; tap `toggleFocusButton` → `"unfocused"`;
  names `["toggleCount"]`, values `["1"]` — one tap verified both ways, the
  machinery live, the storage by log.
