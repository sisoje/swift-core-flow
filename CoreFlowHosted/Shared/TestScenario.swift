/// Every hosted scenario the app can show, one case per scenario view.
nonisolated enum TestScenario: Codable {
    case queryViewGated
    case queryViewUngated
    case mockQueryResults
    case queryViewSectionedLive
    case queryViewSectionedMocked
    case queryViewInsert
    case flowUp
    case flowUpThrows
    case unstructuredTask
    case shellCore
    case testState
    case testAction
    case testFocusState
    case focusBinding
    case testAccessibilityFocusState
    case testEnvironment
    case gestureState
    case viewModifierCore
}
