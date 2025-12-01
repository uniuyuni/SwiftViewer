import SwiftUI

struct InspectorToggleKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct UpdateCatalogKey: FocusedValueKey {
    typealias Value = () -> Void
}

public extension FocusedValues {
    var toggleInspector: (() -> Void)? {
        get { self[InspectorToggleKey.self] }
        set { self[InspectorToggleKey.self] = newValue }
    }
    
    var updateCatalog: (() -> Void)? {
        get { self[UpdateCatalogKey.self] }
        set { self[UpdateCatalogKey.self] = newValue }
    }
}
