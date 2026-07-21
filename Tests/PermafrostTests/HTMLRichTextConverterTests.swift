import Foundation
import Testing

@testable import Permafrost

@Suite struct HTMLRichTextConverterTests {
    @Test func convertsBoldHTMLToRTFContainingBoldMarker() throws {
        let html = "<html><body><p><b>Backfire</b></p></body></html>"
        let converter = HTMLRichTextConverter()

        let rtf = try #require(converter.rtfData(fromHTML: Data(html.utf8)))

        let rtfString = try #require(String(data: rtf, encoding: .ascii))
        #expect(rtfString.contains("\\b"))
    }

    @Test func stripsBackgroundColorButKeepsStrikethroughAndBold() throws {
        // Found 2026-07-21 testing against a real product page: the HTML importer
        // faithfully carries over background-color and link color as-is, which reads as
        // "page decoration" once pasted somewhere else (a colored badge became a gray box
        // in Word) rather than "the text." Character-level emphasis stays; color doesn't.
        let html = """
            <html><body>
            <span style="background-color: blue; color: white;"><b>BACKFIRE</b></span>
            <p><s style="color:red;">$79.99 USD</s> <b>$69.99 USD</b></p>
            <p><a href="https://example.com" style="color:blue;">Shipping</a></p>
            </body></html>
            """
        let converter = HTMLRichTextConverter()

        let rtf = try #require(converter.rtfData(fromHTML: Data(html.utf8)))

        let rtfString = try #require(String(data: rtf, encoding: .ascii))
        #expect(!rtfString.contains("\\cb"))
        #expect(!rtfString.contains("\\highlight"))
        #expect(rtfString.contains("\\strike"))
        #expect(rtfString.contains("\\b"))
    }

    @Test func garbageBinaryDoesNotCrash() {
        // NSAttributedString's HTML importer is lenient (verified 2026-07-21): it never
        // throws, even for non-HTML binary — it produces a degenerate, non-empty result
        // rather than failing. So this only asserts "doesn't crash," not "returns nil";
        // real `.html` pasteboard data always comes from a source app that tagged it as
        // HTML, so unparseable-enough-to-be-empty input isn't a realistic capture scenario.
        let converter = HTMLRichTextConverter()

        _ = converter.rtfData(fromHTML: Data([0xFF, 0xFE, 0x00, 0x01]))
    }

    @Test func emptyHTMLReturnsNil() {
        let converter = HTMLRichTextConverter()

        let rtf = converter.rtfData(fromHTML: Data())

        #expect(rtf == nil)
    }
}
