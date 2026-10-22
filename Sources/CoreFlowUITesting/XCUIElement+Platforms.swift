import XCTest

public extension XCUIElement {
    var valueOrLabel: String {
        #if os(macOS)
            value as? String ?? ""
        #else
            label
        #endif
    }

    /// macOS: `click()` can miss a button a centre click hits. Catalyst: `tap()`
    /// sends nothing. iPhone: `click()` fails, "Pointer events are not supported".
    func tapOrClick() {
        #if os(macOS)
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #elseif targetEnvironment(macCatalyst)
            click()
        #elseif os(tvOS)
            XCTFail("tvOS has no tap; move focus with XCUIRemote and press select")
        #else
            tap()
        #endif
    }
}

public extension XCUIApplication {
    /// iOS and Catalyst: the control is a switch inside the labeled switch.
    func switchOrCheckBox(_ identifier: String) -> XCUIElement {
        #if os(macOS)
            checkBoxes[identifier]
        #elseif os(visionOS)
            switches[identifier]
        #else
            switches[identifier].switches.firstMatch
        #endif
    }
}

#if !os(tvOS)
    public extension XCUICoordinate {
        func pressOrClick(forDuration duration: TimeInterval, thenDragTo other: XCUICoordinate) {
            #if os(macOS) || targetEnvironment(macCatalyst)
                click(forDuration: duration, thenDragTo: other)
            #else
                press(forDuration: duration, thenDragTo: other)
            #endif
        }
    }
#endif
