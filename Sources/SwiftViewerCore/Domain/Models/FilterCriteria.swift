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
        !selectedMakers.isEmpty || !selectedCameras.isEmpty || !selectedLenses.isEmpty || !selectedISOs.isEmpty ||
        !selectedDates.isEmpty || !selectedFileTypes.isEmpty || !selectedShutterSpeeds.isEmpty ||
        showOnlyFavorites || flagFilter != .all
    }
    
    // MARK: - Codable Implementation with Default Fallback for new properties
    
    init() {} // Default init needed explicitly if we have custom init(from:)

    init(minRating: Int = 0, colorLabel: String? = nil) {
        self.minRating = minRating
        self.colorLabel = colorLabel
    }
    
    mutating func resetSelections() {
        // Reset Filter Values
        minRating = 0
        colorLabel = nil
        searchText = ""
        showOnlyFavorites = false
        flagFilter = .all
        
        selectedMakers.removeAll()
        selectedCameras.removeAll()
        selectedLenses.removeAll()
        selectedISOs.removeAll()
        selectedDates.removeAll()
        selectedFileTypes.removeAll()
        selectedShutterSpeeds.removeAll()
        selectedApertures.removeAll()
        selectedFocalLengths.removeAll()
        
        // PRESERVE: visibleColumns, showImages, showVideos
    }
    
    enum CodingKeys: String, CodingKey {
        case minRating, colorLabel, showImages, showVideos, searchText, showOnlyFavorites, flagFilter
        case selectedMakers, selectedCameras, selectedLenses, selectedISOs, selectedDates, selectedFileTypes, selectedShutterSpeeds, selectedApertures, selectedFocalLengths
        case visibleColumns
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        minRating = try container.decodeIfPresent(Int.self, forKey: .minRating) ?? 0
        colorLabel = try container.decodeIfPresent(String.self, forKey: .colorLabel)
        showImages = try container.decodeIfPresent(Bool.self, forKey: .showImages) ?? true
        showVideos = try container.decodeIfPresent(Bool.self, forKey: .showVideos) ?? true
        searchText = try container.decodeIfPresent(String.self, forKey: .searchText) ?? ""
        showOnlyFavorites = try container.decodeIfPresent(Bool.self, forKey: .showOnlyFavorites) ?? false
        flagFilter = try container.decodeIfPresent(FlagFilter.self, forKey: .flagFilter) ?? .all
        
        selectedMakers = try container.decodeIfPresent(Set<String>.self, forKey: .selectedMakers) ?? []
        selectedCameras = try container.decodeIfPresent(Set<String>.self, forKey: .selectedCameras) ?? []
        selectedLenses = try container.decodeIfPresent(Set<String>.self, forKey: .selectedLenses) ?? []
        selectedISOs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedISOs) ?? []
        selectedDates = try container.decodeIfPresent(Set<String>.self, forKey: .selectedDates) ?? []
        selectedFileTypes = try container.decodeIfPresent(Set<String>.self, forKey: .selectedFileTypes) ?? []
        selectedShutterSpeeds = try container.decodeIfPresent(Set<String>.self, forKey: .selectedShutterSpeeds) ?? []
        selectedApertures = try container.decodeIfPresent(Set<String>.self, forKey: .selectedApertures) ?? []
        selectedFocalLengths = try container.decodeIfPresent(Set<String>.self, forKey: .selectedFocalLengths) ?? []
        
        visibleColumns = try container.decodeIfPresent([MetadataType].self, forKey: .visibleColumns) ?? [.date, .maker, .camera, .lens, .iso]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minRating, forKey: .minRating)
        try container.encodeIfPresent(colorLabel, forKey: .colorLabel)
        try container.encode(showImages, forKey: .showImages)
        try container.encode(showVideos, forKey: .showVideos)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(showOnlyFavorites, forKey: .showOnlyFavorites)
        try container.encode(flagFilter, forKey: .flagFilter)
        
        try container.encode(selectedMakers, forKey: .selectedMakers)
        try container.encode(selectedCameras, forKey: .selectedCameras)
        try container.encode(selectedLenses, forKey: .selectedLenses)
        try container.encode(selectedISOs, forKey: .selectedISOs)
        try container.encode(selectedDates, forKey: .selectedDates)
        try container.encode(selectedFileTypes, forKey: .selectedFileTypes)
        try container.encode(selectedShutterSpeeds, forKey: .selectedShutterSpeeds)
        try container.encode(selectedApertures, forKey: .selectedApertures)
        try container.encode(selectedFocalLengths, forKey: .selectedFocalLengths)
        
        try container.encode(visibleColumns, forKey: .visibleColumns)
    }
}
