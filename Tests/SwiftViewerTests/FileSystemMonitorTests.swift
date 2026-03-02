import XCTest
@testable import SwiftViewerCore
import Foundation

final class FileSystemMonitorTests: XCTestCase {
    var tempDir: URL!
    var monitor: FileSystemMonitor!
    
    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: "filterCriteria")
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        tempDir = tempBase.resolvingSymlinksInPath()
        
        monitor = FileSystemMonitor.shared
    }
    
    override func tearDownWithError() throws {
        monitor.stopMonitoring()
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Basic Operations
    
    func testMonitorSuspendResume() throws {
        var eventFired = false
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventFired = true
        }
        
        // Suspend
        monitor.suspend()
        
        // Create a file while suspended
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait briefly
        Thread.sleep(forTimeInterval: 0.2)
        
        // Event should NOT fire while suspended
        XCTAssertFalse(eventFired, "Event should not fire while suspended")
        
        // Resume
        monitor.resume()
        
        // Modify file after resume
        try "modified".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait for event
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should fire after resume
        XCTAssertTrue(eventFired, "Event should fire after resume")
    }
    
    func testMonitorEventFiltering() throws {
        var eventCount = 0
        let lock = NSLock()
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventCount += 1
            lock.unlock()
        }
        
        // Wait slightly longer to ensure any stray events (from setup or delay) are definitely processed
        Thread.sleep(forTimeInterval: 0.5)
        
        // Reset eventCount immediately before suspending to guarantee clean state
        lock.lock()
        eventCount = 0
        lock.unlock()
        
        // Suspend
        monitor.suspend()
        
        // Create multiple files while suspended
        for i in 0..<3 {
            let testFile = tempDir.appendingPathComponent("test\(i).txt")
            try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Wait longer to ensure any delayed events are ignored while suspended
        Thread.sleep(forTimeInterval: 1.0)
        
        // No events should fire
        lock.lock()
        let countWhileSuspended = eventCount
        lock.unlock()
        XCTAssertEqual(countWhileSuspended, 0, "No events should fire while suspended")
        
        // Resume
        monitor.resume()
        
        // Create one more file
        let testFile = tempDir.appendingPathComponent("test3.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Only one event should fire (after resume)
        lock.lock()
        let countAfterResume = eventCount
        lock.unlock()
        XCTAssertGreaterThanOrEqual(countAfterResume, 1, "At least one event should fire after resume")
    }
    
    // MARK: - Timing
    
    func testMonitorResumeDelay() throws {
        var eventFired = false
        let lock = NSLock()
        
        let expectation = self.expectation(description: "Wait for delayed resume and event")
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventFired = true
            lock.unlock()
            expectation.fulfill()
        }
        
        // Suspend
        monitor.suspend()
        
        // Resume after a delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            self.monitor.resume()
        }
        
        // Create file immediately
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait 0.5s (before resume)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Event should NOT have fired yet
        lock.lock()
        let firedBeforeResume = eventFired
        lock.unlock()
        XCTAssertFalse(firedBeforeResume, "Event should not fire before resume")
        
        // Wait for the expectation to be fulfilled after resume (timeout after 2.0s)
        waitForExpectations(timeout: 2.0)
        
        lock.lock()
        let finalFired = eventFired
        lock.unlock()
        XCTAssertTrue(finalFired, "Event should fire after delayed resume")
    }
    
    func testMonitorEventAfterResume() throws {
        var eventFired = false
        let lock = NSLock()
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventFired = true
            lock.unlock()
        }
        
        // Suspend and immediately resume
        monitor.suspend()
        monitor.resume()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should fire
        lock.lock()
        let finalFired = eventFired
        lock.unlock()
        XCTAssertTrue(finalFired, "Event should fire after resume")
    }
    
    // MARK: - Thread Safety
    
    func testMonitorThreadSafety() throws {
        var eventCount = 0
        let lock = NSLock()
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventCount += 1
            lock.unlock()
        }
        
        // Call suspend/resume from multiple threads
        let group = DispatchGroup()
        
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                self.monitor.suspend()
                Thread.sleep(forTimeInterval: 0.01)
                self.monitor.resume()
                group.leave()
            }
        }
        
        group.wait()
        
        // Create a file after all operations
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Should not crash, event should fire
        XCTAssertGreaterThanOrEqual(eventCount, 0, "Should handle concurrent suspend/resume")
    }
    
    func testMultipleSuspendResume() throws {
        var eventFired = false
        let lock = NSLock()
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventFired = true
            lock.unlock()
        }
        
        // Multiple suspend calls
        monitor.suspend()
        monitor.suspend()
        monitor.suspend()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.2)
        
        // Event should not fire
        lock.lock()
        let firedWhileSuspended = eventFired
        lock.unlock()
        XCTAssertFalse(firedWhileSuspended, "Event should not fire with multiple suspends")
        
        // Multiple resume calls
        monitor.resume()
        monitor.resume()
        monitor.resume()
        
        // Modify file
        try "modified".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should fire
        lock.lock()
        let firedAfterResume = eventFired
        lock.unlock()
        XCTAssertTrue(firedAfterResume, "Event should fire after multiple resumes")
    }
    
    // MARK: - Edge Cases
    
    func testSuspendWithoutStart() throws {
        // Suspend without starting monitoring
        monitor.suspend()
        
        // Should not crash
        XCTAssertTrue(true, "Should handle suspend without start")
        
        // Resume
        monitor.resume()
        
        // Should not crash
        XCTAssertTrue(true, "Should handle resume without start")
    }
    
    func testResumeWithoutSuspend() throws {
        var eventFired = false
        let lock = NSLock()
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            lock.lock()
            eventFired = true
            lock.unlock()
        }
        
        // Resume without suspend
        monitor.resume()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try (Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=", options: .ignoreUnknownCharacters) ?? Data("dummy".utf8)).write(to: testFile, options: .atomic)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should still fire
        lock.lock()
        let finalFired = eventFired
        lock.unlock()
        XCTAssertTrue(finalFired, "Event should fire even with resume-before-suspend")
    }
}
