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
    
    var isFullScreen: Bool? {
        get { self[IsFullScreenKey.self] }
        set { self[IsFullScreenKey.self] = newValue }
    }
}

struct IsFullScreenKey: FocusedValueKey {
    typealias Value = Bool
}

struct ToggleSubViewKey: FocusedValueKey {
    typealias Value = () -> Void
}

public extension FocusedValues {
    var toggleSubView: (() -> Void)? {
        get { self[ToggleSubViewKey.self] }
        set { self[ToggleSubViewKey.self] = newValue }
    }
}
