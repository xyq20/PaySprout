import AppKit
import SwiftUI

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: (Double) -> Void
    init(_ report: @escaping (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { DispatchQueue.main.async { self.report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) } }
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published var phase = "idle"
    @Published var message = "可以检查并安装最新稳定版本。"
    @Published var progress = 0.0
    @Published var release: ReleaseUpdate?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var workspace: URL?
    private var incoming: URL?
    private var installing = false
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    var busy: Bool { phase == "checking" || phase == "downloading" }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "薪芽 · 软件更新"; window.isReleasedWhenClosed = false; window.level = .floating
            window.contentView = NSHostingView(rootView: SoftwareUpdateView(updater: self)); window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func check(manual: Bool) {
        if manual { show() }
        guard !busy, !installing else { return }
        if phase == "ready" || phase == "available" { if manual { show() }; return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if !manual && Date().timeIntervalSince1970 - last < 6 * 3600 { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        phase = "checking"; message = "正在检查最新版本…"
        task = Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/xyq20/PaySprout/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.setValue("PaySprout-Updater/1.0", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 { release = nil }
                else {
                    guard status == 200 else { throw UpdateError(status == 403 ? "检查次数暂时受限，请稍后重试。" : "无法连接更新服务（\(status)）。") }
                    release = try ReleaseUpdate.parse(data, current: currentVersion)
                }
                if let release { phase = "available"; message = "发现新版本 v\(release.version)"; show() }
                else { phase = "latest"; message = "当前 v\(currentVersion) 已是最新稳定版本。" }
            } catch { phase = "failed"; message = "检查更新失败：\(error.localizedDescription)" }
        }
    }
    func download() {
        guard !busy, let release else { return }
        phase = "downloading"; progress = 0; message = "正在下载并校验更新…"
        task = Task {
            var created: URL?
            do {
                let workspace = UpdateFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                created = workspace; try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                var request = URLRequest(url: release.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30 * 60)
                request.setValue("PaySprout-Updater/1.0", forHTTPHeaderField: "User-Agent")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                let delegate = DownloadProgress { [weak self] value in self?.progress = value }
                let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else { throw UpdateError("下载更新失败，请稍后重试。") }
                try Task.checkCancellation()
                let zip = workspace.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: temporary, to: zip)
                let target = Bundle.main.bundleURL
                let incoming = try await Task.detached { try UpdateFiles.prepare(zip: zip, update: release, target: target, workspace: workspace) }.value
                if Task.isCancelled { try? FileManager.default.removeItem(at: incoming); throw CancellationError() }
                self.workspace = workspace; self.incoming = incoming; progress = 1; phase = "ready"
                message = "v\(release.version) 已准备好。重启后完成更新，设置会保留；本次临时充电计时将结束。"
            } catch {
                if let created { try? FileManager.default.removeItem(at: created) }
                phase = Task.isCancelled ? "available" : "failed"
                message = Task.isCancelled ? "下载已取消，可重新下载。" : "更新准备失败：\(error.localizedDescription)"
            }
        }
    }
    func cancel() { task?.cancel() }
    func install() {
        guard phase == "ready", let workspace, let incoming, let release, !installing else { return }
        do {
            let target = Bundle.main.bundleURL
            let backup = target.deletingLastPathComponent().appendingPathComponent(".PaySprout-\(workspace.lastPathComponent).previous.app")
            let plan = ["version": release.version, "target": target.path]
            try JSONSerialization.data(withJSONObject: plan).write(to: workspace.appendingPathComponent("plan.json"), options: .atomic)
            guard let resource = Bundle.main.url(forResource: "install-update-macos", withExtension: "sh") else { throw UpdateError("找不到更新助手，请重新安装此版本。") }
            let script = workspace.appendingPathComponent("install.sh"); try FileManager.default.copyItem(at: resource, to: script)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, incoming.path, backup.path, workspace.path, workspace.lastPathComponent]
            process.standardInput = FileHandle.nullDevice
            let log = workspace.appendingPathComponent("install.log"); FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
            try process.run(); try? handle.close(); installing = true
            (NSApp.delegate as? AppDelegate)?.saveWindowSize(); NSApp.terminate(nil)
        } catch { phase = "failed"; message = "无法启动更新：\(error.localizedDescription)" }
    }
    func discardPreparedUpdate() {
        guard !installing else { return }
        if let incoming { try? FileManager.default.removeItem(at: incoming) }
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        incoming = nil; workspace = nil
    }
    static func acknowledgeLaunch() {
        let args = ProcessInfo.processInfo.arguments
        guard args.count == 3, let token = args.last, UUID(uuidString: token) != nil else { return }
        let workspace = UpdateFiles.root.appendingPathComponent(token)
        if args[1] == "--paysprout-updated" {
            do {
                let plan = try JSONSerialization.jsonObject(with: Data(contentsOf: workspace.appendingPathComponent("plan.json"))) as? [String: String]
                guard plan?["version"] == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      plan?["target"] == Bundle.main.bundleURL.path else { return }
                try String(ProcessInfo.processInfo.processIdentifier).write(to: workspace.appendingPathComponent("ready.txt"), atomically: true, encoding: .utf8)
            } catch { }
        } else if args[1] == "--paysprout-rollback" {
            let alert = NSAlert(); alert.messageText = "更新未完成，已恢复旧版"; alert.informativeText = "薪资与窗口设置已保留。请稍后重新检查更新。"; alert.runModal()
        }
    }
}

private struct SoftwareUpdateView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("让小薪芽保持新鲜").font(.title2.weight(.semibold))
            Text("当前版本 v\(updater.currentVersion)").foregroundStyle(.secondary)
            Text(updater.message).fixedSize(horizontal: false, vertical: true).font(.system(size: 13))
            if updater.busy {
                if updater.phase == "checking" { ProgressView().controlSize(.small) }
                else { ProgressView(value: updater.progress); Text("\(Int(updater.progress * 100))%").monospacedDigit() }
            }
            if let release = updater.release {
                ScrollView { Text(release.notes.isEmpty ? "本次更新包含功能与体验改进。" : release.notes).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                Link("查看完整发布说明", destination: release.notesURL).font(.system(size: 11))
            }
            Spacer(minLength: 0)
            HStack {
                if updater.busy { Button("取消", action: updater.cancel) }
                Spacer()
                if updater.phase == "ready" { Button("重启更新", action: updater.install).buttonStyle(.borderedProminent) }
                else if updater.release != nil && !updater.busy { Button("下载更新", action: updater.download).buttonStyle(.borderedProminent) }
                else if !updater.busy { Button("检查更新") { updater.check(manual: true) }.buttonStyle(.borderedProminent) }
            }
        }.padding(24).frame(width: 420, height: 340).background(Color(nsColor: .windowBackgroundColor))
    }
}
