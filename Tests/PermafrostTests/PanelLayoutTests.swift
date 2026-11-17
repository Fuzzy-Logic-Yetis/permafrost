import Testing

import PermafrostCore
@testable import Permafrost

@MainActor
@Suite struct PanelLayoutTests {
    /// The panel is as wide as its chrome needs (the wider of the chip row and the footer
    /// hints), so neither wraps or clips, and it does not depend on the list content.
    @Test func panelWidthIsTheWiderOfTheChipRowAndTheFooter() {
        let widths = PanelLayout.chromeWidths

        #expect(PanelLayout.width == max(widths.chips, widths.footer))
        #expect(PanelLayout.width >= widths.chips)
        #expect(PanelLayout.width >= widths.footer)
        // Sanity bounds: a real measurement, not zero and not absurd.
        #expect(widths.chips > 300 && widths.chips < 700, "chips \\(widths.chips)")
        #expect(widths.footer > 300 && widths.footer < 700, "footer \\(widths.footer)")
    }

    /// Every chip must fit in one row at the panel width: the row's natural width is the
    /// sum of its chips, so this fails if the width were ever fixed below that again.
    @Test func chipRowFitsOnOneLineAtThePanelWidth() {
        #expect(PanelLayout.chromeWidths.chips <= PanelLayout.width)
    }
}
