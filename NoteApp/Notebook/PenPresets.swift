import Foundation
import InkKit

/// Remembers colour and width separately for every pen style.
struct PenPresets: Codable, Sendable {
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

    mutating func update(_ tool: InkTool) {
        tools[tool.style.rawValue] = tool
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
