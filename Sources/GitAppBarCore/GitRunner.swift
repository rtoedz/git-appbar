import Foundation

public struct GitError: Error, LocalizedError, Sendable {
    public let args: [String]
    public let exitCode: Int32
    public let stderr: String

    public var errorDescription: String? {
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "git \(args.joined(separator: " ")) gagal (\(exitCode)): \(msg)"
    }
}

/// Runs git as a child process. GUI apps don't inherit the shell PATH, so it is
/// set explicitly — otherwise hooks (husky), git-lfs and credential helpers fail.
public struct GitRunner: Sendable {
    public static let searchPath = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ].joined(separator: ":")

    public let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func run(_ args: [String], in directory: URL) async throws -> String {
        let gitPath = self.gitPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = args
                process.currentDirectoryURL = directory

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = GitRunner.searchPath
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["LC_ALL"] = "C"
                process.environment = env

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
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

                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                } else {
                    continuation.resume(throwing: GitError(
                        args: args,
                        exitCode: process.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self)
                    ))
                }
            }
        }
    }

    public func status(of repo: URL) async throws -> RepoStatus {
        let out = try await run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: repo)
        return GitStatusParser.parse(out)
    }
}
