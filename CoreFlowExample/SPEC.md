# CoreFlowExample — regeneration spec

The Swift sources of this example are deliberately collapsed into this spec;
regenerate them from the contracts below — `sh generate.sh` does it headlessly
via the claude CLI (deleting every generated `.swift` first, so files an
older spec created can't linger). `project.yml`, `test.sh`, `generate.sh`,
and `.gitignore` (ignoring the generated sources) are kept
verbatim next to this file and are part of the spec (targets, schemes, build
settings, the no-lldb-attach note, and the test/generate invocations live
there). Verify a regeneration with `sh test.sh` in this directory.

The spec assumes the `@Shell` mapping where `@State` substitutes to
`@TestState private` on `Core` (Core owns and logs its own state; the field is
sealed, out of the memberwise init, host's inline default required),
`@FocusState` → `@TestFocusState private` (a REAL `FocusState` peer
underneath — hosted behavior stays live; programmatic writes log, while
`$name` remains the real `FocusState<T>.Binding`, so SYSTEM focus moves
through it don't), `@AppStorage`/`@SceneStorage` → `@Binding` (external
storage is an injected
dependency; keys dropped), and unknown wrappers (`@GestureState`,
`@Environment`) copied verbatim with their attribute arguments — an
`@Environment` copy reads whatever the scenario installs with
`.environment(...)`, the environment's own mocking story.

## What this example is

The production shape: one SPM library holding ALL the components, consumed
by two thin app targets. The reading-list set (the pair, their composed
screen, and the store capability) and the six tricky-wrapper
components (plain `@GestureState`, `@GestureState(reset:)`, `@FocusState`,
a `ViewModifier` host, an async throwing action, an `@UnstructuredTask`
slot) live side by side in the
library, one file per component — host, scenario,
`#Preview { TheScenario() }` (`BookStore.swift` being the one non-component
file). Only what the
real app consumes is `public`: the composed `ReadingListScreen` (with
`@Flowable` for the cross-module init), the
`Book` model (hand-written init), and the `BookStore` capability with its
public `\.bookStore` entry — the package defines the seam, the app supplies
the live implementation. Everything else — `AddBookField` and `BookList`
(composed only inside `ReadingListScreen`), the six tricky hosts, every
scenario, every `Core` — is internal, reached by the test app via
`@testable import`. Scenario structs are named `<Component>Scenario`, except
`AddBookField`'s (`AddBookScenario`) and `ReadingListScreen`'s
(`ReadingListScenario`).

- `CoreFlowExampleUI` — SPM library; hosts + internal scenarios/Cores.
- `RealApp` → `CoreFlowRealApp` scheme: plain `import CoreFlowExampleUI`, the
  public reading-list hosts with live wrappers (real SwiftData container,
  real `@AppStorage`).
- `TestApp` → `CoreFlowTestApp` scheme: one file — `@testable import
  CoreFlowExampleUI` reaches the internal scenarios, selected per launch via
  the `SCENARIO` env var; hosts the accessibility log element.
- `UITests` — XCUITests against the test app, one suite per component (eight).

## Layout

```
CoreFlowExample/
  project.yml                  (kept)
  test.sh                      (kept)
  generate.sh                  (kept)
  .gitignore                   (kept)
  CoreFlowExampleUI/
    Package.swift
    Sources/CoreFlowExampleUI/ Book.swift, BookStore.swift,
                               AddBookField.swift, BookList.swift,
                               ReadingListScreen.swift, DragCard.swift,
                               TrickyDragCard.swift, FocusField.swift,
                               DimmerDemo.swift, SaveButton.swift,
                               DownloadButton.swift
  RealApp/RealApp.swift
  TestApp/TestApp.swift
  UITests/                     LaunchHelper.swift, one file per suite
```

## CoreFlowExampleUI/Package.swift

swift-tools-version 6.0, platform `.iOS(.v17)`, one library product/target
`CoreFlowExampleUI` depending on `.product(name: "CoreFlow", package: "CoreFlow")`
with `.package(name: "CoreFlow", path: "../..")`.

## Book.swift

`import SwiftData`. `@Model public final class Book` with `public var title:
String` and a `public init(title:)`. Plus `extension Book:
CustomStringConvertible { public var description: String { title } }` —
action payloads log via `String(describing:)`, and the title is the readable
identity, keeping log snapshots pinnable where a bare class description
wouldn't be.

## BookStore.swift — the DB capability

The DB service as data: a struct of closures — mocked by construction, no
protocol. Public with a public `@Entry`: the package defines the seam and
its no-op default; the LIVE implementation belongs to the consuming app,
next to the SwiftData it wires (see RealApp below).

```swift
@Flowable
public struct BookStore: Equatable {
    var insert: (Book) -> Void
    var delete: (Book) -> Void

    public static func == (lhs: BookStore, rhs: BookStore) -> Bool { true }
}
```

`@Flowable` supplies the public cross-module memberwise init (`@Flowable`
on a plain non-View struct; the closure parameters get `@escaping`).
Always-equal `Equatable`, deliberately: a seam installed once — closure
fields can't compare, and invalidating every dependent on each render would
misreport a value that never meaningfully changes (same argument as
CoreFlow's own `testLog` entry).

`extension EnvironmentValues { @Entry public var bookStore = BookStore(
insert: { _ in }, delete: { _ in }) }` — no-op default: components render
without a store; the app's injector or a scenario's logging mock supplies
the real one. Not a component — no scenario, no `#Preview`.

## AddBookField.swift — own state, logged by Core itself

Text entry: the draft title is view-owned `@State` (→ `@TestState private` on
`Core`, so every keystroke logs at the write site); submitting inserts
through the `\.bookStore` capability and clears the field.

```swift
@Shell
struct AddBookField: View {
    @State private var title = ""
    @Environment(\.bookStore) private var bookStore: BookStore
    var body: some View { ... }
}
```

Body: `HStack` of `TextField("Title", text: $title)` with
`.autocorrectionDisabled()`, `.textInputAutocapitalization(.never)` (both
matter — the UI test types literal text and pins exact log values), identifier
`titleField`; and `Button("Add") { bookStore.insert(Book(title: title));
title = "" }` with
`.disabled(title.isEmpty)` (an empty title adds a blank, delete-hostile row),
identifier `addButton`; `.padding(.horizontal)`.

Scenario: `@TestAction private var insert: (Book) -> Void = { _ in }` and
`@TestAction private var delete: (Book) -> Void = { _ in }` — the `@State`
substitution needs no backing, `Core` owns and logs it; body
`AddBookField.Core()` with `.environment(\.bookStore, BookStore(insert:
insert, delete: delete))` — the WHOLE store is logging mocks (`delete` too,
though this component never deletes: an unexpected call must poison the log
snapshot, not vanish into an inert stub), installed on `Core`, whose copied
`@Environment` reads it.

## BookList.swift — the SwiftData screen

`@AppStorage` → `@Binding` on `Core`, external storage injected. The books
come through `QueryView`: the body builds a real `Query` dynamically —
sorting is the QUERY's job, and toggling the flag makes a new query — and
the content consumes a `QueryResult`. Mocking is a seeded in-memory
`ModelContainer`: the REAL query runs, so the sort assertions exercise the
query's own `order:`. Deleting goes through the `\.bookStore` capability.

```swift
@Shell
struct BookList: View {
    @AppStorage("sortDescending") private var sortDescending = false
    @Environment(\.bookStore) private var bookStore: BookStore
    var body: some View { ... }
}
```

Body: `VStack` of `Toggle("Sort Z–A", isOn: $sortDescending)`
(`.padding(.horizontal)`, identifier `sortToggle`) and
`QueryView(index: sortDescending, query: Query(sort: \Book.title, order:
sortDescending ? .reverse : .forward)) { $books in ... }` whose content is
a `List` of `ForEach(books)`, rows an `HStack` of
`Text(book.title)` (identifier `bookTitle`), `Spacer()`, and `Button("Delete") {
bookStore.delete(book) }` with identifier `delete-\(book.title)` — the model
object itself, not its title: titles aren't unique, deletion is by identity.

Scenario: `@TestState private var sortDescending = false`, `@TestAction private var insert:
(Book) -> Void = { _ in }`, `@TestAction private var delete:
(Book) -> Void = { _ in }`. Body constructs
`BookList.Core(sortDescending: $sortDescending)` with
`.environment(\.bookStore, BookStore(insert: insert, delete: delete))` —
the whole store logging mocks, same rationale as `AddBookScenario`'s — and
`.modelContainer(for: Book.self, inMemory: true)` whose `onSetup` inserts
`Book(title: "Dune")` then `Book(title: "Anathem")` into the container's
`mainContext` (under `MainActor.assumeIsolated`; `try!` the result — a mock
failing has no recovery). The real query fetches and sorts them, so
toggling the flag exercises the query's own `order:` — the store mock only
logs deletes, it does not remove rows.

## ReadingListScreen.swift — the composed screen

The public pair stacked — pure composition, no state of its own,
`@Flowable` for the public cross-module `init()`, `@Shell` for the `Core`
twin; the `\.bookStore` capability comes from whoever hosts it. Body:
`VStack { AddBookField(); BookList() }`. Not a component-tested host — the
children are, no suite. Scenario: bare `ReadingListScreen.Core()`, exactly
like `DragCardScenario` — the host takes nothing from callers, so the
scenario adds nothing; the children's `\.bookStore` reads fall back to the
entry's no-op default, `BookList`'s `QueryView` hosts its containerless
real `Query` (renders empty, no crash),
and the composed `Core` hosts with NO `ModelContainer`.
`#Preview { ReadingListScenario() }`. A preview must
never construct `ReadingListScreen()` directly: `#Preview` is itself a
macro expansion and can't reference the `@Flowable`-generated init (the
cross-expansion rule; the generated init also suppresses the compiler's
implicit one, leaving `#Preview` no accessible initializer at all — hit
live); the scenario is ordinary source, so hosting `Core` there is the
uniform escape.

## RealApp/RealApp.swift

The REAL app: normal import, the composed screen with live wrappers —
`@Query` fetches from the real container, `@AppStorage` persists the sort:
`@main struct CoreFlowRealApp: App` with `WindowGroup {
ReadingListScreen().liveBookStore() }` and `.modelContainer(for:
Book.self)`. The injector lives HERE, next to the SwiftData it wires: an
internal `LiveBookStore: ViewModifier` reading
`@Environment(\.modelContext)` and setting `.environment(\.bookStore,
BookStore(insert: { context.insert($0) }, delete: { context.delete($0) }))`
on `content`, plus an internal `extension View { func liveBookStore() }`
wrapping `modifier(LiveBookStore())`. The live store's `context.delete($0)`
takes the row's own model object, so exactly the tapped book dies, and the
context registers the change so `@Query` refreshes. Two dead ends, both
observed live: predicate-matching by title deleted every same-titled
duplicate in one tap, and the batch `delete(model:where:)` doesn't register
changes in the context, so rows stayed until relaunch.

## TestApp/TestApp.swift

`import CoreFlow`, `@testable import CoreFlowExampleUI`.

- `enum Scenario: String` — cases `bookList = "BookList"`, `addBook =
  "AddBook"`, `readingList = "ReadingList"`, `dragCard = "DragCard"`,
  `trickyDragCard = "TrickyDragCard"`, `focusField = "FocusField"`,
  `dimmer = "Dimmer"`, `saveButton = "SaveButton"`, `downloadButton =
  "DownloadButton"`; `static var
  defaultScenario` is `.bookList` (used when `SCENARIO` is unset, so Cmd-R
  just works).
- `@main struct CoreFlowTestApp: App`: `init()` reads
  `ProcessInfo.processInfo.environment["SCENARIO"]`, falls back to
  `defaultScenario`, `fatalError`s on an unknown value.
- `@State private var logItems: [(String, String)] = []`. The scenario
  `switch` sits in a `Group` carrying the log element — names JSON in label,
  values JSON in value, read by the UI tests:

```swift
.accessibilityElement(children: .contain)
.accessibilityIdentifier("log")
.accessibilityLabel(logNamesJSON)
.accessibilityValue(logValuesJSON)
.testLog { property, value in logItems.append((property, value)) }
```

`logNamesJSON`/`logValuesJSON` are `JSONEncoder().encode` of
`logItems.map(\.0)`/`\.1` as UTF-8 strings.

## DragCard.swift — live @GestureState

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

## TrickyDragCard.swift — argument-carrying @GestureState

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

## FocusField.swift — the property logs, the projection wires

`@FocusState` → `@TestFocusState` on `Core`, demonstrated on both channels
in one host: tapping the field moves the OS's REAL focus (the system writes
through the real `FocusState.Binding` — status label changes, NO log line),
while the toggle button's programmatic write goes through the substituted
setter and logs. `@AppStorage` is EXTERNAL storage, a dependency: `Core`
takes it as a `@Binding` the scenario backs and logs.

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

Scenario: `@TestState private var toggleCount = 0`, body
`FocusField.Core(toggleCount: $toggleCount)`.

## DimmerDemo.swift — the ViewModifier host

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

## SaveButton.swift — async throwing action

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
@TestAction private var onSave: (String) -> Void = { _ in }
@TestAction private var getUserName: @Sendable (_ id: String) async throws -> String = { _ in
    throw CancellationError()
}
```

body: `SaveButton.Core(onSave: onSave, getUserName: getUserName)`.

## DownloadButton.swift — the @UnstructuredTask slot

`@UnstructuredTask` under `@Shell` rides the verbatim rule and re-expands on
`Core`: the twin cancels and logs identically. Assigning logs
`("download","task")`, clearing logs `("download","nil")` and the box's
`willSet` cancels the live task — observed, not assumed: the cancelled
task's sleep returns early and its resumption writes Core's own logged
state, strictly after the clearing write (cancellation happens inside the
button action; the resumption is scheduled later on the main actor), so the
log order is deterministic.

```swift
@Shell
struct DownloadButton: View {
    @UnstructuredTask private var download: Task<Void, Never>?
    @State private var cancelsSeen = 0
}
```

Body: `VStack(spacing: 16)` of `Text(download == nil ? "idle" :
"downloading")` (`downloadStatusLabel` — the slot's storage is
`@Observable`, so the body re-renders on task change), `Text("cancels
\(cancelsSeen)")` (`cancelsLabel`), `Button("Start") { download = Task {
try? await Task.sleep(for: .seconds(600)); if Task.isCancelled {
cancelsSeen += 1 } } }` (`startDownloadButton`), and `Button("Cancel") {
download = nil }` (`cancelDownloadButton`).

Scenario: bare `DownloadButton.Core()` — nothing to wire.

## UITests

`LaunchHelper.swift`: `@MainActor func launchApp(scenario: String) ->
XCUIApplication` setting `launchEnvironment["SCENARIO"]` before `launch()` —
the app is a separate process and inherits nothing from the shell that
invoked xcodebuild (verified directly); every test states its scenario
explicitly. An `XCUIApplication` extension adds `var log: XCUIElement {
otherElements["log"] }` and `var logValues: [String]` JSON-decoding
`log.value` (empty array when the value is missing or undecodable). An
`XCUIElement` extension adds the one shared wait every suite uses:

```swift
@discardableResult
func wait<Value: Equatable>(
    for keyPath: KeyPath<XCUIElement, Value>,
    toEqual expected: Value,
    timeout: TimeInterval
) -> Bool
```

an `XCTNSPredicateExpectation` comparing `element[keyPath: keyPath] ==
expected`, waited with `XCTWaiter()`. Tests wait on names —
`log.wait(for: \.label, toEqual:)`, the
finish line AND the names assertion — then `XCTAssertEqual` on `logValues`.
Every wait (`waitForExistence`, `wait(for:toEqual:)`) uses `timeout: 5`.
All test methods `@MainActor`, on plain `XCTestCase` (no MainActor default in
this target — see project.yml).

- `AddBookUITests.testTypingSubmittingAndClearingAllLogInOrder` — scenario
  `AddBook`: tap `titleField`, `typeText("Dune")`, tap `addButton`. The log
  pins TextField's REAL binding behavior: it writes TWICE per keystroke plus
  two initial `""` writes on focus — pinned as-is; the insert hands the
  built `Book` (logging as its title) to the store, the clear is the final
  write. Names: ten `"title"`,
  then `"insert"`, then `"title"`. Values:
  `["", "", "D", "D", "Du", "Du", "Dun", "Dun", "Dune", "Dune", "Dune", ""]`.
- `BookListUITests.testSortWritesStorageAndDeleteLogsTheTitle` — scenario
  `BookList`: first `bookTitle` static text is `"Anathem"` (A–Z sort); tap
  the switch inside `sortToggle` (`app.switches["sortToggle"].switches
  .firstMatch`) → first becomes `"Dune"` (Z–A sort); tap `delete-Anathem`;
  names `["sortDescending","delete"]`, values `["true", "Anathem"]` — the
  `Book` payload logs via its `description`, the title.
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
  `DragCard`: `maxLabel`/`currentLabel` start `"max 0"`/`"current 0"`; the
  box is an `otherElements` match (`app.otherElements["dragBox"]` — an
  identified shape is not a `staticText`); from its center coordinate
  (`coordinate(withNormalizedOffset:)` at 0.5/0.5), `press(forDuration:
  0.2, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 80)))`; then
  `currentLabel` returns to `"current 0"` (release reset) and `maxLabel` is
  no longer `"max 0"`. Values are timing-dependent — behavior asserts only,
  no log snapshot.
- `TrickyDragCardUITests.testCustomResetClosureFiresWhenGestureEnds` —
  scenario `TrickyDragCard`: `trickyResetsLabel` starts `"resets 0"`; drag
  from `trickyDragBox`'s center by `(80, -40)` (same element lookup and
  press/drag call) → `"resets 1"`; names `["resetsSeen"]`, values `["1"]`.
- `DownloadButtonUITests.testStartThenCancelLogsSlotAndObservedCancellation`
  — scenario `DownloadButton`: `downloadStatusLabel` starts `"idle"`,
  `cancelsLabel` `"cancels 0"`; tap `startDownloadButton` →
  `"downloading"`; tap `cancelDownloadButton` → `"idle"` and `"cancels 1"`;
  names `["download","download","cancelsSeen"]`, values
  `["task","nil","1"]`.
- `FocusFieldUITests.testTappingFieldFocusesAndToggleButtonUnfocuses` —
  scenario `FocusField`: `focusStatusLabel` starts `"unfocused"`; tap
  `focusTextField` → `"focused"` AND the log names are still the encoded
  empty array (`"[]"` — the system moved focus through the real binding,
  nothing logged); tap `toggleFocusButton` → `"unfocused"`; names
  `["isFocused","toggleCount"]`, values `["false","1"]` — the programmatic
  write logs, the system one didn't: the property logs, the projection
  wires.
