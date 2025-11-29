import SwiftUI

struct InspectorToggleKey: FocusedValueKey {
    typealias Value = () -> Void
}

public extension FocusedValues {
    var toggleInspector: (() -> Void)? {
        get { self[InspectorToggleKey.self] }
        set { self[InspectorToggleKey.self] = newValue }
    }
}
