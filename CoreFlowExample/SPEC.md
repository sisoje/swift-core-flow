# CoreFlowExample — regeneration spec

The Swift sources of this example are deliberately collapsed into this spec;
regenerate them from the contracts below — `sh generate.sh` does it headlessly
via the claude CLI. `project.yml`, `test.sh`, and `generate.sh` are kept
verbatim next to this file and are part of the spec (targets, schemes, build
settings, the no-lldb-attach note, and the test/generate invocations live
there). Verify a regeneration with `sh test.sh` in this directory.

The spec assumes the `@Shell` mapping where `@State` substitutes to
`@TestState private` on `Core` (Core owns and logs its own state; the field is
sealed, out of the memberwise init, host's inline default required),
`@AppStorage`/`@SceneStorage` → `@Binding` (external storage is an injected
dependency; keys dropped), `@Query` → `@QueryCore` (fetched array as a bare
init parameter), `@Binding` copied verbatim (the mock vehicle itself), and
unknown wrappers (`@GestureState`, `@FocusState`) copied verbatim with their
attribute arguments.

## What this example is

The production shape: one SPM library holding ALL the components, consumed
by two thin app targets. The reading-list trio and the five tricky-wrapper
components (`@GestureState(reset:)`, `@FocusState`, a `ViewModifier` host,
an async throwing action) live side by side in the library, one file per
component — host, scenario, `#Preview { TheScenario() }`. Only what the
real app consumes is `public` (with `@Flowable` for the cross-module init):
`AddBookField`, `BookList`, and the `Book` model. Everything else — `BookRow`
(composed only inside `BookList`'s body), the five tricky hosts, every
scenario, every `Core` — is internal, reached by the test app via
`@testable import`. Scenario structs are named `<Component>Scenario`, except
`AddBookField`'s, which is `AddBookScenario`.

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
  CoreFlowExampleUI/
    Package.swift
    Sources/CoreFlowExampleUI/ Book.swift, BookRow.swift, AddBookField.swift,
                               BookList.swift, DragCard.swift,
                               TrickyDragCard.swift, FocusField.swift,
                               DimmerDemo.swift, SaveButton.swift
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
String`, `public var author: String`, `public var isFavorite = false`, and a
`public init(title:author:isFavorite:)` whose `isFavorite` defaults to `false`.

## BookRow.swift — a @Binding host

The favorite is NOT row-owned state — `Book` owns it, persisted — so the row
receives a channel: `@Binding`, caller-supplied, copied verbatim onto `Core`.

```swift
@Shell
struct BookRow: View {
    let title: String
    let author: String
    @Binding var isFavorite: Bool
}
```

Body: an `HStack` of a leading-aligned `VStack` — `Text(title)` (identifier
`bookTitle`) over `Text(author)` in `.caption`/`.secondary` — then `Spacer()`,
then `Button(isFavorite ? "★" : "☆") { isFavorite.toggle() }` (identifier
`favoriteButton`); `.padding(.horizontal)` on the stack.

Scenario (internal, as all scenarios): `@TestState private var isFavorite = false`,
body `BookRow.Core(title: "Dune", author: "Herbert", isFavorite: $isFavorite)`
— the use-site backing for a genuine `@Binding` parameter. Plus
`#Preview { BookRowScenario() }` (every scenario file has one).

## AddBookField.swift — own state, logged by Core itself

Text entry: the draft title is view-owned `@State` (→ `@TestState private` on
`Core`, so every keystroke logs at the write site); submitting hands the title
to the caller and clears the field.

```swift
@Flowable
@Shell
public struct AddBookField: View {
    @State private var title = ""
    let onSubmit: (String) -> Void
    public var body: some View { ... }
}
```

Body: `HStack` of `TextField("Title", text: $title)` with
`.autocorrectionDisabled()`, `.textInputAutocapitalization(.never)` (both
matter — the UI test types literal text and pins exact log values), identifier
`titleField`; and `Button("Add") { onSubmit(title); title = "" }`, identifier
`addButton`; `.padding(.horizontal)`.

Scenario: `@TestAction private var onSubmit: (String) -> Void = { _ in }` only — the
`@State` substitution needs no backing, `Core` owns and logs it:
`AddBookField.Core(onSubmit: onSubmit)`.

## BookList.swift — the SwiftData screen

`@Query` → `@QueryCore` on `Core`, so a scenario hands the fetched array in
directly — no `ModelContainer` anywhere in the tests — and `@AppStorage` →
`@Binding`, external storage injected. Deleting is the caller's business,
passed in as an action.

```swift
@Flowable
@Shell
public struct BookList: View {
    @Query private var books: [Book]
    @AppStorage("sortByAuthor") private var sortByAuthor = false
    let onDelete: (String) -> Void
    public var body: some View { ... }
}
```

Body: `VStack` of `Toggle("Sort by author", isOn: $sortByAuthor)`
(`.padding(.horizontal)`, identifier `sortToggle`) and a `List` whose local
`shown` is `books` sorted by `author` when `sortByAuthor` else by `title`;
`ForEach(shown)` binds `@Bindable var book = book` and rows an `HStack` of
`BookRow(title: book.title, author: book.author, isFavorite: $book.isFavorite)`
— the HOST, not its `Core`: production code composes components, `Core` is a
test seam — and `Button("Delete") { onDelete(book.title) }` with identifier
`delete-\(book.title)`.

Scenario: `@TestState private var sortByAuthor = false`, `@TestAction private var onDelete:
(String) -> Void = { _ in }`, body constructing `BookList.Core` with `books:`
of exactly Dune/Herbert then Anathem/Stephenson, `sortByAuthor:
$sortByAuthor`, `onDelete: onDelete`.

## RealApp/RealApp.swift

The REAL app: normal import, public hosts running their own live wrappers —
`@Query` fetches from the real container, `@AppStorage` persists the sort. The
closures are where data flow leaves the components: `@main struct
CoreFlowRealApp: App` with `WindowGroup { ContentView() }` and
`.modelContainer(for: Book.self)`. `ContentView` reads `@Environment(\.modelContext)`
and stacks `AddBookField(onSubmit:)` — inserting `Book(title: $0, author:
"Unknown")` — over `BookList(onDelete:)` — `try? context.delete(model:
Book.self, where: #Predicate { $0.title == title })`.

## TestApp/TestApp.swift

`import CoreFlow`, `@testable import CoreFlowExampleUI`.

- `enum Scenario: String` — cases `bookRow = "BookRow"`, `bookList =
  "BookList"`, `addBook = "AddBook"`, `dragCard = "DragCard"`,
  `trickyDragCard = "TrickyDragCard"`, `focusField = "FocusField"`,
  `dimmer = "Dimmer"`, `saveButton = "SaveButton"`; `static var
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

## FocusField.swift — machinery vs external storage, one host

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

## UITests

`LaunchHelper.swift`: `@MainActor func launchApp(scenario: String) ->
XCUIApplication` setting `launchEnvironment["SCENARIO"]` before `launch()` —
the app is a separate process and inherits nothing from the shell that
invoked xcodebuild (verified directly); every test states its scenario
explicitly. An `XCUIApplication` extension adds `var log: XCUIElement {
otherElements["log"] }` and `var logValues: [String]` JSON-decoding
`log.value`. Tests wait on names — `log.wait(for: \.label, toEqual:)`, the
finish line AND the names assertion — then `XCTAssertEqual` on `logValues`.
Every wait (`waitForExistence`, `wait(for:toEqual:)`) uses `timeout: 5`.
All test methods `@MainActor`, on plain `XCTestCase` (no MainActor default in
this target — see project.yml).

- `BookRowUITests.testFavoriteTogglesAndLogsEachWrite` — scenario `BookRow`:
  `favoriteButton` starts `"☆"`; tap → `"★"`, tap → `"☆"` (each awaited);
  names `["isFavorite","isFavorite"]`, values `["true", "false"]`.
- `AddBookUITests.testTypingSubmittingAndClearingAllLogInOrder` — scenario
  `AddBook`: tap `titleField`, `typeText("Dune")`, tap `addButton`. The log
  pins TextField's REAL binding behavior: it writes TWICE per keystroke plus
  two initial `""` writes on focus — pinned as-is; the submit hands the full
  title to the action, the clear is the final write. Names: ten `"title"`,
  then `"onSubmit"`, then `"title"`. Values:
  `["", "", "D", "D", "Du", "Du", "Dun", "Dun", "Dune", "Dune", "Dune", ""]`.
- `BookListUITests.testSortWritesStorageAndDeleteLogsTheTitle` — scenario
  `BookList`: first `bookTitle` static text is `"Anathem"` (title sort); tap
  the switch inside `sortToggle` (`app.switches["sortToggle"].switches
  .firstMatch`) → first becomes `"Dune"` (author sort); tap `delete-Anathem`;
  names `["sortByAuthor","onDelete"]`, values `["true", "Anathem"]`.
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
