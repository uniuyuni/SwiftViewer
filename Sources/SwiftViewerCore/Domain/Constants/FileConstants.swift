import Foundation

public struct FileConstants {
    public static let allowedImageExtensions = [
        "jpg", "jpeg", "png", "heic", "tiff", "gif", "webp",
        "arw", "cr2", "cr3", "nef", "dng", "orf", "raf", "rw2", "pef", "srw",
        "3fr", "fff", "mos", "x3f", "gpr", "iiq", "nrw", "sr2", "srf", "erf",
        "kdc", "mef", "mrw", "rwl", "raw"
    ]
    
    public static let allowedVideoExtensions = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
        "braw", "r3d", "crm"
    ]
    
    public static var allAllowedExtensions: [String] {
        allowedImageExtensions + allowedVideoExtensions
    }
    
    public static let rawExtensions = [
        "arw", "cr2", "cr3", "nef", "dng", "orf", "raf", "rw2", "pef", "srw",
        "3fr", "fff", "mos", "x3f", "gpr", "iiq", "nrw", "sr2", "srf", "erf",
        "kdc", "mef", "mrw", "rwl", "raw", "braw", "r3d", "crm"
    ]
}
