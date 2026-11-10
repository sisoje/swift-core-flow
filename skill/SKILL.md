---
name: swift-core-flow
description: >
  Adopting swift-core-flow inside the hypermodular method: the @Shell cut
  that generates a testable Core, @TestState and @TestAction logging at
  the write site, QueryView and @QueryResult for SwiftData, scenarios,
  the HostApp test host, and the CoreFlowUITesting bundle that asserts
  the execution log. Use when writing or reviewing code that mentions
  @Shell, Core, @TestState, @TestAction, @TestLog, QueryView,
  @QueryResult, HostApp, uiTestLog, logElement, or when adding
  swift-core-flow to a package or an Xcode project. The README beside
  this file is the per-macro reference. The data-coupling skill in
  sisoje/hypermodular is the doctrine this mechanizes.
---

# swift-core-flow: the method, mechanized

The data-coupling skill says how a SwiftUI node is written, cut into
shell and core, and tested by its execution log. This library does the
cut and the log as macros. `@Shell` generates the core, the test
wrappers log every write and call at the site, `HostApp` renders a
scenario, and `CoreFlowUITesting` asserts the log. The README is the
API. This file is the order of work and what the README does not say.

## Install

```swift
// swift-tools-version: 6.4
.package(url: "https://github.com/sisoje/swift-core-flow.git", from: "1.2.1"),
.product(name: "CoreFlow", package: "swift-core-flow"),            // the app and the test host
.product(name: "CoreFlowUITestHost", package: "swift-core-flow"),  // the test host only
.product(name: "CoreFlowUITesting", package: "swift-core-flow"),   // the UI-test bundle only
```

With a path dependency, `.package(path: "../CoreFlow")`, the package
name in `.product(name:package:)` is the directory's, `CoreFlow`, not
`swift-core-flow`. In an Xcode project the app target links `CoreFlow`, or the features
package that does, the test host
links `CoreFlow` and `CoreFlowUITestHost`, the UI-test bundle links
`CoreFlowUITesting`. `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` goes on
the app and the test host and never on the UI-test bundle; in a package the
same is `swiftSettings: [.defaultIsolation(MainActor.self)]` on the
library as well, or a contract's async closure trips a sending error
at the call. The first build compiles
swift-syntax and takes minutes once.

## The rule, the macro

| Rule in the data-coupling skill | Here |
|---|---|
| the cut, with own state logging at the write site | `@Shell` generates `Core`; `@TestState`, `@TestAction`, `@TestFocusState`, `@TestEnvironment` |
| the scenario as a hosted UI test | `HostApp<Scenario>`, `uiTestLog()`, `CoreFlowUITesting` |
| `@Query` as input: one shell owns the live query, content reads plain data | `QueryView` with `dependencies:`, `@QueryResult`, `.mockQuery` |
| a value derived from inputs, kept across renders, never `@State(wrappedValue:)` in an `init` | `MemoView` |
| work an event starts is a task the node holds, never a `Task` nobody holds; it cancels on replacement and on node removal | `@UnstructuredTask`; each assignment logs under the property's name with the value `task`, and the block declares it; a child that starts the work is handed `$download`, and its write cancels and logs the same; inside the task, write state through a `$binding` taken into the capture list, never through `self` |
| capabilities: hand a consumer only the operations it needs, as a tuple | `@Capability` over a type or an extension |
| slices: a tuple of the fields a node reads, from one or more sources | `#pick(from:)` |
| the memberwise `init` a data package needs public, and construction inputs as a tuple | `@Flowable` generates `init`, `InFlow`, `makeFlow(_:)` |
| events up the tree and one closure back down the environment | `@FlowUp` with `.collectFlow` and `.onFlow` |

## The cut

`@Shell` goes on a node that has a live wrapper. Whether a view is cut
with it or by hand is judged per view, as the work goes, and neither is
the default. The macro was made for a view that already exists. One
attribute makes a legacy screen testable with nothing rewritten, so a
project gains tests one view at a time. It is also the practical cut
wherever the state and the `body` that uses it are tested together, in
one log. A new screen modeled from the design is a core written by
hand, which owns no wrapper and is never cut, and the shell written
above it carries `@Shell` when the shell itself is to be tested. The
two cuts mix and cascade, a `@Shell` node above a hand-written core, a
hand-written core whose child is another `@Shell` node. The data-coupling
skill's `references/shell-core.md`, "When to split", has the cases.
The macro generates a nested,
internal `Core` with the same `body`, substituting the wrappers it knows
and copying everything else verbatim: `@State` becomes `@TestState`,
`@SceneStorage` becomes `@Binding` (`@AppStorage` too, though the method
keeps it at the root, which is never cut), `@Query` becomes
`@QueryResult`, `@FocusState` becomes `@TestFocusState`, `\.dismiss` and
`\.openURL` become `@TestEnvironment`, which logs the call under its
own name, `dismiss`, then runs the real action, so a test asserts that
the sheet really closed by its log. A scenario constructs
`Node.Core(...)` through the memberwise initializer, which takes the
copied `let`s, a `Binding` where the host had `@AppStorage` or
`@SceneStorage`, and a bare array where it had `@Query`. A `@TestState`
is `@State` that logs, with `@State`'s own rules, so the Core's private
ones are out of the init and keep their defaults.

- Mapped wrappers are private on the host and carry an explicit type,
  `@State private var street: String = ""`, or the macro
  rejects them. `@Environment` properties
  are copied verbatim, the two sealed actions excepted, and carry an
  explicit type, `@Environment(\.dbService) private var dbService:
  DbService`, or the macro rejects them. The scenario sets them with
  `.environment(...)`; a contract it does not set runs its `@Entry`
  no-op. A contract is a struct of closures with no-op defaults and an
  `@Entry`, the data-coupling skill's layer.
- What the core owns is what its evidence declares. Every private
  `@State` logs, so a draft no criterion names, the text a field is
  still editing, lives below the core in a furniture view, a form or a
  row that is no node on the map, and hands the value back through a
  plain closure. The rules never move down with it. A form's node owns
  one `String` per field and one `String?` error per field as
  `@State`, loose, never a model and never an errors struct, and
  assembles the model only when Save hands it on; it intercepts each
  field's binding
  to store the text and write the error. The fields view is a core
  written by hand, read off the screen, a `@Binding` per field, a `let`
  per error label, a closure per button. It never decides whether a
  field is wrong, and what the design says the screen does with an
  error it was handed is its own logic.
- A view made only of `let`s, bindings, environment reads, and closures
  is already a core, a core read off the screen included. `@Shell` adds
  nothing to it; the scenario constructs the node itself, and
  `#Preview` may construct it directly with literals.

## Transformers

A transformer is a struct whose stored properties are `@Binding`s, the
node's raw state, and whose computed properties and methods are the
intercepted bindings and labels a view needs, a form's fields and their
errors, a `judge()` for Save. It holds no state, and a plain test
constructs it over local variables and writes through an output
binding. `@Capability` on it bundles every computed property and method
into one `Capability` tuple and a `capability` property, so the view is
handed `fields.capability`, the smart bindings and the labels as plain
values, and nothing else. Stored `@Binding`s are not collected, so a
label is a computed re-export, `streetMessage`, and an output binding
takes a name of its own, `streetField`. Computed properties need
explicit types, and the tuple is rebuilt on each `body`, so a label
read from it is current.

## SwiftData

On a `@Shell` node `@Query` becomes `@QueryResult` and the scenario
hands the array. When the query's sort or filter depends on state, the
shell owns a `QueryView(query:dependencies:) { $books in … }` and the
content reads plain data; `dependencies` are exactly the values the
`Query` init reads. `.mockQuery(QueryResult(wrappedValue: [dune]))` on
a subtree hands its `QueryView`s canned results. A `@Model` class
carries what SwiftData gives it and nothing added. The integration
test of a query seeds a real in-memory container with literals,
`.modelContainer(for:inMemory:) { try! $0.get().mainContext.insert(…) }`,
lets the shell's `QueryView` run, and logs the delivered order from a
user action, a snapshot button calling `log("books",
"\(books.map(\.title))")`, so the real sort is asserted at the shell's
edge and never from the render schedule. The query expression is a
static function on the shell, `Library.query(sortByAuthor:)`, so the
test runs the very expression the shell runs; the shell's own wiring of
it into its `QueryView` is read, not tested, since the delivered array
is inside the node and no contract line exposes it.

## Scenario

One per core, with the app, never under `#if DEBUG`. The preview
chain, the scenario and the `#Preview` that shows it, lives in one
file with the view that is there. A view that holds
the boundaries, `@TestState private var sortByAuthor = false` for a
binding the host takes, typed by its annotation or by a bare `Bool`,
`Int`, or `String` literal and annotated otherwise, `@TestAction private var onDelete: (Book) ->
Void = { _ in }` for a closure, `@TestLog` for a payload logged by
hand, constructs the core from literals, sets its contracts with
`.environment(...)`, and ends in `#Preview`. A `@Shell` node is
previewed only through its scenario, since `#Preview` cannot name the
generated `Core` and the host owns live state. The scenario's givens
are its parameters. A given that would have to set the core's own state says
the truth is above the core; it is a `@TestState` on the scenario,
handed down as a binding, and a different given is another scenario
or another parameter, since a scenario is cheap.

```swift
struct LibraryScenario: View {
    @TestState private var sortByAuthor = false
    @TestLog private var log

    var body: some View {
        Library.Core(books: [Book(title: "Dune", author: "Herbert")],
                     sortByAuthor: $sortByAuthor)
            .environment(\.dbService, DbService(deleteBook: { log("deleteBook", $0.title) }))
    }
}
```

The log is two arrays, names and values. `@TestState` and `@TestAction`
log `String(describing:)` of the value, a tuple for several arguments,
so an optional reads `Optional("cover")` and a model reads its
description. The names are the contract. A value is asserted as the
test's author sees fit. A scenario sets loggers for the node's own
boundaries. A child under it is the child's host, not its `Core`, so
its own state stays silent; it shares the environment, so a contract
both name logs the child's calls too; the block drives the node, no
deeper.
A child with `@Query` is handed `.mockQuery`. Where a payload needs the spelling the
criterion uses, a title and not a description, or where the logger
must read a scenario parameter, a given, the scenario logs that one
boundary with `@TestLog`, as above, instead of `@TestAction`. One
or the other per boundary, never both.

## Host

`TestScenario` is a `nonisolated enum TestScenario: Codable` with one
case per scenario; `nonisolated` because a UI-test bundle has no
main-actor default and must decode it. In an Xcode project it lives in
a `Shared/` folder compiled into both the host and the bundle, or in
the host target alone when there is no bundle, and the host target
adds `TestScenario+View.swift`, an `extension TestScenario: View` with
the switch. In a package, `Core` and the scenarios are
internal to the library, so the enum and its `View` conformance live
public in the library beside the scenarios, and the host target only
imports it. A UI-test bundle beside such a package links the same
library, next to `CoreFlowUITesting`, to name the cases it launches. Either way the host's whole `main.swift` is
`HostApp<TestScenario>.main()`.
The host renders the launched case under `uiTestLog()`, which exposes
the log as one accessibility element.

## UI test

One `@MainActor` test class per node, one test method per evidence
block, the log a hypermodular map declares for one acceptance
criterion. A criterion that names an effect, "persists the star", is
proven by the request leaving the node with the right payload; what
the contract does with it is its own boundary's test. `XCUIApplication.launch(TestScenario.library)` starts the host
on the case and returns the app. Drive with `tapOrClick()`,
`switchOrCheckBox(_:)`, `pressOrClick(forDuration:thenDragTo:)`, one
spelling for every destination. Then wait for the names and assert:

```swift
let names = ["sortByAuthor", "deleteBook"]
let log = app.logElement
XCTAssertTrue(log.waitUntil(\.label, equals: String(decoding: try JSONEncoder().encode(names), as: UTF8.self), timeout: 10))
XCTAssertEqual(log.logNames, names)
XCTAssertEqual(log.logValues, ["true", "Dune"])
```

The names whole and in order, the values as the author sees fit.
Nothing is read off the screen after the log. The README's known issues hold: tap or click, never both; a
synthesized drag can be dropped on a CI runner; Mac Catalyst frees a
removed view on the next event; a tap right after a fresh build may not
register once, the one known flake, so a failure that repeats on a
rerun is the real one; on macOS the log element's `label`, the
names array, is cut at 512 characters, so a block's log stays under
about sixty entries.

## Do not

Any rule here may be broken whenever breaking it saves time or is the
more practical thing to do.

- **Log by hand where a macro logs.** A `Binding(get:set:)` that appends
  to an array next to `@TestState`, or `@TestLog` beside `@TestAction`
  on the same boundary, is two spellings of one seam.
- **Keep a draft no criterion names in a `@Shell` core.** Its
  keystrokes become the node's evidence. Move it below the core. A
  form's fields, which its criteria name, stay in the core behind a
  transformer.
- **`@StateObject` or `@ObservedObject`.** Unmapped on purpose; nothing
  value-shaped to substitute.

## References

- `README.md` beside this file, the per-macro reference: Shell and its
  wrapper mapping, QueryView, TestState and TestAction, the testLog
  seam, known issues in hosted UI tests.
- `CoreFlowHosted/`, the package's own hosted suite, the layout to copy.
- [sisoje/hypermodular](https://github.com/sisoje/hypermodular),
  `data-coupling/SKILL.md` for the doctrine and `hypermodular/SKILL.md`
  for the maps whose evidence blocks these tests assert.
