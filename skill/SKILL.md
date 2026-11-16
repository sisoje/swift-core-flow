---
name: swift-core-flow
description: >
  Adopting swift-core-flow inside the hypermodular method: the @Shell cut
  that generates a testable Core, @TestState and @TestAction logging at
  the write site, QueryView, @QueryResult, LazyQuery and @LazyQueries for
  SwiftData, scenarios, the HostApp test host, and the CoreFlowUITesting
  bundle that asserts the execution log. Use when writing or reviewing
  code that mentions @Shell, Core, @TestState, @TestAction, @TestLog,
  QueryView, @QueryResult, LazyQuery, @LazyQueries, QueryUtilities,
  HostApp, uiTestLog, logElement, or when adding swift-core-flow to a
  package or an Xcode project. The README beside this file is the
  per-macro reference. The data-coupling skill in sisoje/hypermodular is
  the doctrine this mechanizes.
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
.package(url: "https://github.com/sisoje/swift-core-flow.git", from: "1.3.0"),
.product(name: "CoreFlow", package: "swift-core-flow"),            // the app and the test host
.product(name: "CoreFlowUITestHost", package: "swift-core-flow"),  // the test host only
.product(name: "CoreFlowUITesting", package: "swift-core-flow"),   // the UI-test bundle only
```

With a path dependency, `.package(path: "../CoreFlow")`, the package
name in `.product(name:package:)` is the directory's, `CoreFlow`, not
`swift-core-flow`. In an Xcode project the app target links `CoreFlow`, or `AppCore`,
the package that does, the test host
links the same and `CoreFlowUITestHost`, the UI-test bundle links
`CoreFlowUITesting`. `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` goes on
the app and the test host and not on the UI-test bundle; in a package the
same is `swiftSettings: [.defaultIsolation(MainActor.self)]` on the
library as well, or a contract's async closure trips a sending error
at the call. The first build compiles
swift-syntax and takes minutes once.

Inside the hypermodular layout one package lists the library, the
data coupling layer, and it re-exports it with `@_exported import
CoreFlow`. `AppCore` re-exports the layer the same way.
A feature file then sees the layer and the macros and imports neither
by name, and a dependency that imports the layer has the macros too.

## The rule, the macro

| Rule in the data-coupling skill | Here |
|---|---|
| the cut, with own state logging at the write site | `@Shell` generates `Core`; `@TestState`, `@TestAction`, `@TestFocusState`, `@TestEnvironment` |
| the scenario as a hosted UI test | `HostApp<Scenario>`, `uiTestLog()`, `CoreFlowUITesting` |
| `@Query` as input: one shell owns the live query, content reads plain data | `QueryView` with `dependencies:`, `@QueryResult`, `.mockQuery` |
| a value derived from inputs, kept across renders, not `@State(wrappedValue:)` in an `init` | `MemoView` with `dependencies:`; a changed dependency replaces the whole value, so state that is to survive a change of the input stays out of it; a value the build reads and `dependencies:` leaves out is not followed |
| work an event starts is a task the node holds, not a `Task` nobody holds; it cancels on replacement and on node removal | `@UnstructuredTask`; each assignment logs under the property's name with the value `task`, and the block declares it; a child that starts the work is handed `$download`, and its write cancels and logs the same; inside the task, write state through a `$binding` taken into the capture list, not through `self` |
| capabilities: hand a consumer only the operations it needs, as a tuple | `@Capability` over a type or an extension |
| slices: a tuple of the fields a node reads, from one or more sources | `#pick(from:)` |
| the memberwise `init` a data package needs public, and construction inputs as a tuple | `@Flowable` generates `init`, `InFlow`, `makeFlow(_:)` |
| events up the tree and one closure back down the environment | `@FlowUp` with `.collectFlow` and `.onFlow`; in a package the declaration is `@FlowUp public var`, in an extension that is not itself marked `public`; the rule is general: when the event or the data behind a modifier comes from outside the app, the node that carries the modifier is a shell, whether or not a test could fake the source; `.onOpenURL`, `.onContinueUserActivity`, and `.onChange(of: scenePhase)` are examples; declare a flow, keep the system's modifier as one line in a root modifier that calls the flow, write the handling as a view that listens with `.onFlow`, and give its scenario a control that calls the flow |

## The cut

`@Shell` goes on a node that has a live wrapper. Whether a view is cut
with it or by hand is judged per view, as the work goes, and neither is
the default. The macro was made for a view that already exists. One
attribute makes a legacy screen testable with nothing rewritten, so a
project gains tests one view at a time. It is also the practical cut
wherever the state and the `body` that uses it are tested together, in
one log. A new screen modeled from the design is a core written by
hand, which owns no wrapper and is not cut, and the shell written
above it carries `@Shell` when the shell itself is to be tested. The
two cuts mix and cascade, a `@Shell` node above a hand-written core, a
hand-written core whose child is another `@Shell` node. The data-coupling
skill's `references/shell-core.md`, "When to split", has the cases.
The macro generates a nested,
internal `Core` with the same `body`, substituting the wrappers it knows
and copying everything else verbatim: `@State` becomes `@TestState`,
`@SceneStorage` becomes `@Binding` (`@AppStorage` too, though the method
keeps it at the root, which is not cut), `@Query` becomes
`@QueryResult`, `@FocusState` becomes `@TestFocusState`, `\.dismiss` and
`\.openURL` become `@TestEnvironment`, which logs the call under its
own name, `dismiss`, then runs the real action, so the log proves that
the node asked to be dismissed. A scenario constructs
`Node.Core(...)` through the memberwise initializer, which takes the
copied `let`s, a `Binding` where the host had `@AppStorage` or
`@SceneStorage`, and a bare array where it had `@Query`. A `@TestState`
is `@State` that logs, with `@State`'s own rules, so the Core's private
ones are out of the init and keep their defaults.

- Mapped wrappers are private on the host and carry an explicit type,
  `@State private var street: String = ""`, or the macro
  rejects them. A `@State` carries an inline default too, an optional
  included, `@State private var streetError: String? = nil`, since the
  macro copies the default onto `Core`. `@Environment` properties
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
  plain closure. The rules do not move down with it. A form's node owns
  one `String` per field and one `String?` error per field as
  `@State`, loose, not a model and not an errors struct, and
  assembles the model only when Save hands it on; it intercepts each
  field's binding
  to store the text and write the error. The fields view is a core
  written by hand, read off the screen, a `@Binding` per field, a `let`
  per error label, a closure per button. It does not decide whether a
  field is wrong, and what the design says the screen does with an
  error it was handed is its own logic.
- A view made only of `let`s, bindings, environment reads, and closures
  is already a core, a core read off the screen included. `@Shell` adds
  nothing to it; the scenario constructs the node itself, and
  `#Preview` may construct it directly with literals.

## Transformers

A view is the runtime's node. Its capability is `body`, fixed by the
protocol, and the runtime is what calls it. A transformer is our node.
The runtime does not know it and keeps nothing for it, so its
capability has no protocol to fix it and has to be declared.
`@Capability` declares it.

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
`Query` init reads. A value it reads and the list leaves out is a
change the query does not follow, and the list goes stale with no
error. `.mockQuery(QueryResult(wrappedValue: [dune]))` on
a subtree hands its `QueryView`s canned results. A `@Model` class
carries what SwiftData gives it and nothing added. The integration
test of a query seeds a real in-memory container with literals,
`.modelContainer(for:inMemory:) { try! $0.get().mainContext.insert(…) }`,
lets the shell's `QueryView` run, and logs the delivered order from a
user action, a snapshot button calling `log("books",
"\(books.map(\.title))")`, so the real sort is asserted at the shell's
edge and not from the render schedule. The query expression is a
static function on the shell, `Library.query(sortByAuthor:)`, so the
test runs the very expression the shell runs; the shell's own wiring of
it into its `QueryView` is read, not tested, since the delivered array
is inside the node and no contract line exposes it.

A query asked from a service has no list to forget. The contract is a
struct under `@LazyQueries` whose members answer a `LazyQuery`, `var
books: (_ sortByAuthor: Bool) -> LazyQuery<Book, [Book]>`, each written
once. The macro writes the initializer, which takes each member's plain
query expression, and `defaultQueries`, the service whose every member
answers `Query()`. The environment entry defaults to it, `@Entry var
queries = Queries.defaultQueries`. The store writes each expression once,
`Queries(books: { sortByAuthor in Query(sort: …) })`, and the shell
writes `QueryView(queries.books(sortByAuthor)) { $books in … }`. Whoever
provides the arguments gets the dependencies back for free, since the
arguments are the dependencies. Calling the member builds nothing, and
the query is built when an argument changes. A `LazyQuery` cannot be
opened or built by hand, so a query does not travel without the values
it was built from. Every stored property of the service is such a
member, and anything else is a compile error. A sectioned query names
its section and so has no default, and a service that holds one gets the
initializer without `defaultQueries`. The contract's file imports
SwiftData and SwiftUI, since the generated code names `Query`.
`.mockQuery` and a seeded container work the same as under
`QueryView(query:dependencies:)`.

## Scenario

One per core, with the app, not under `#if DEBUG`. A scenario is a
file of its own beside the view it stages, and the `#Preview` that
shows it is in the view's file. A view that holds
the boundaries, `@TestState private var sortByAuthor = false` for a
binding the host takes, typed by its annotation or by a bare `Bool`,
`Int`, or `String` literal and annotated otherwise, `@TestAction private var onDelete: (Book) ->
Void = { _ in }` for a closure, constructs the core from literals, sets its contracts with
`.environment(...)`, and is shown by a `#Preview` in the view's file. A `@Shell` node is
previewed only through its scenario, since `#Preview` cannot name the
generated `Core` and the host owns live state. The scenario's givens
are its parameters. A given that would have to set the core's own state says
the truth is above the core; it is a `@TestState` on the scenario,
handed down as a binding, and a different given is another scenario
or another parameter, since a scenario is cheap.

```swift
struct LibraryScenario: View {
    @TestState private var sortByAuthor = false
    @TestAction private var deleteBook: (Book) -> Void = { _ in }

    var body: some View {
        Library.Core(books: [Book(title: "Dune", author: "Herbert")],
                     sortByAuthor: $sortByAuthor)
            .environment(\.dbService, DbService(deleteBook: deleteBook))
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
A child with `@Query` is handed `.mockQuery`.

A closure of a contract is a `@TestAction` too. That is what the
wrapper was made for, so that no scenario writes a logger by hand. The
scenario declares it with the stub's answer as its default and hands
it to the contract.

```swift
struct AddressScreenScenario: View {
    @TestAction private var save: (Address) throws -> String = { _ in "/tmp/address.json" }

    var body: some View {
        AddressScreen.Core()
            .environment(\.addressService, AddressService(save: save))
    }
}
```

The call logs under the property's name, `save`, with the description
of its argument, and the test asserts that description, or the part of
it the criterion names. No scenario formats a payload so that the log
reads like the evidence block. This is what a scenario does not hold:

```swift
.environment(\.addressService, AddressService(save: { address in
    log("save", "\(address.street), \(address.city), \(address.postalCode), \(address.country)")
    return "/tmp/address.json"
}))
```

A subscription is stubbed the same way. Its `@TestAction` default
returns a stream that yields the events the block gives and then
finishes, so the call logs once and each event arrives as the system's
stimulus.

A default cannot read a scenario's parameter. A different answer, a
save that throws, is another scenario with another default, and a
scenario is cheap. `@TestLog` is the seam the wrappers are built on.
A scenario reaches for it only where no wrapper can carry the
boundary, and then not on a boundary a wrapper already logs.

## Host

`TestScenario` is a `nonisolated enum TestScenario: Codable` with one
case per scenario; `nonisolated` because a UI-test bundle has no
main-actor default and has to decode it. In an Xcode project it lives in
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
on the case and returns the app. Drive with `tapOrClick()` and
`pressOrClick(forDuration:thenDragTo:)` on an element, and
`app.switchOrCheckBox(_:)` on the app, which takes the identifier and
returns the element, one spelling for every destination. Then wait for the names and assert:

```swift
let names = ["sortByAuthor", "deleteBook"]
let log = app.logElement
XCTAssertTrue(log.waitUntil(\.label, equals: String(decoding: try JSONEncoder().encode(names), as: UTF8.self), timeout: 10))
XCTAssertEqual(log.logNames, names)
XCTAssertEqual(log.logValues.first, "true")
```

The names whole and in order. A value is asserted where it can be
read, the flag here. A model logs as its type name, so its entry is
asserted by its name alone.
`waitUntil` takes any key path of the element whose value is
`Equatable`, so a test can wait on `\.label`, on `\.value`, or on a
count. A block that ends in a silence has nothing more to wait for.
The test waits for the names the block does expect and then compares
the whole log, so an entry that should not be there fails it. Where
the criterion names no order, both sides are sorted by name and then
by value before they are compared.
Nothing is read off the screen after the log. The README's known issues hold: tap or click, not both; a
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
  to an array next to `@TestState`, a `log("save", ...)` call written
  inside a contract's closure where a `@TestAction` could be handed in,
  or `@TestLog` beside `@TestAction` on the same boundary. Each is a
  second spelling of a seam the wrappers already are.
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
