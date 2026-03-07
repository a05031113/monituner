import Foundation

/// Wraps the `m1ddc` CLI for DDC/CI monitor communication.
public final class DDCService {
    public static let m1ddcPath = "/opt/homebrew/bin/m1ddc"

    private var displayMap: [String: Int] = [:]
    /// Per-display max luminance DDC value (queried once per refresh).
    private var maxLuminance: [String: Int] = [:]

    public init() {
        refreshDisplayMap()
    }

    // MARK: - Display Enumeration

    public func refreshDisplayMap() {
        guard let output = runM1DDC(["display", "list"]) else { return }
        displayMap = DDCService.parseDisplayList(output)
        // Query max luminance for each display
        maxLuminance.removeAll()
        for (name, num) in displayMap {
            if let maxOutput = runM1DDC(["display", "\(num)", "get", "luminance", "max"]),
               let maxVal = DDCService.parseIntOutput(maxOutput), maxVal > 0 {
                maxLuminance[name] = maxVal
            }
        }
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

    /// Returns brightness as 0-100% (normalized by monitor's DDC max).
    public func getBrightness(displayName: String) -> Int? {
        guard let num = displayMap[displayName] else { return nil }
        guard let output = runM1DDC(["display", "\(num)", "get", "luminance"]) else { return nil }
        guard let raw = DDCService.parseIntOutput(output) else { return nil }
        let maxVal = maxLuminance[displayName] ?? 100
        return DDCService.ddcToPercent(raw: raw, max: maxVal)
    }

    /// Sets brightness from 0-100% (scaled to monitor's DDC max).
    public func setBrightness(displayName: String, value: Int) -> Bool {
        guard let num = displayMap[displayName] else { return false }
        let percent = min(max(value, 0), 100)
        let maxVal = maxLuminance[displayName] ?? 100
        let raw = DDCService.percentToDDC(percent: percent, max: maxVal)
        return runM1DDC(["display", "\(num)", "set", "luminance", "\(raw)"]) != nil
    }

    /// Returns the DDC max luminance value for a display (nil if unknown).
    public func getMaxLuminance(displayName: String) -> Int? {
        maxLuminance[displayName]
    }

    // MARK: - Helpers

    public static func parseIntOutput(_ output: String) -> Int? {
        Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Convert raw DDC value to 0-100%.
    public static func ddcToPercent(raw: Int, max: Int) -> Int {
        guard max > 0 else { return 0 }
        return min(100, Int(round(Double(raw) / Double(max) * 100.0)))
    }

    /// Convert 0-100% to raw DDC value.
    public static func percentToDDC(percent: Int, max: Int) -> Int {
        guard max > 0 else { return 0 }
        return min(max, Int(round(Double(percent) / 100.0 * Double(max))))
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
