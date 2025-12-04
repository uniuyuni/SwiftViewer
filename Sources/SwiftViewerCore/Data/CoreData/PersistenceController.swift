import CoreData

import CoreData

public class PersistenceController {
    public static let shared = PersistenceController()

    public var container: NSPersistentContainer
    private var currentStoreURL: URL?

    public init(inMemory: Bool = false) {
        // ... (Model loading logic remains same, extracted to helper if possible but keeping inline for now)
        // We need to load the model from the package bundle
        // Try .momd first (model bundle)
        var modelURL = Bundle.module.url(forResource: "SwiftViewer", withExtension: "momd")
        
        // Try .mom (single model file)
        if modelURL == nil {
            modelURL = Bundle.module.url(forResource: "SwiftViewer", withExtension: "mom")
        }
        
        if modelURL == nil {
            // Fallback 1: Check for the specific resource bundle in the main bundle (App Bundle case)
            if let bundleURL = Bundle.main.url(forResource: "SwiftViewer_SwiftViewerCore", withExtension: "bundle"),
               let bundle = Bundle(url: bundleURL) {
                modelURL = bundle.url(forResource: "SwiftViewer", withExtension: "momd")
                if modelURL == nil {
                    modelURL = bundle.url(forResource: "SwiftViewer", withExtension: "mom")
                }
            }
        }
        
        if modelURL == nil {
            // Fallback 2: Check main bundle directly
            modelURL = Bundle.main.url(forResource: "SwiftViewer", withExtension: "momd")
            if modelURL == nil {
                modelURL = Bundle.main.url(forResource: "SwiftViewer", withExtension: "mom")
            }
        }
        
        if modelURL == nil {
            // Fallback 3: Check all bundles
            for bundle in Bundle.allBundles {
                if let url = bundle.url(forResource: "SwiftViewer", withExtension: "momd") {
                    modelURL = url
                    break
                }
                if let url = bundle.url(forResource: "SwiftViewer", withExtension: "mom") {
                    modelURL = url
                    break
                }
            }
        }
        
        var model: NSManagedObjectModel?
        if let finalModelURL = modelURL {
            model = NSManagedObjectModel(contentsOf: finalModelURL)
        }
        
        if model == nil {
            print("DEBUG: Failed to load model from file. Creating programmatic model.")
            model = PersistenceController.createProgrammaticModel()
        }
        
        guard let finalModel = model else {
            fatalError("Failed to create Core Data model")
        }

        container = NSPersistentContainer(name: "SwiftViewer", managedObjectModel: finalModel)
        
        // Default to in-memory store to avoid creating "SwiftViewer.sqlite" in Application Support
        // The user must explicitly open a catalog to persist data.
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        // Explicitly set URL to /dev/null to prevent any directory creation attempts
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    public func switchToCatalog(at url: URL) {
        // Save current context if needed
        if container.viewContext.hasChanges {
            try? container.viewContext.save()
        }
        
        // Create new container with same model
        let model = container.managedObjectModel
        let newContainer = NSPersistentContainer(name: "SwiftViewer", managedObjectModel: model)
        
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        newContainer.persistentStoreDescriptions = [description]
        
        newContainer.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Failed to load store at \(url): \(error)")
                // Fallback or error handling?
            }
        }
        
        newContainer.viewContext.automaticallyMergesChangesFromParent = true
        
        // Replace container
        self.container = newContainer
        self.currentStoreURL = url
        
        // Notify change
        NotificationCenter.default.post(name: .coreDataStackChanged, object: nil)
    }
    
    public var currentContext: NSManagedObjectContext {
        return container.viewContext
    }
    
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    private static func createProgrammaticModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // Entities
        let catalog = NSEntityDescription()
        catalog.name = "Catalog"
        catalog.managedObjectClassName = NSStringFromClass(Catalog.self)
        
        let mediaItem = NSEntityDescription()
        mediaItem.name = "MediaItem"
        mediaItem.managedObjectClassName = NSStringFromClass(MediaItem.self)
        
        let exifData = NSEntityDescription()
        exifData.name = "ExifData"
        exifData.managedObjectClassName = NSStringFromClass(ExifData.self)
        
        let collection = NSEntityDescription()
        collection.name = "Collection"
        collection.managedObjectClassName = NSStringFromClass(Collection.self)
        
        // Properties - Catalog
        let cat_id = NSAttributeDescription()
        cat_id.name = "id"
        cat_id.attributeType = .UUIDAttributeType
        cat_id.isOptional = true
        
        let cat_name = NSAttributeDescription()
        cat_name.name = "name"
        cat_name.attributeType = .stringAttributeType
        cat_name.isOptional = true
        
        let cat_created = NSAttributeDescription()
        cat_created.name = "createdDate"
        cat_created.attributeType = .dateAttributeType
        cat_created.isOptional = true
        
        let cat_modified = NSAttributeDescription()
        cat_modified.name = "modifiedDate"
        cat_modified.attributeType = .dateAttributeType
        cat_modified.isOptional = true
        
        let cat_color = NSAttributeDescription()
        cat_color.name = "color"
        cat_color.attributeType = .stringAttributeType
        cat_color.isOptional = true
        
        let cat_importing = NSAttributeDescription()
        cat_importing.name = "isImporting"
        cat_importing.attributeType = .booleanAttributeType
        cat_importing.defaultValue = false
        cat_importing.isOptional = false
        
        catalog.properties = [cat_id, cat_name, cat_created, cat_modified, cat_color, cat_importing]
        
        // Properties - MediaItem
        let mi_id = NSAttributeDescription()
        mi_id.name = "id"
        mi_id.attributeType = .UUIDAttributeType
        mi_id.isOptional = true
        
        let mi_path = NSAttributeDescription()
        mi_path.name = "originalPath"
        mi_path.attributeType = .stringAttributeType
        mi_path.isOptional = true
        
        let mi_name = NSAttributeDescription()
        mi_name.name = "fileName"
        mi_name.attributeType = .stringAttributeType
        mi_name.isOptional = true
        
        let mi_size = NSAttributeDescription()
        mi_size.name = "fileSize"
        mi_size.attributeType = .integer64AttributeType
        mi_size.defaultValue = 0
        mi_size.isOptional = false
        
        let mi_type = NSAttributeDescription()
        mi_type.name = "mediaType"
        mi_type.attributeType = .stringAttributeType
        mi_type.isOptional = true
        
        let mi_capture = NSAttributeDescription()
        mi_capture.name = "captureDate"
        mi_capture.attributeType = .dateAttributeType
        mi_capture.isOptional = true
        
        let mi_import = NSAttributeDescription()
        mi_import.name = "importDate"
        mi_import.attributeType = .dateAttributeType
        mi_import.isOptional = true
        
        let mi_mod = NSAttributeDescription()
        mi_mod.name = "modifiedDate"
        mi_mod.attributeType = .dateAttributeType
        mi_mod.isOptional = true
        
        let mi_rating = NSAttributeDescription()
        mi_rating.name = "rating"
        mi_rating.attributeType = .integer16AttributeType
        mi_rating.defaultValue = 0
        mi_rating.isOptional = false
        
        let mi_flag = NSAttributeDescription()
        mi_flag.name = "isFlagged"
        mi_flag.attributeType = .booleanAttributeType
        mi_flag.defaultValue = false
        mi_flag.isOptional = false
        
        let mi_color = NSAttributeDescription()
        mi_color.name = "colorLabel"
        mi_color.attributeType = .stringAttributeType
        mi_color.isOptional = true
        
        let mi_orient = NSAttributeDescription()
        mi_orient.name = "orientation"
        mi_orient.attributeType = .integer16AttributeType
        mi_orient.defaultValue = 1
        mi_orient.isOptional = false
        
        let mi_w = NSAttributeDescription()
        mi_w.name = "width"
        mi_w.attributeType = .integer32AttributeType
        mi_w.defaultValue = 0
        mi_w.isOptional = false
        
        let mi_h = NSAttributeDescription()
        mi_h.name = "height"
        mi_h.attributeType = .integer32AttributeType
        mi_h.defaultValue = 0
        mi_h.isOptional = false
        
        let mi_exists = NSAttributeDescription()
        mi_exists.name = "fileExists"
        mi_exists.attributeType = .booleanAttributeType
        mi_exists.defaultValue = true
        mi_exists.isOptional = false
        
        let mi_fav = NSAttributeDescription()
        mi_fav.name = "isFavorite"
        mi_fav.attributeType = .booleanAttributeType
        mi_fav.defaultValue = false
        mi_fav.isOptional = false
        
        let mi_flagStatus = NSAttributeDescription()
        mi_flagStatus.name = "flagStatus"
        mi_flagStatus.attributeType = .integer16AttributeType
        mi_flagStatus.defaultValue = 0
        mi_flagStatus.isOptional = false
        
        mediaItem.properties = [mi_id, mi_path, mi_name, mi_size, mi_type, mi_capture, mi_import, mi_mod, mi_rating, mi_flag, mi_color, mi_orient, mi_w, mi_h, mi_exists, mi_fav, mi_flagStatus]
        
        // Properties - ExifData
        let ed_id = NSAttributeDescription()
        ed_id.name = "id"
        ed_id.attributeType = .UUIDAttributeType
        ed_id.isOptional = true
        
        // ... (Simplified ExifData for now to avoid huge code block, add essential ones)
        let ed_make = NSAttributeDescription()
        ed_make.name = "cameraMake"
        ed_make.attributeType = .stringAttributeType
        ed_make.isOptional = true
        
        exifData.properties = [ed_id, ed_make]
        
        let ed_model = NSAttributeDescription()
        ed_model.name = "cameraModel"
        ed_model.attributeType = .stringAttributeType
        ed_model.isOptional = true
        exifData.properties.append(ed_model)
        
        let ed_lens = NSAttributeDescription()
        ed_lens.name = "lensModel"
        ed_lens.attributeType = .stringAttributeType
        ed_lens.isOptional = true
        exifData.properties.append(ed_lens)
        
        let ed_focal = NSAttributeDescription()
        ed_focal.name = "focalLength"
        ed_focal.attributeType = .doubleAttributeType
        ed_focal.isOptional = true
        exifData.properties.append(ed_focal)
        
        let ed_aperture = NSAttributeDescription()
        ed_aperture.name = "aperture"
        ed_aperture.attributeType = .doubleAttributeType
        ed_aperture.isOptional = true
        exifData.properties.append(ed_aperture)
        
        let ed_shutter = NSAttributeDescription()
        ed_shutter.name = "shutterSpeed"
        ed_shutter.attributeType = .stringAttributeType
        ed_shutter.isOptional = true
        exifData.properties.append(ed_shutter)
        
        let ed_iso = NSAttributeDescription()
        ed_iso.name = "iso"
        ed_iso.attributeType = .integer32AttributeType
        ed_iso.isOptional = true
        exifData.properties.append(ed_iso)
        
        let ed_date = NSAttributeDescription()
        ed_date.name = "dateTimeOriginal"
        ed_date.attributeType = .dateAttributeType
        ed_date.isOptional = true
        exifData.properties.append(ed_date)
        
        let ed_lat = NSAttributeDescription()
        ed_lat.name = "gpsLatitude"
        ed_lat.attributeType = .doubleAttributeType
        ed_lat.isOptional = true
        exifData.properties.append(ed_lat)
        
        let ed_brightnessValue = NSAttributeDescription()
        ed_brightnessValue.name = "brightnessValue"
        ed_brightnessValue.attributeType = .doubleAttributeType
        ed_brightnessValue.isOptional = true
        exifData.properties.append(ed_brightnessValue)

        let ed_exposureBias = NSAttributeDescription()
        ed_exposureBias.name = "exposureBias"
        ed_exposureBias.attributeType = .doubleAttributeType
        ed_exposureBias.isOptional = true
        exifData.properties.append(ed_exposureBias)

        let ed_serialNumber = NSAttributeDescription()
        ed_serialNumber.name = "serialNumber"
        ed_serialNumber.attributeType = .stringAttributeType
        ed_serialNumber.isOptional = true
        exifData.properties.append(ed_serialNumber)

        let ed_title = NSAttributeDescription()
        ed_title.name = "title"
        ed_title.attributeType = .stringAttributeType
        ed_title.isOptional = true
        exifData.properties.append(ed_title)

        let ed_caption = NSAttributeDescription()
        ed_caption.name = "caption"
        ed_caption.attributeType = .stringAttributeType
        ed_caption.isOptional = true
        exifData.properties.append(ed_caption)

        let ed_latitude = NSAttributeDescription()
        ed_latitude.name = "latitude"
        ed_latitude.attributeType = .doubleAttributeType
        ed_latitude.isOptional = true
        exifData.properties.append(ed_latitude)

        let ed_longitude = NSAttributeDescription()
        ed_longitude.name = "longitude"
        ed_longitude.attributeType = .doubleAttributeType
        ed_longitude.isOptional = true
        exifData.properties.append(ed_longitude)

        let ed_altitude = NSAttributeDescription()
        ed_altitude.name = "altitude"
        ed_altitude.attributeType = .doubleAttributeType
        ed_altitude.isOptional = true
        exifData.properties.append(ed_altitude)

        let ed_imageDirection = NSAttributeDescription()
        ed_imageDirection.name = "imageDirection"
        ed_imageDirection.attributeType = .doubleAttributeType
        ed_imageDirection.isOptional = true
        exifData.properties.append(ed_imageDirection)
        
        let ed_lon = NSAttributeDescription()
        ed_lon.name = "gpsLongitude"
        ed_lon.attributeType = .doubleAttributeType
        ed_lon.isOptional = true
        exifData.properties.append(ed_lon)
        
        let ed_copy = NSAttributeDescription()
        ed_copy.name = "copyright"
        ed_copy.attributeType = .stringAttributeType
        ed_copy.isOptional = true
        exifData.properties.append(ed_copy)
        
        let ed_artist = NSAttributeDescription()
        ed_artist.name = "artist"
        ed_artist.attributeType = .stringAttributeType
        ed_artist.isOptional = true
        exifData.properties.append(ed_artist)
        
        let ed_desc = NSAttributeDescription()
        ed_desc.name = "descriptionText"
        ed_desc.attributeType = .stringAttributeType
        ed_desc.isOptional = true
        exifData.properties.append(ed_desc)
        
        let ed_raw = NSAttributeDescription()
        ed_raw.name = "rawProps"
        ed_raw.attributeType = .binaryDataAttributeType
        ed_raw.isOptional = true
        exifData.properties.append(ed_raw)
        
        let ed_rating = NSAttributeDescription()
        ed_rating.name = "rating"
        ed_rating.attributeType = .integer16AttributeType
        ed_rating.isOptional = true
        exifData.properties.append(ed_rating)
        
        // NEW PROPERTIES
        let ed_software = NSAttributeDescription()
        ed_software.name = "software"
        ed_software.attributeType = .stringAttributeType
        ed_software.isOptional = true
        exifData.properties.append(ed_software)
        
        let ed_metering = NSAttributeDescription()
        ed_metering.name = "meteringMode"
        ed_metering.attributeType = .stringAttributeType
        ed_metering.isOptional = true
        exifData.properties.append(ed_metering)
        
        let ed_flash = NSAttributeDescription()
        ed_flash.name = "flash"
        ed_flash.attributeType = .stringAttributeType
        ed_flash.isOptional = true
        exifData.properties.append(ed_flash)
        
        let ed_wb = NSAttributeDescription()
        ed_wb.name = "whiteBalance"
        ed_wb.attributeType = .stringAttributeType
        ed_wb.isOptional = true
        exifData.properties.append(ed_wb)
        
        let ed_prog = NSAttributeDescription()
        ed_prog.name = "exposureProgram"
        ed_prog.attributeType = .stringAttributeType
        ed_prog.isOptional = true
        exifData.properties.append(ed_prog)
        
        let ed_expComp = NSAttributeDescription()
        ed_expComp.name = "exposureCompensation"
        ed_expComp.attributeType = .doubleAttributeType
        ed_expComp.isOptional = true
        exifData.properties.append(ed_expComp)
        
        // Properties - Collection
        let col_id = NSAttributeDescription()
        col_id.name = "id"
        col_id.attributeType = .UUIDAttributeType
        col_id.isOptional = true
        
        let col_name = NSAttributeDescription()
        col_name.name = "name"
        col_name.attributeType = .stringAttributeType
        col_name.isOptional = true
        
        let col_type = NSAttributeDescription()
        col_type.name = "type"
        col_type.attributeType = .stringAttributeType
        col_type.isOptional = true
        
        collection.properties = [col_id, col_name, col_type]
        
        // Relationships
        let cat_items = NSRelationshipDescription()
        cat_items.name = "mediaItems"
        cat_items.destinationEntity = mediaItem
        cat_items.minCount = 0
        cat_items.maxCount = 0 // To-many
        cat_items.deleteRule = .cascadeDeleteRule
        
        let mi_cat = NSRelationshipDescription()
        mi_cat.name = "catalog"
        mi_cat.destinationEntity = catalog
        mi_cat.minCount = 0
        mi_cat.maxCount = 1 // To-one
        mi_cat.deleteRule = .nullifyDeleteRule
        mi_cat.inverseRelationship = cat_items
        cat_items.inverseRelationship = mi_cat
        
        catalog.properties.append(cat_items)
        mediaItem.properties.append(mi_cat)
        
        // Relationships - Collection
        let col_cat = NSRelationshipDescription()
        col_cat.name = "catalog"
        col_cat.destinationEntity = catalog
        col_cat.minCount = 0
        col_cat.maxCount = 1
        col_cat.deleteRule = .nullifyDeleteRule
        
        let col_items = NSRelationshipDescription()
        col_items.name = "mediaItems"
        col_items.destinationEntity = mediaItem
        col_items.minCount = 0
        col_items.maxCount = 0 // To-many
        col_items.deleteRule = .nullifyDeleteRule
        
        collection.properties = [col_id, col_name, col_type, col_cat, col_items]
        
        // Inverse Relationships
        let cat_cols = NSRelationshipDescription()
        cat_cols.name = "collections"
        cat_cols.destinationEntity = collection
        cat_cols.minCount = 0
        cat_cols.maxCount = 0 // To-many
        cat_cols.deleteRule = .cascadeDeleteRule
        cat_cols.inverseRelationship = col_cat
        col_cat.inverseRelationship = cat_cols
        
        catalog.properties.append(cat_cols)
        
        let mi_cols = NSRelationshipDescription()
        mi_cols.name = "collections"
        mi_cols.destinationEntity = collection
        mi_cols.minCount = 0
        mi_cols.maxCount = 0 // To-many
        mi_cols.deleteRule = .nullifyDeleteRule
        mi_cols.inverseRelationship = col_items
        col_items.inverseRelationship = mi_cols
        
        mediaItem.properties.append(mi_cols)
        
        // Relationships - ExifData
        let mi_exif = NSRelationshipDescription()
        mi_exif.name = "exifData"
        mi_exif.destinationEntity = exifData
        mi_exif.minCount = 0
        mi_exif.maxCount = 1
        mi_exif.deleteRule = .cascadeDeleteRule
        
        let ed_mi = NSRelationshipDescription()
        ed_mi.name = "mediaItem"
        ed_mi.destinationEntity = mediaItem
        ed_mi.minCount = 1
        ed_mi.maxCount = 1
        ed_mi.deleteRule = .nullifyDeleteRule
        ed_mi.inverseRelationship = mi_exif
        mi_exif.inverseRelationship = ed_mi
        
        mediaItem.properties.append(mi_exif)
        exifData.properties.append(ed_mi)
        
        model.entities = [catalog, mediaItem, exifData, collection]
        return model
    }
}

extension Notification.Name {
    static let coreDataStackChanged = Notification.Name("coreDataStackChanged")
    static let requestNewCatalog = Notification.Name("requestNewCatalog")
    static let requestOpenCatalog = Notification.Name("requestOpenCatalog")
}
