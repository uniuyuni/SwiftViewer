import Foundation
import AppKit

class FileOperationService {
    static let shared = FileOperationService()
    
    func copyFile(at url: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: url, to: destination)
    }
    
    func moveFile(at url: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: url, to: destination)
    }
    
    func deleteFile(at url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
    
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
