import Foundation

struct EngineResult { var output: Data; var errors: String; var code: Int32 }
private final class PipeReader: @unchecked Sendable {
    var data = Data()
    let handle: FileHandle
    let limit: Int
    let callback: @Sendable (String) -> Void
    init(_ handle: FileHandle, limit: Int, callback: @escaping @Sendable (String) -> Void) { self.handle = handle; self.limit = limit; self.callback = callback }
    func read() {
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) { let line = pending[..<end]; if line.count < 64000 { callback(String(decoding: line, as: UTF8.self)) }; pending.removeSubrange(...end) }
            if pending.count > 1024 * 1024 { pending.removeAll(keepingCapacity: true) }
        }
        if !pending.isEmpty { callback(String(decoding: pending, as: UTF8.self)) }
        try? handle.close()
    }
}
final class EngineRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning {
            p.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
        }
    }
    func run(_ executable: URL, _ args: [String], line: @escaping @Sendable (String) -> Void = { _ in }) async throws -> EngineResult {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process(); p.executableURL = executable; p.arguments = args
                    var env = ProcessInfo.processInfo.environment
                    env["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    env["PYTHONUNBUFFERED"] = "1"; p.environment = env
                    let stdout = Pipe(), stderr = Pipe()
                    p.standardOutput = stdout; p.standardError = stderr; p.standardInput = FileHandle.nullDevice
                    let out = PipeReader(stdout.fileHandleForReading, limit: 32*1024*1024, callback: line)
                    let err = PipeReader(stderr.fileHandleForReading, limit: 256*1024, callback: line)
                    self.lock.lock()
                    if self.cancelled { self.lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                    self.process = p
                    do { try p.run(); self.lock.unlock() } catch { self.process = nil; self.lock.unlock(); continuation.resume(throwing: error); return }
                    let group = DispatchGroup()
                    group.enter(); DispatchQueue.global().async { out.read(); group.leave() }
                    group.enter(); DispatchQueue.global().async { err.read(); group.leave() }
                    p.waitUntilExit(); group.wait()
                    self.lock.lock(); self.process = nil; let wasCancelled = self.cancelled; self.lock.unlock()
                    if wasCancelled { continuation.resume(throwing: CancellationError()) }
                    else { continuation.resume(returning: EngineResult(output: out.data, errors: String(decoding: err.data, as: UTF8.self), code: p.terminationStatus)) }
                }
            }
        }, onCancel: { self.cancel() })
    }
}
final class FileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var active: URLSessionDownloadTask?
    private var result: Result<URL, Error>?
    private var destination: URL!
    private var started = Date()
    private var lastUpdate = Date.distantPast
    private let lock = NSLock()
    private var cancelled = false
    var progress: @Sendable (StreamProgress) -> Void = { _ in }
    func cancel() { lock.lock(); cancelled = true; let t = active; lock.unlock(); t?.cancel() }
    func download(_ request: URLRequest, to destination: URL) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { c in
                lock.lock()
                if cancelled { lock.unlock(); c.resume(throwing: CancellationError()); return }
                self.continuation = c; self.destination = destination; started = Date()
                let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 40; config.timeoutIntervalForResource = 24*3600
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let s = URLSession(configuration: config, delegate: self, delegateQueue: queue); session = s
                let t = s.downloadTask(with: request); active = t; t.resume(); lock.unlock()
            }
        }, onCancel: { self.cancel() })
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date(); guard now.timeIntervalSince(lastUpdate) > 0.12 else { return }; lastUpdate = now
        let speed = Double(totalBytesWritten) / max(0.1, now.timeIntervalSince(started))
        progress(StreamProgress(id: "direct", downloaded: Double(totalBytesWritten), total: totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : nil, speed: speed, eta: totalBytesExpectedToWrite > 0 ? Double(max(0,totalBytesExpectedToWrite-totalBytesWritten))/max(1,speed) : nil, finished: false))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let r = downloadTask.response as? HTTPURLResponse, (200...299).contains(r.statusCode) else { throw failure("파일 서버가 다운로드를 거부했습니다 (HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)).") }
            let mime = r.mimeType ?? ""
            guard mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/octet-stream" || mime == "binary/octet-stream" else { throw failure("응답이 미디어 파일이 아닙니다 (\(mime)). 미리보기를 다시 분석해 주세요.") }
            try FileManager.default.moveItem(at: location, to: destination); result = .success(destination)
        } catch { result = .failure(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let c = continuation; continuation = nil; active = nil; self.session = nil; lock.unlock()
        if let error { c?.resume(throwing: error) } else { c?.resume(with: result ?? .failure(failure("저장된 파일이 없습니다."))) }
        session.finishTasksAndInvalidate()
    }
}
