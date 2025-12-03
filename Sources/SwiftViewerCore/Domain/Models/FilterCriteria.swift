import Foundation

struct FilterCriteria: Codable {
    var minRating: Int = 0
    var colorLabel: String?
    var showImages: Bool = true
    var showVideos: Bool = true
    var searchText: String = ""
    var showOnlyFavorites: Bool = false
    var flagFilter: FlagFilter = .all
    
    enum FlagFilter: String, CaseIterable, Codable {
        case all = "All"
        case flagged = "Flagged"  // Pick or Reject
        case unflagged = "Unflagged"  // No flag
        case pick = "Pick"  // flagStatus == 1
        case reject = "Reject"  // flagStatus == -1
    }
    
    // Metadata filters (Multi-selection)
    var selectedMakers: Set<String> = []
    var selectedCameras: Set<String> = []
    var selectedLenses: Set<String> = []
    var selectedISOs: Set<String> = []
    var selectedDates: Set<String> = []
    var selectedFileTypes: Set<String> = []
    var selectedShutterSpeeds: Set<String> = []
    var selectedApertures: Set<String> = []
    var selectedFocalLengths: Set<String> = []
    
    // Visible columns configuration
    var visibleColumns: [MetadataType] = [.date, .maker, .camera, .lens, .iso]
    
    enum MetadataType: String, CaseIterable, Identifiable, Codable { // Added Codable here too for completeness, though String raw value makes it implicit
        case date = "Date"
        case fileType = "File Type"
        case maker = "Maker"
        case camera = "Model"
        case lens = "Lens"
        case iso = "ISO"
        case shutterSpeed = "Shutter"
        case aperture = "Aperture"
        case focalLength = "Focal Length"
        
        var id: String { rawValue }
    }
    
    var isActive: Bool {
        minRating > 0 || colorLabel != nil || !showImages || !showVideos || !searchText.isEmpty ||
        !selectedCameras.isEmpty || !selectedLenses.isEmpty || !selectedISOs.isEmpty ||
        !selectedDates.isEmpty || !selectedFileTypes.isEmpty || !selectedShutterSpeeds.isEmpty ||
        !selectedApertures.isEmpty || !selectedFocalLengths.isEmpty ||
        showOnlyFavorites || flagFilter != .all
    }
}
