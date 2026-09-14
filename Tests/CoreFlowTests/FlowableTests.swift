import CoreFlow
import Testing

@Flowable
struct FlowablePoint: Equatable {
    var x: Int
    var y: Int
}

@Flowable
struct FlowableLabel: Equatable {
    var text: String
}

struct FlowableTests {
    @Test func generatedInitFactoryAndInFlowAgree() {
        let byInit = FlowablePoint(x: 1, y: 2)
        let byFactory = FlowablePoint.makeFlow((1, 2))
        let inFlow: FlowablePoint.InFlow = (x: 1, y: 2)
        #expect(byInit == byFactory)
        #expect(FlowablePoint.makeFlow(inFlow) == byInit)
    }

    @Test func singleFieldCollapsesToTheBareValue() {
        #expect(FlowableLabel.makeFlow("a") == FlowableLabel(text: "a"))
        let inFlow: FlowableLabel.InFlow = "a"
        #expect(FlowableLabel.makeFlow(inFlow) == FlowableLabel(text: "a"))
    }
}
