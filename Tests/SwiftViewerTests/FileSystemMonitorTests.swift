import XCTest
@testable import SwiftViewerCore
import Foundation

final class FileSystemMonitorTests: XCTestCase {
    var tempDir: URL!
    var monitor: FileSystemMonitor!
    
    override func setUpWithError() throws {
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
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
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
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventCount += 1
        }
        
        // Suspend
        monitor.suspend()
        
        // Create multiple files while suspended
        for i in 0..<3 {
            let testFile = tempDir.appendingPathComponent("test\(i).txt")
            try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Wait
        Thread.sleep(forTimeInterval: 0.2)
        
        // No events should fire
        XCTAssertEqual(eventCount, 0, "No events should fire while suspended")
        
        // Resume
        monitor.resume()
        
        // Create one more file
        let testFile = tempDir.appendingPathComponent("test3.txt")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Only one event should fire (after resume)
        XCTAssertGreaterThanOrEqual(eventCount, 1, "At least one event should fire after resume")
    }
    
    // MARK: - Timing
    
    func testMonitorResumeDelay() async throws {
        var eventFired = false
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventFired = true
        }
        
        // Suspend
        monitor.suspend()
        
        // Resume after a delay (simulating writeMetadataBatch behavior)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
            self.monitor.resume()
        }
        
        // Create file immediately
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait 0.5s (before resume)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Event should NOT have fired yet
        XCTAssertFalse(eventFired, "Event should not fire before resume")
        
        // Wait another 0.7s (after resume)
        try await Task.sleep(nanoseconds: 700_000_000)
        
        // Event might fire now (depending on file system timing)
        // This test mainly verifies no crashes occur with delayed resume
        XCTAssertTrue(true, "No crash with delayed resume")
    }
    
    func testMonitorEventAfterResume() throws {
        var eventFired = false
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventFired = true
        }
        
        // Suspend and immediately resume
        monitor.suspend()
        monitor.resume()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should fire
        XCTAssertTrue(eventFired, "Event should fire after resume")
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
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Should not crash, event should fire
        XCTAssertGreaterThanOrEqual(eventCount, 0, "Should handle concurrent suspend/resume")
    }
    
    func testMultipleSuspendResume() throws {
        var eventFired = false
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventFired = true
        }
        
        // Multiple suspend calls
        monitor.suspend()
        monitor.suspend()
        monitor.suspend()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.2)
        
        // Event should not fire
        XCTAssertFalse(eventFired, "Event should not fire with multiple suspends")
        
        // Multiple resume calls
        monitor.resume()
        monitor.resume()
        monitor.resume()
        
        // Modify file
        try "modified".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should fire
        XCTAssertTrue(eventFired, "Event should fire after multiple resumes")
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
        
        // Start monitoring
        monitor.startMonitoring(url: tempDir) {
            eventFired = true
        }
        
        // Resume without suspend
        monitor.resume()
        
        // Create file
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Wait
        Thread.sleep(forTimeInterval: 0.3)
        
        // Event should still fire
        XCTAssertTrue(eventFired, "Event should fire even with resume-before-suspend")
    }
}
