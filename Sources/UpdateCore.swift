import Foundation
import CryptoKit

struct AppVersion: Equatable, Comparable {
    let parts: [Int]
    var text: String { parts.map(String.init).joined(separator: ".") }
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        var parsed: [Int] = []
        for field in fields {
            guard !field.isEmpty, field == "0" || !field.hasPrefix("0"),
                  field.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let number = Int(field), number <= Int(Int32.max) else { return nil }
            parsed.append(number)
        }
        parts = parsed
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

enum UpdatePolicy {
    static func isNewer(current: String, candidate: String) -> Bool {
        guard let current = AppVersion(current), let candidate = AppVersion(candidate) else { return false }
        return candidate > current
    }
    static func safeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { return false }
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        return clean.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct ReleaseUpdate {
    let version: String
    let name: String
    let downloadURL: URL
    let sha256: String
    let size: Int64
    let notes: String
    var notesURL: URL { URL(string: "https://github.com/xyq20/PaySprout/releases/tag/v\(version)")! }

    static func parse(_ data: Data, current: String) throws -> ReleaseUpdate? {
        struct Asset: Decodable { let id: Int64; let name: String; let size: Int64; let digest: String?; let url: String }
        struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let body: String?; let assets: [Asset] }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = AppVersion(release.tag_name), release.tag_name == "v" + version.text else { throw UpdateError("发布版本号格式无效。") }
        guard UpdatePolicy.isNewer(current: current, candidate: version.text) else { return nil }
        let name = "PaySprout-\(version.text)-macOS-universal.zip"
        let matches = release.assets.filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first else { throw UpdateError("此版本暂未提供 Mac 更新包，请稍后重试。") }
        let digest = asset.digest ?? ""
        let hash = String(digest.dropFirst(7))
        let expected = "https://api.github.com/repos/xyq20/PaySprout/releases/assets/\(asset.id)"
        guard digest.hasPrefix("sha256:"), hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              asset.id > 0, asset.size > 0, asset.size <= 512 * 1024 * 1024, asset.url == expected else { throw UpdateError("更新包缺少有效校验信息，已停止更新。") }
        return ReleaseUpdate(version: version.text, name: name, downloadURL: URL(string: expected)!, sha256: hash, size: asset.size, notes: String((release.body ?? "").prefix(6000)))
    }
}

enum UpdateFiles {
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PaySproutUpdates", isDirectory: true)
    static func hash(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ file: URL, update: ReleaseUpdate) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size == update.size, try hash(file) == update.sha256 else { throw UpdateError("下载文件不完整或校验失败，请重新下载。") }
    }
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        let output = Pipe(); let errors = Pipe(); task.standardOutput = output; task.standardError = errors
        try task.run()
        // stderr is discarded to avoid a full pipe blocking archive inspection.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit(); errors.fileHandleForReading.readabilityHandler = nil
        guard task.terminationStatus == 0 else { throw UpdateError("更新包检查或解压失败（\(task.terminationStatus)）。") }
        return String(decoding: data, as: UTF8.self)
    }
    static func prepare(zip: URL, update: ReleaseUpdate, target: URL, workspace: URL) throws -> URL {
        try verify(zip, update: update)
        let manager = FileManager.default
        guard !target.path.contains("/AppTranslocation/"), manager.isWritableFile(atPath: target.deletingLastPathComponent().path),
              !target.path.hasPrefix("/Volumes/") else { throw UpdateError("请先将应用移到有写入权限的应用程序目录，再重试更新。") }
        let names = try run("/usr/bin/zipinfo", ["-1", zip.path]).split(separator: "\n").map(String.init)
        guard !names.isEmpty, names.allSatisfy({ UpdatePolicy.safeArchivePath($0) && ($0.hasPrefix("上班鼓励器.app/") || $0.hasPrefix("__MACOSX/")) }) else { throw UpdateError("更新包目录结构不安全。") }
        let unpacked = workspace.appendingPathComponent("unpacked", isDirectory: true)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let app = unpacked.appendingPathComponent("上班鼓励器.app", isDirectory: true)
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "local.gentlework.encourager",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == update.version else { throw UpdateError("更新包的应用标识或版本不匹配。") }
        if let items = manager.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in items {
                if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw UpdateError("更新包含有不支持的符号链接。") }
            }
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let incoming = target.deletingLastPathComponent().appendingPathComponent(".PaySprout-\(workspace.lastPathComponent).new.app")
        do { try manager.copyItem(at: app, to: incoming) }
        catch { try? manager.removeItem(at: incoming); throw error }
        return incoming
    }
}
