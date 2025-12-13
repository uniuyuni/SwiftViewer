import Foundation

public struct FileConstants {
    public static let allowedImageExtensions = [
        "jpg", "jpeg", "png", "heic", "tiff", "gif", "webp", "bmp", "heif", "tif",
        "arw", "cr2", "cr3", "nef", "dng", "orf", "raf", "rw2", "pef", "srw",
        "3fr", "fff", "mos", "x3f", "gpr", "iiq", "nrw", "sr2", "srf", "erf",
        "kdc", "mef", "mrw", "rwl", "raw", "crw", "dcr"
    ]
    
    public static let allowedVideoExtensions = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
        "braw", "r3d", "crm", "mts", "m2ts", "heiv"
    ]
    
    public static var allAllowedExtensions: [String] {
        allowedImageExtensions + allowedVideoExtensions
    }
    
    public static let rawExtensions = [
        "arw", "cr2", "cr3", "nef", "dng", "orf", "raf", "rw2", "pef", "srw",
        "3fr", "fff", "mos", "x3f", "gpr", "iiq", "nrw", "sr2", "srf", "erf",
        "kdc", "mef", "mrw", "rwl", "raw", "braw", "r3d", "crm", "crw", "dcr"
    ]
}
