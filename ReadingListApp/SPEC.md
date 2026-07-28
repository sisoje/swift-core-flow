# ReadingListApp — regeneration spec

The Swift sources of this example are deliberately collapsed into this spec;
regenerate them from the contracts below. `project.yml` and `test.sh` are kept
verbatim next to this file and are part of the spec (targets, schemes, build
settings, and the test invocation live there). Verify a regeneration with
`sh test.sh` in this directory.

The spec assumes the `@Shell` mapping where `@State` substitutes to
`@TestState private` on `Core` (Core owns and logs its own state; the field is
sealed, out of the memberwise init, host's inline default required),
`@AppStorage`/`@SceneStorage` → `@Binding` (external storage is an injected
dependency; keys dropped), `@Query` → `@QueryCore` (fetched array as a bare
init parameter), and `@Binding` copied verbatim (the mock vehicle itself).

## What this example is

The production shape, unlike ExampleApp's one-app-many-scenarios: a real SPM
library of `@Flowable @Shell` components consumed by two thin app targets.

- `ReadingListUI` — SPM library; public hosts, internal scenarios/Cores.
- `RealApp` → `ReadingList` scheme: plain `import ReadingListUI`, live wrappers
  (real SwiftData container, real `@AppStorage`).
- `TestApp` → `ReadingListTestApp` scheme: `@testable import ReadingListUI`
  reaches the internal scenarios, selected per launch via the `SCENARIO` env
  var; hosts the accessibility log element.
- `UITests` — XCUITests against the test app, one suite per component.

## Layout

```
ReadingListApp/
  project.yml                  (kept)
  test.sh                      (kept)
  ReadingListUI/
    Package.swift
    Sources/ReadingListUI/     Book.swift, BookRow.swift, AddBookField.swift,
                               BookList.swift
  RealApp/RealApp.swift
  TestApp/TestApp.swift
  UITests/                     LaunchHelper.swift, BookRowUITests.swift,
                               AddBookUITests.swift, BookListUITests.swift
```

## ReadingListUI/Package.swift

swift-tools-version 6.0, platform `.iOS(.v17)`, one library product/target
`ReadingListUI` depending on `.product(name: "CoreFlow", package: "CoreFlow")`
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

Scenario (internal, as all scenarios): `@TestState var isFavorite = false`,
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

Scenario: `@TestAction var onSubmit: (String) -> Void = { _ in }` only — the
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

Scenario: `@TestState var sortByAuthor = false`, `@TestAction var onDelete:
(String) -> Void = { _ in }`, body constructing `BookList.Core` with `books:`
of exactly Dune/Herbert then Anathem/Stephenson, `sortByAuthor:
$sortByAuthor`, `onDelete: onDelete`.

## RealApp/RealApp.swift

The REAL app: normal import, public hosts running their own live wrappers —
`@Query` fetches from the real container, `@AppStorage` persists the sort. The
closures are where data flow leaves the components: `@main struct
ReadingListApp: App` with `WindowGroup { ContentView() }` and
`.modelContainer(for: Book.self)`. `ContentView` reads `@Environment(\.modelContext)`
and stacks `AddBookField(onSubmit:)` — inserting `Book(title: $0, author:
"Unknown")` — over `BookList(onDelete:)` — `try? context.delete(model:
Book.self, where: #Predicate { $0.title == title })`.

## TestApp/TestApp.swift

`import CoreFlow`, `@testable import ReadingListUI`.

- `enum Scenario: String` — cases `bookRow = "BookRow"`, `bookList =
  "BookList"`, `addBook = "AddBook"`; `static var defaultScenario` is
  `.bookList` (used when `SCENARIO` is unset, so Cmd-R just works).
- `@main struct ReadingListTestApp: App`: `init()` reads
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

## UITests

`LaunchHelper.swift`: `@MainActor func launchApp(scenario: String) ->
XCUIApplication` setting `launchEnvironment["SCENARIO"]` before `launch()`;
an `XCUIApplication` extension with `var log: XCUIElement {
otherElements["log"] }` and `var logValues: [String]` JSON-decoding
`log.value`. Tests wait on names — `log.wait(for: \.label, toEqual:)`, the
finish line AND the names assertion — then `XCTAssertEqual` on `logValues`.
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
