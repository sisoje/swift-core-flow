import CoreFlow
import Testing

// Real, compiled usage of Reflector — not a macro, so no assertMacroExpansion here,
// same reasoning as EndToEndTests: exercise the actual runtime behavior.

private struct Coordinates {
    let x: Int
    let y: Int
    let label: String
}

private struct SingleField {
    let value: Int
}

@Flowable
struct Point {
    var x: Int
    var y: Int
}

struct ReflectorTests {
    @Test func fieldNamesListsAStructsStoredPropertiesInDeclarationOrder() {
        #expect(Reflector.fieldNames(of: Coordinates.self) == ["x", "y", "label"])
    }

    @Test func fieldNamesOnASingleFieldStructStillReturnsOneName() {
        #expect(Reflector.fieldNames(of: SingleField.self) == ["value"])
    }

    @Test func fieldNamesOnALabeledTupleReturnsItsLabels() {
        #expect(Reflector.fieldNames(of: (x: Int, y: Int).self) == ["x", "y"])
    }

    @Test func fieldNamesOnAnUnlabeledTupleReturnsPositionalLabels() {
        // No real field names to report — Mirror falls back to ".0", ".1", …
        #expect(Reflector.fieldNames(of: (Int, Int).self) == [".0", ".1"])
    }

    @Test func fieldNamesPairsWithInFlowToNameAnInFlowsFields() {
        // Needs only the *type* — the generated labeled tuple's real field
        // names, without ever constructing a `Point`.
        #expect(Reflector.fieldNames(of: Point.InFlow.self) == ["x", "y"])
    }
}
