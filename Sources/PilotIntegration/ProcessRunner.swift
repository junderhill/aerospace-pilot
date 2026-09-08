import Foundation
import Darwin

public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public init(status: Int32 = 0, stdout: String = "", stderr: String = "") {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
}

public struct CommandFailure: Error, LocalizedError, Sendable, Equatable {
    public enum Kind: String, Sendable { case missingExecutable, launch, timeout, cancelled, exit, outputLimit, malformedResponse }
    public let kind: Kind
    public let executable: String
    public let arguments: [String]
    public let detail: String
    public let status: Int32?
    public init(_ kind: Kind, executable: String, arguments: [String], detail: String, status: Int32? = nil) {
        self.kind = kind; self.executable = executable; self.arguments = arguments; self.detail = detail; self.status = status
    }
    public var errorDescription: String? { "\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.first ?? ""): \(detail)" }
}

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}

/// Files avoid pipe-buffer deadlocks even when a process writes both streams heavily.
/// Only the child started by this invocation is terminated on timeout/cancellation.
public struct ProcessRunner: ProcessRunning {
    public let outputLimit: Int
    public init(outputLimit: Int = 4 * 1024 * 1024) { self.outputLimit = outputLimit }

    public func run(executable: URL, arguments: [String], timeout: TimeInterval = 5) async throws -> CommandResult {
        func failure(_ kind: CommandFailure.Kind, _ detail: String, status: Int32? = nil) -> CommandFailure {
            CommandFailure(kind, executable: executable.path, arguments: arguments, detail: detail, status: status)
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw failure(.missingExecutable, "Executable is missing or not executable: \(executable.path)")
        }
        guard timeout > 0 else { throw failure(.timeout, "Deadline must be positive.") }
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pilot-process-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let outURL = temporary.appendingPathComponent("stdout")
        let errURL = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw failure(.launch, error.localizedDescription) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw failure(.timeout, "Command exceeded \(timeout) seconds.") }
                for file in [outURL, errURL] {
                    // URL resource values may cache file sizes; stat each growing output file.
                    let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
                    guard size <= outputLimit else { throw failure(.outputLimit, "Command output exceeded \(outputLimit) bytes.") }
                }
                try await Task.sleep(for: .milliseconds(15))
            }
        } catch {
            if process.isRunning {
                process.terminate()
                // Cancellation must not cancel the bounded termination grace period.
                let grace = ContinuousClock.now.advanced(by: .milliseconds(150))
                while process.isRunning && ContinuousClock.now < grace { usleep(5_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            if error is CancellationError { throw failure(.cancelled, "Command cancelled.") }
            throw error
        }
        func read(_ url: URL) throws -> String {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: outputLimit + 1) ?? Data()
            guard data.count <= outputLimit else { throw failure(.outputLimit, "Command output exceeded \(outputLimit) bytes.") }
            return String(decoding: data, as: UTF8.self)
        }
        return try CommandResult(status: process.terminationStatus, stdout: read(outURL), stderr: read(errURL))
    }
}
