import CoreData

public struct PersistenceController {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        // We need to load the model from the package bundle
        // Try .momd first (model bundle)
        var modelURL = Bundle.module.url(forResource: "SwiftViewer", withExtension: "momd")
        
        // Try .mom (single model file)
        if modelURL == nil {
            modelURL = Bundle.module.url(forResource: "SwiftViewer", withExtension: "mom")
        }
        
        if modelURL == nil {
            print("DEBUG: Bundle.module path: \(Bundle.module.bundlePath)")
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
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Enable automatic migration
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        
        print("DEBUG: Loading persistent stores...")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("DEBUG: Failed to load store: \(error), \(error.userInfo)")
                // fatalError("Unresolved error \(error), \(error.userInfo)") // Don't crash, just log?
                // If we don't crash, the app might run but be broken.
                // But for debugging, let's see the error.
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        print("DEBUG: Persistent stores loaded.")
        
        container.viewContext.automaticallyMergesChangesFromParent = true
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
        
        catalog.properties = [cat_id, cat_name, cat_created, cat_modified, cat_color]
        
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
        
        mediaItem.properties = [mi_id, mi_path, mi_name, mi_size, mi_type, mi_capture, mi_import, mi_mod, mi_rating, mi_flag, mi_color, mi_orient, mi_w, mi_h, mi_exists]
        
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
