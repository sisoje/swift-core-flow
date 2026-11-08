You are evaluating whether a library-adoption skill is understandable. Read `skill/SKILL.md` in full first. Read `README.md` only when the skill points you there for a question. Do not read anything else, and do not edit any file.

Then answer these questions, from the skill only, in your own words, two to four sentences each. Where you can, cite the line of the skill you relied on.

1. A view declares `@State private var isExpanded = false`, `@AppStorage("fav") private var fav = false`, `@Query private var books: [Book]`, `let title: String`, and `@Environment(\.dbService) private var dbService: DbService`. What does `@Shell` generate for each on `Core`, and what does a scenario pass to `Core`'s initializer?
2. A search screen cut with `@Shell` has a text field. Where does the text the user is still typing live, and why?
3. `@TestAction private var save: (Book) -> Void` is called with a `Book` titled Dune. What does the log record for names and for values, what does the test assert, and how does a test author get `Dune` rather than the model's description?
4. In an Xcode project with an app, a test host, and a UI-test bundle, which target links which product, and where does `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` go?
5. What is `TestScenario`, where does it live, and what is the test host's whole `main.swift`?
6. A UI test taps a toggle right after a fresh build and the toggle's write is missing from the log once. What does the skill say to do?

Then one design task. A `Favorites` node lists `@Query` books and stars one through a `favorites` environment contract with a `setStarred: (Book, Bool) -> Void` closure. Cut it with `@Shell`. Write the host struct, the scenario, the `TestScenario` case, and the UI test for "starring Dune persists the star", asserting the names array exactly and the values as you see fit. Keep it under 60 lines of Swift. No hand-written logging where a macro logs.

Finally, list every place where the skill was unclear, contradictory, or where you had to guess, with the line number. Be specific: quote the sentence and say what confused you. If nothing confused you, say so. Report the answers, the code, and the list as your final message.
