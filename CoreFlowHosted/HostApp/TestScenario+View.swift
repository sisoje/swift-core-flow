import SwiftUI

extension TestScenario: View {
    var body: some View {
        switch self {
        case .queryViewGated: QueryViewSortScenario(gated: true)
        case .queryViewUngated: QueryViewSortScenario(gated: false)
        case .mockQueryResults: MockQueryResultsScenario()
        case .queryViewSectionedLive: QueryViewSectionedScenario(mocked: false)
        case .queryViewSectionedMocked: QueryViewSectionedScenario(mocked: true)
        case .queryViewInsert: QueryViewInsertScenario()
        case .flowUp: FlowUpScenario()
        case .flowUpThrows: FlowUpThrowsScenario()
        case .unstructuredTask: UnstructuredTaskScenario()
        case .shellCore: ShellCoreScenario()
        case .testState: TestStateScenario()
        case .testAction: TestActionScenario()
        case .testFocusState: TestFocusStateScenario()
        case .testAccessibilityFocusState: TestAccessibilityFocusStateScenario()
        case .gestureState: GestureStateScenario()
        case .viewModifierCore: ViewModifierCoreScenario()
        }
    }
}
