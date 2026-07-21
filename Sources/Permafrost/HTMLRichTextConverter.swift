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
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
