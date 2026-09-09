import Foundation
@main struct EngineTests {
    static func main() async throws {
        let r = EngineRunner()
        let result = try await r.run(URL(fileURLWithPath:"/usr/bin/python3"),["-c","import sys; print('x'*200000); print('stderr-ok',file=sys.stderr)"])
        precondition(result.output.count == 200001 && result.errors.contains("stderr-ok"))
        let cancelRunner = EngineRunner()
        let t = Task { try await cancelRunner.run(URL(fileURLWithPath:"/bin/sleep"), ["10"]) }
        try await Task.sleep(nanoseconds:100_000_000); t.cancel()
        do { _ = try await t.value; fatalError("Cancellation failed") } catch is CancellationError {}
        print("PASS: concurrent pipe draining, capture, cancellation")
    }
}
