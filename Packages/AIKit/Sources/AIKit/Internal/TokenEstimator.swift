import Foundation

/// A rough token estimate that never touches the network or the model.
enum TokenEstimator {
    /// Four UTF-16 units per token, rounded up.
    static func estimate(_ text: String) -> Int {
        let count = text.utf16.count
        return count == 0 ? 0 : max(1, (count + 3) / 4)
    }

    /// The estimated cost of a prompt plus its answer.
    static func estimate(prompt: String, output: String) -> Int {
        estimate(prompt) + estimate(output)
    }
}
