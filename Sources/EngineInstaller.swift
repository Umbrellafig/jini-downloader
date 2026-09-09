import Foundation
import CryptoKit

struct EngineManifest: Codable {
    var revision: String
    var tools: [EngineSpec]
    static func bundled() throws -> EngineManifest {
        guard let url = Bundle.main.url(forResource: "engines", withExtension: "json") else { throw failure("엔진 설치 목록이 없습니다. 앱을 다시 내려받아 주세요.") }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
struct EngineSpec: Codable { var name: String; var version: String; var url: String; var sha256: String; var archive: String; var executable: String; var bytes: Int64 }
final class EngineInstaller: @unchecked Sendable {
    let manifest: EngineManifest
    let root: URL
    init(manifest: EngineManifest, root: URL? = nil) {
        self.manifest = manifest
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JiniDownloader/Engines", isDirectory: true)
    }
    var directory: URL { root.appendingPathComponent(manifest.revision, isDirectory: true) }
    var bin: URL { directory.appendingPathComponent("bin", isDirectory: true) }
    var ready: Bool {
        let marker = directory.appendingPathComponent("installed.json")
        guard let data = try? Data(contentsOf: marker), let saved = try? JSONDecoder().decode(EngineManifest.self, from: data), saved.revision == manifest.revision, saved.tools.map(\.sha256) == manifest.tools.map(\.sha256) else { return false }
        return manifest.tools.allSatisfy { FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent($0.executable).path) }
    }
    static func digest(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; var sha = SHA256()
        while true { let d = try h.read(upToCount: 1024*1024) ?? Data(); if d.isEmpty { break }; sha.update(data: d) }
        return sha.finalize().map { String(format:"%02x",$0) }.joined()
    }
    func install(update: @escaping @Sendable (String, Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let stage = root.appendingPathComponent(".install-" + UUID().uuidString, isDirectory:true)
        try fm.createDirectory(at: stage.appendingPathComponent("bin"), withIntermediateDirectories:true)
        defer { try? fm.removeItem(at: stage) }
        for (index, tool) in manifest.tools.enumerated() {
            try Task.checkCancellation()
            guard let url = webURL(tool.url), url.scheme == "https", tool.sha256.count == 64 else { throw failure("유효하지 않은 엔진 설치 정보입니다.") }
            let fraction = Double(index) / Double(manifest.tools.count)
            update("\(index+1)/\(manifest.tools.count) · \(tool.name) 다운로드 (\(bytes(Double(tool.bytes))))", fraction)
            var request = URLRequest(url: url); request.timeoutInterval = 90
            let (temp, response) = try await URLSession.shared.download(for: request)
            defer { try? fm.removeItem(at: temp) }
            try Task.checkCancellation()
            guard let r = response as? HTTPURLResponse, (200...299).contains(r.statusCode), response.url?.scheme == "https" else { throw failure("\(tool.name) 다운로드에 실패했습니다. 잠시 후 다시 설치해 주세요.") }
            update("\(tool.name) 파일 검증 중…", fraction)
            let digest = try await Task.detached { try Self.digest(temp) }.value
            guard digest == tool.sha256 else { throw failure("\(tool.name)의 체크섬이 일치하지 않습니다. 실행하지 않고 설치를 중단했습니다.") }
            let target = stage.appendingPathComponent("bin").appendingPathComponent(tool.executable)
            if tool.archive == "zip" {
                let unpack = stage.appendingPathComponent("unpack-" + tool.name)
                try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
                let r = try await EngineRunner().run(URL(fileURLWithPath:"/usr/bin/ditto"), ["-x","-k",temp.path,unpack.path])
                guard r.code == 0 else { throw failure("\(tool.name) 압축 해제 실패: \(r.errors)") }
                try fm.moveItem(at: unpack.appendingPathComponent(tool.executable), to: target)
                try fm.removeItem(at: unpack)
            } else { try fm.copyItem(at: temp, to: target) }
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }
        try Task.checkCancellation()
        update("설치한 도구 실행 확인 중…", 0.95)
        for name in ["yt-dlp", "gallery-dl", "deno", "ffmpeg", "ffprobe"] {
            let args = ["ffmpeg","ffprobe"].contains(name) ? ["-version"] : ["--version"]
            let result = try await EngineRunner().run(stage.appendingPathComponent("bin").appendingPathComponent(name), args)
            guard result.code == 0 else { throw failure("\(name) 실행 확인에 실패했습니다: \(result.errors)") }
        }
        try JSONEncoder().encode(manifest).write(to: stage.appendingPathComponent("installed.json"), options: .atomic)
        try Task.checkCancellation()
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: stage, to: directory)
        update("필수 도구 설치 완료", 1)
    }
}
