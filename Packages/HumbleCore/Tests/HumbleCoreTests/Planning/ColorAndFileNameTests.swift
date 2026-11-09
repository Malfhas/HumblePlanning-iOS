import Foundation
import Testing
@testable import HumbleCore

@Suite struct RGBColorTests {
    @Test func readsSixHexDigitsWithOrWithoutHash() {
        #expect(RGBColor(hex: "#FF8000") == RGBColor(red: 255, green: 128, blue: 0))
        #expect(RGBColor(hex: "ff8000") == RGBColor(red: 255, green: 128, blue: 0))
        #expect(RGBColor(hex: "  #5a17ff \n") == RGBColor(red: 0x5A, green: 0x17, blue: 0xFF))
        for bad in [nil, "", "#", "#FFF", "#FF80000", "##FF8000", "#GG8000", "-12345", "+12345", "FF 800", "#ＦＦ8000"] {
            #expect(RGBColor(hex: bad) == nil, "\(bad ?? "nil")")
        }
        #expect(RGBColor(hex: "#5a17ff")?.hex == "#5A17FF")
    }

    @Test func textIsDarkOnLightBackgrounds() {
        #expect(RGBColor.white.luminance == 1)
        #expect(RGBColor(red: 0, green: 0, blue: 0).luminance == 0)
        #expect(abs(RGBColor(hex: "#BBBBBB")!.luminance - 0.4969) < 0.001)
        #expect(RGBColor(hex: "#FFFF00")!.contentColorIsDark)
        #expect(RGBColor(hex: "#CCCCCC")!.contentColorIsDark)
        #expect(!RGBColor(hex: "#BBBBBB")!.contentColorIsDark)
        #expect(!RGBColor(hex: "#5A17FF")!.contentColorIsDark)
        #expect(RGBColor(hex: "#F97316")!.contentColor == .white)
        #expect(RGBColor.white.contentColor == RGBColor(hex: "#18181B"))
    }

    @Test func holidaysFallBackOnOrange() {
        #expect(Holiday(id: "h", date: "2026-11-11").tint == RGBColor(hex: "#F97316"))
        #expect(Holiday(id: "h", date: "2026-11-11", color: "#00FF00").tint == RGBColor(hex: "#00FF00"))
    }
}

/// `AvatarUrlTest` (test 60), the initials of `Avatar`, and `safeFileName` (test 63).
@Suite struct FileNameTests {
    private let server = "https://planning.example"

    @Test func storedPathIsServedUnderTheApi_inWebp() {
        #expect(avatarURL(server: server, image: "avatars/u1.avif")?.absoluteString == "\(server)/api/avatars/u1.webp")
        #expect(avatarURL(server: server, image: "/api/avatars/u1.avif")?.absoluteString == "\(server)/api/avatars/u1.webp")
        #expect(avatarURL(server: server, image: "u1.png")?.absoluteString == "\(server)/api/avatars/u1.png")
        #expect(avatarURL(server: server, image: " avatars/u-1_a.AVIF ")?.absoluteString == "\(server)/api/avatars/u-1_a.webp")
    }

    @Test func nothingElseThanAFileOfTheFolder() {
        for image in [nil, "", "https://elsewhere.example/a.png", "//elsewhere.example/a.png", "avatars/../secret",
                      "../a.png", ".hidden", "a b.png", "é.png", "a/b.png", "a.png?x=1"] {
            #expect(avatarURL(server: server, image: image) == nil, "\(image ?? "nil")")
        }
    }

    @Test func initialsOfTheFirstTwoWords() {
        #expect(avatarInitials("Liam Turner") == "LT")
        #expect(avatarInitials("jean-pierre martin") == "JP")
        #expect(avatarInitials("(Ann) 2nd team") == "A2")
        #expect(avatarInitials("Émile") == "É")
        #expect(avatarInitials("  ") == "")
    }

    @Test func aFileNameIsNeverAPath() {
        #expect(safeFileName("../../report.pdf", fallback: "x") == "report.pdf")
        #expect(safeFileName("..\\..\\report.pdf", fallback: "x") == "report.pdf")
        #expect(safeFileName(".hidden", fallback: "x") == "hidden")
        #expect(safeFileName("..", fallback: "x") == "x")
        #expect(safeFileName("", fallback: "x") == "x")
        #expect(safeFileName("folder/", fallback: "x") == "x")
        #expect(safeFileName("re\u{0}po\u{1F}rt\u{85}.pdf", fallback: "x") == "report.pdf")
        #expect(safeFileName("  .notes.txt ", fallback: "x") == "notes.txt")
        #expect(safeFileName("Devis été.pdf", fallback: "x") == "Devis été.pdf")
    }
}
