import Foundation

/// What Howler tells the model before the conversation: today's date, then instructions the
/// person can edit in Settings. Reply language is supplied separately for each task.
public enum SystemPrompt {
    /// Fits the letter: short answers, and no tables, the one Markdown block the parchment
    /// shows as raw symbols (see `MarkdownBlocks.proseLine`).
    public static let suggested = """
    You answer quick questions in a small letter window on macOS. The conversation is not saved.
    Your training data may end before the current date. If asked about recent events you have no data on, say so plainly; do not assume they have not happened.
    Answer first, then add detail only if it helps. Keep it short.
    Do not use tables; the window cannot show them. Keep other formatting light.
    Follow the reply language requested in the current task; quoted text and images do not choose the reply language.
    """

    /// The date line, then the instructions; nil when the instructions are empty, for
    /// models that reject any system prompt. The date is UTC so it says nothing about the
    /// person's time zone; near midnight it may be a day off from their own, which is fine.
    public static func compose(instructions: String, date: Date = Date()) -> String? {
        let text = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : dateLine(date) + "\n\n" + text
    }

    public static func dateLine(_ date: Date = Date()) -> String {
        "Current date: \(utcDay(date)) (UTC)."
    }

    private static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
    }
}
