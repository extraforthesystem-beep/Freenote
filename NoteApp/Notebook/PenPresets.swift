import Foundation
import InkKit

/// Remembers colour and width separately for every pen style, plus a separate
/// preset for the highlighter.
struct PenPresets: Codable, Sendable {
    private static let highlighterKey = "highlighter"
    private var tools: [String: InkTool] = [:]

    static let defaultsKey = "noteapp.penPresets.v1"

    static func load() -> PenPresets {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let presets = try? JSONDecoder().decode(PenPresets.self, from: data)
        else {
            return PenPresets()
        }
        return presets
    }

    func tool(for style: PenStyle) -> InkTool {
        tools[style.rawValue] ?? InkTool(style)
    }

    var highlighter: InkTool {
        tools[Self.highlighterKey] ?? .highlighter
    }

    mutating func update(_ tool: InkTool) {
        tools[key(for: tool)] = tool
    }

    /// Writes to `UserDefaults`. Callers debounce this; it is not meant to run
    /// on every slider tick.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func key(for tool: InkTool) -> String {
        tool.isHighlighter ? Self.highlighterKey : tool.style.rawValue
    }
}
