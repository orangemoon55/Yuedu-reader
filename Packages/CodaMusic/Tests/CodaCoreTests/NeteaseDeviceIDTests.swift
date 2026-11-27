import Foundation
import Testing
@testable import CodaCore

struct NeteaseDeviceIDTests {
    @Test func identitySurvivesRestartAndRepairsCorruptStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = NeteaseClient.loadDeviceID(in: directory)
        #expect(first.count == 52)
        #expect(first.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) })
        #expect(NeteaseClient.loadDeviceID(in: directory) == first)
        let file = directory.appendingPathComponent("device-id")
        try Data("coda".utf8).write(to: file)
        let repaired = NeteaseClient.loadDeviceID(in: directory)
        #expect(repaired != "coda" && repaired.count == 52)
        #expect(try String(contentsOf: file, encoding: .utf8) == repaired)
        #expect(NeteaseClient.loadDeviceID(in: nil).count == 52)
    }
}
