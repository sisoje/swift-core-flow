import CoreFlow
import Testing

@Capability
final class CapabilityCounter {
    var count = 0
    var doubled: Int {
        count * 2
    }

    func label() -> String {
        "n=\(count)"
    }
}

struct CapabilityTests {
    @Test func computedValuesFreezeAtCaptureMethodsStayLive() {
        let counter = CapabilityCounter()
        let cached = counter.capability
        counter.count = 1
        #expect(cached.doubled == 0)
        #expect(counter.capability.doubled == 2)
        #expect(cached.label() == "n=1")
    }
}
