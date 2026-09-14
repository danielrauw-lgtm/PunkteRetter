import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ProcessRunnerError: LocalizedError, Equatable, Sendable {
    case timedOut(seconds: Int)
    case terminatedBySignal(Int32)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Der Vorgang wurde nach \(seconds) Sekunden beendet, weil keine Antwort kam."
        case .terminatedBySignal(let signal):
            return "Der Hilfsprozess wurde unerwartet durch Signal \(signal) beendet."
        }
    }
}

@MainActor
public enum ProcessRunner {
    /// Startet einen Helper ohne die auf manchen macOS-Versionen fehleranfällige
    /// Kombination aus nachträglich gesetztem terminationHandler und endlosem Warten.
    public static func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()

        let startedAt = Date()
        do {
            while process.isRunning && Date().timeIntervalSince(startedAt) < timeout {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch {
            stop(process)
            throw error
        }

        if !process.isRunning {
            if process.terminationReason == .uncaughtSignal {
                throw ProcessRunnerError.terminatedBySignal(process.terminationStatus)
            }
            return process.terminationStatus
        }

        stop(process)
        throw ProcessRunnerError.timedOut(seconds: max(1, Int(timeout.rounded())))
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let graceDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

#if canImport(Darwin)
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
#elseif canImport(Glibc)
        if process.isRunning {
            Glibc.kill(process.processIdentifier, SIGKILL)
        }
#endif
    }
}
