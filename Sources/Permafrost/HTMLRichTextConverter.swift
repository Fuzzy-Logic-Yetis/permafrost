import AppKit

/// Best-effort HTML → RTF conversion (ADR-019), so a browser-sourced copy — which carries
/// `public.html`, never `.rtf` — still gets *some* rich-text capture instead of none. Not
/// guaranteed lossless: RTF can't represent everything CSS can. Must run off the main actor
/// (`CaptureSaveQueue`, never `PasteboardWatcher`'s main-actor poll loop) — the HTML
/// importer has a one-time ~0.65s warmup cost on first use in this process (spiked
/// 2026-07-21), trivial after that (~2.5ms).
protocol HTMLRichTextConverting: Sendable {
    func rtfData(fromHTML html: Data) -> Data?
}

struct HTMLRichTextConverter: HTMLRichTextConverting {
    /// Attributes stripped before conversion — page/site decoration, not "the text" (found
    /// 2026-07-21: converting a real product page carried its colored badge background
    /// through as a gray box in Word, and its link color, neither of which the project
    /// owner wanted). Character-level emphasis (bold/italic via `.font`, `.strikethroughStyle`,
    /// `.underlineStyle`) is deliberately kept — only the *color* attached to it goes.
    private static let strippedAttributes: [NSAttributedString.Key] = [
        .backgroundColor, .foregroundColor, .strikethroughColor, .underlineColor,
    ]

    func rtfData(fromHTML html: Data) -> Data? {
        // The HTML importer is lenient — it never throws, even for empty or garbage input,
        // producing a degenerate zero-length result instead (verified 2026-07-21). Checking
        // `length > 0` is what actually distinguishes "nothing usable" from real content.
        guard
            let attributed = try? NSAttributedString(
                data: html,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            ),
            attributed.length > 0
        else { return nil }

        let sanitized = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: sanitized.length)
        for key in Self.strippedAttributes {
            sanitized.removeAttribute(key, range: fullRange)
        }

        return try? sanitized.data(
            from: NSRange(location: 0, length: sanitized.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
