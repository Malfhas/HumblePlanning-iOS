import Testing
@testable import HumbleCore

/// The Markdown cases of `ConversationHelpersTest`, plus the rules of `Markdown.kt` they rest on.
struct MarkdownTests {
    // MARK: - Blocks

    @Test func paragraphsBulletsAndHeadings() {
        #expect(Markdown.blocks("# Title\n\nOne\nstill one\n\n- a\n* b\n\nTwo") == [
            .heading(level: 1, [.text("Title")]),
            .paragraph([.text("One\nstill one")]),
            .bullet([.text("a")]),
            .bullet([.text("b")]),
            .paragraph([.text("Two")]),
        ])
    }

    @Test func headingsOfEveryLevel() {
        #expect(Markdown.blocks("## Two\n###### Six") == [.heading(level: 2, [.text("Two")]), .heading(level: 6, [.text("Six")])])
        #expect(Markdown.blocks("  ###   Indented  ") == [.heading(level: 3, [.text("Indented")])])
        #expect(Markdown.blocks("####### Seven") == [.paragraph([.text("####### Seven")])])
        #expect(Markdown.blocks("#Tight") == [.paragraph([.text("#Tight")])])
        #expect(Markdown.blocks("# ") == [.paragraph([.text("#")])])
        #expect(Markdown.blocks("#\tTab") == [.heading(level: 1, [.text("Tab")])])
        #expect(Markdown.blocks("# **Bold** title") == [.heading(level: 1, [.bold("Bold"), .text(" title")])])
    }

    @Test func bullets() {
        #expect(Markdown.blocks("   - indented\n•\tdot\n*  star  ") == [
            .bullet([.text("indented")]),
            .bullet([.text("dot")]),
            .bullet([.text("star  ")]),
        ])
        #expect(Markdown.blocks("- ") == [.bullet([])])
        #expect(Markdown.blocks("-tight") == [.paragraph([.text("-tight")])])
        #expect(Markdown.blocks("- # not a heading") == [.bullet([.text("# not a heading")])])
        #expect(Markdown.blocks("- **Liam** is free") == [.bullet([.bold("Liam"), .text(" is free")])])
        #expect(Markdown.blocks("* * *") == [.bullet([.text("* *")])])
    }

    @Test func aBulletEndsTheParagraphAbove() {
        #expect(Markdown.blocks("Here:\n- a\nafter") == [
            .paragraph([.text("Here:")]),
            .bullet([.text("a")]),
            .paragraph([.text("after")]),
        ])
    }

    @Test func paragraphLinesAreTrimmedAndBlankLinesSeparate() {
        #expect(Markdown.blocks("\n\n  One  \n\t two\n \t \nThree\n\n") == [
            .paragraph([.text("One\ntwo")]),
            .paragraph([.text("Three")]),
        ])
        #expect(Markdown.blocks("") == [])
        #expect(Markdown.blocks(" \n ") == [])
    }

    @Test func everyLineEndingSplits() {
        #expect(Markdown.blocks("One\r\ntwo\rthree\n\r\nFour") == [.paragraph([.text("One\ntwo\nthree")]), .paragraph([.text("Four")])])
    }

    @Test func whatIsNotSupportedStaysLiteral() {
        #expect(Markdown.blocks("1. first\n2. second") == [.paragraph([.text("1. first\n2. second")])])
        #expect(Markdown.blocks("> quoted") == [.paragraph([.text("> quoted")])])
        #expect(Markdown.blocks("| a | b |") == [.paragraph([.text("| a | b |")])])
        #expect(Markdown.inlines("*italic* _also_ [link](https://example.com)") == [.text("*italic* _also_ [link](https://example.com)")])
    }

    @Test func spacesAreTheAsciiOnesOfTheAndroidPattern() {
        // `\s` of Java is ASCII: a no-break space does not make a bullet nor a heading.
        #expect(Markdown.blocks("-\u{00A0}item") == [.paragraph([.text("-\u{00A0}item")])])
        #expect(Markdown.blocks("#\u{00A0}Title") == [.paragraph([.text("#\u{00A0}Title")])])
        // ...but trimming is Kotlin's, which removes it.
        #expect(Markdown.blocks("\u{00A0}text\u{00A0}") == [.paragraph([.text("text")])])
    }

    // MARK: - Inline

    @Test func boldAndCodeLoseTheirMarkers() {
        let inlines = Markdown.inlines("a **b** `c` d")
        #expect(inlines == [.text("a "), .bold("b"), .text(" "), .code("c"), .text(" d")])
        #expect(inlines.plainText == "a b c d")
        #expect(inlines.filter { if case .text = $0 { false } else { true } }.count == 2)
    }

    @Test func anOpenMarkerStaysAsText() {
        #expect(Markdown.inlines("a **b") == [.text("a **b")])
        #expect(Markdown.inlines("a `b") == [.text("a `b")])
    }

    @Test func whileStreamingTheBoldAppearsOnlyOnceClosed() {
        #expect(Markdown.inlines("Liam is **fr") == [.text("Liam is **fr")])
        #expect(Markdown.inlines("Liam is **free*") == [.text("Liam is **free*")])
        #expect(Markdown.inlines("Liam is **free**") == [.text("Liam is "), .bold("free")])
    }

    @Test func emptyMarkersStayLiteral() {
        #expect(Markdown.inlines("****") == [.text("****")])
        #expect(Markdown.inlines("``") == [.text("``")])
        #expect(Markdown.inlines("**") == [.text("**")])
        #expect(Markdown.inlines("") == [])
    }

    @Test func markersPairFromTheLeftWithoutNesting() {
        #expect(Markdown.inlines("***a***") == [.bold("*a"), .text("*")])
        #expect(Markdown.inlines("**a `b` c**") == [.bold("a `b` c")])
        #expect(Markdown.inlines("`**x**`") == [.code("**x**")])
        #expect(Markdown.inlines("**a** and **b**") == [.bold("a"), .text(" and "), .bold("b")])
        #expect(Markdown.inlines("`a``b`") == [.code("a"), .code("b")])
    }

    @Test func boldMaySpanTheLinesOfAParagraph() {
        #expect(Markdown.blocks("**one\ntwo**") == [.paragraph([.bold("one\ntwo")])])
    }

    @Test func fencedCodeBackticksPairUpInline() {
        #expect(Markdown.blocks("```swift\nlet x = 1\n```") == [.paragraph([.text("``"), .code("swift\nlet x = 1\n"), .text("``")])])
    }

    @Test func aCombiningMarkDoesNotHideAMarker() {
        #expect(Markdown.inlines("**\u{0301}a**") == [.bold("\u{0301}a")])
    }

    @Test func blocksGiveTheirInlines() {
        #expect(MarkdownBlock.heading(level: 2, [.text("a")]).inlines == [.text("a")])
        #expect(MarkdownBlock.bullet([.code("b")]).inlines == [.code("b")])
        #expect(MarkdownBlock.paragraph([.bold("c")]).inlines.plainText == "c")
    }
}
