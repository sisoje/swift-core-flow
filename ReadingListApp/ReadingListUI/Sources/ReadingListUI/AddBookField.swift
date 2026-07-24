import CoreFlow
import SwiftUI

// Text entry: the draft title is view-owned @State (→ @Binding on Core, so
// every keystroke logs at the write site), submitting hands the title to the
// caller and clears the field.
@Flowable
@Shell
public struct AddBookField: View {
    @State private var title: String = ""
    let onSubmit: (String) -> Void

    public var body: some View {
        HStack {
            TextField("Title", text: $title)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("titleField")
            Button("Add") {
                onSubmit(title)
                title = ""
            }
            .accessibilityIdentifier("addButton")
        }
        .padding(.horizontal)
    }
}

struct AddBookScenario: View {
    @TestState var title = ""
    @TestAction var onSubmit: (String) -> Void = { _ in }

    var body: some View {
        AddBookField.Core(title: $title, onSubmit: onSubmit)
    }
}

#Preview {
    AddBookScenario()
}
