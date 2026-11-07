import Foundation
import CryptoKit

@main
struct UpdateTests {
    static func main() throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Tests/UpdateFixtures.json"))) as! [String: Any]
        var count = 0
        func check(_ value: Bool, _ message: String) {
            count += 1
            precondition(value, message)
        }
        for row in json["versions"] as! [[Any]] {
            check(UpdatePolicy.isNewer(current: row[0] as! String, candidate: row[1] as! String) == row[2] as! Bool, "Version comparison: \(row)")
        }
        for path in json["invalidPaths"] as! [String] { check(!UpdatePolicy.safeArchivePath(path), "Unsafe archive path: \(path)") }
        check(UpdatePolicy.safeArchivePath("上班鼓励器.app/Contents/MacOS/Encourager"), "Valid archive path")
        let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/UpdateRelease.json"))
        let release = try ReleaseUpdate.parse(fixture, current: "0.1.1")!
        check(release.version == "0.2.0" && release.name.hasSuffix("macOS-universal.zip"), "Mac package selection")
        check(try ReleaseUpdate.parse(fixture, current: "0.2.0") == nil, "No update for same version")
        check(try ReleaseUpdate.parse(fixture, current: "1.0.0") == nil, "No downgrade")
        func changed(_ modify: (inout [String: Any]) -> Void) throws -> Data {
            var json = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
            modify(&json); return try JSONSerialization.data(withJSONObject: json)
        }
        for key in ["draft", "prerelease"] { check(try ReleaseUpdate.parse(changed { $0[key] = true }, current: "0.1.1") == nil, "Skip \(key)") }
        for (key, value) in [("digest", "sha256:bad" as Any), ("url", "https://evil.example/file" as Any), ("size", 0 as Any), ("size", 600_000_000 as Any), ("name", "PaySprout.exe" as Any)] {
            let bad = try changed { json in
                var assets = json["assets"] as! [[String: Any]]; assets[0][key] = value; json["assets"] = assets
            }
            do { _ = try ReleaseUpdate.parse(bad, current: "0.1.1"); check(false, "Reject invalid \(key)") }
            catch { check(true, "Rejected invalid \(key)") }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("verified update fixture".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try UpdateFiles.verify(temporary, update: release); check(true, "Verified exact bytes")
        try Data("modified update fixture".utf8).write(to: temporary)
        do { try UpdateFiles.verify(temporary, update: release); check(false, "Reject same-size tampering") } catch { check(true, "Rejected tampering") }
        try Data().write(to: temporary)
        do { try UpdateFiles.verify(temporary, update: release); check(false, "Reject truncation") } catch { check(true, "Rejected truncation") }
        print("Passed \(count) Mac update policy checks.")
    }
}
