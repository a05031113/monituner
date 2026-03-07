import Foundation

/// Wraps the `m1ddc` CLI for DDC/CI monitor communication.
public final class DDCService {
    public static let m1ddcPath = "/opt/homebrew/bin/m1ddc"

    private var displayMap: [String: Int] = [:]

    public init() {
        refreshDisplayMap()
    }

    // MARK: - Display Enumeration

    public func refreshDisplayMap() {
        guard let output = runM1DDC(["display", "list"]) else { return }
        displayMap = DDCService.parseDisplayList(output)
    }

    /// Parse `m1ddc display list` output. Lines: `[3] VP32UQ (UUID...)`
    public static func parseDisplayList(_ output: String) -> [String: Int] {
        var map: [String: Int] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["),
                  let closeBracket = trimmed.firstIndex(of: "]") else { continue }
            let numStr = trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket]
            guard let num = Int(numStr) else { continue }
            let rest = trimmed[trimmed.index(after: closeBracket)...]
                .trimmingCharacters(in: .whitespaces)
            let name: String
            if let parenIdx = rest.firstIndex(of: "(") {
                name = rest[..<parenIdx].trimmingCharacters(in: .whitespaces)
            } else {
                name = rest
            }
            guard !name.isEmpty, name != "(null)" else { continue }
            map[name] = num
        }
        return map
    }

    public var displayNames: [String] {
        Array(displayMap.keys)
    }

    // MARK: - Brightness

    public func getBrightness(displayName: String) -> Int? {
        guard let num = displayMap[displayName] else { return nil }
        guard let output = runM1DDC(["display", "\(num)", "get", "luminance"]) else { return nil }
        return DDCService.parseIntOutput(output)
    }

    public func setBrightness(displayName: String, value: Int) -> Bool {
        guard let num = displayMap[displayName] else { return false }
        let clamped = min(max(value, 0), 100)
        return runM1DDC(["display", "\(num)", "set", "luminance", "\(clamped)"]) != nil
    }

    // MARK: - Helpers

    public static func parseIntOutput(_ output: String) -> Int? {
        Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    private func runM1DDC(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: DDCService.m1ddcPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
