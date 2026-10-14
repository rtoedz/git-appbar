import Foundation

public struct GitError: Error, LocalizedError, Sendable {
    public let args: [String]
    public let exitCode: Int32
    public let stderr: String
    public var timedOut = false

    public var errorDescription: String? {
        if timedOut {
            return "git \(args.first ?? "") tidak merespons dan dihentikan. Cek koneksi atau autentikasi remote."
        }
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "git \(args.joined(separator: " ")) gagal (\(exitCode))" : msg
    }
}

/// Runs git as a child process. GUI apps don't inherit the shell PATH, so it is
/// set explicitly — otherwise hooks (husky), git-lfs and credential helpers fail.
public struct GitRunner: Sendable {
    public static let searchPath = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ].joined(separator: ":")

    /// Network commands (fetch/pull/push) get this long before being killed.
    public static let networkTimeout: TimeInterval = 120

    public let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func run(_ args: [String], in directory: URL, timeout: TimeInterval? = nil) async throws -> String {
        let gitPath = self.gitPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = args
                process.currentDirectoryURL = directory

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = GitRunner.searchPath
                env["LC_ALL"] = "C"
                // Never wait on an interactive prompt nobody can answer.
                env["GIT_TERMINAL_PROMPT"] = "0"
                if env["GIT_SSH_COMMAND"] == nil {
                    env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=15"
                }
                process.environment = env

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timedOut = TimedOutFlag()
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            timedOut.set()
                            process.terminate()
                        }
                    }
                }

                // Drain stderr concurrently so a full pipe can't deadlock the child.
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                group.wait()

                if process.terminationStatus == 0 && !timedOut.value {
                    continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                } else {
                    var error = GitError(
                        args: args,
                        exitCode: process.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self)
                    )
                    error.timedOut = timedOut.value
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func status(of repo: URL) async throws -> RepoStatus {
        let out = try await run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: repo)
        return GitStatusParser.parse(out)
    }
}

private final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
