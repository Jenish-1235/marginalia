import Testing
@testable import Marginalia

struct MetadataExtractorTests {
    @Test func findsArxivID() {
        let text = "Attention Is All You Need\narXiv:1706.03762v7 [cs.CL] 2 Aug 2023"
        #expect(MetadataExtractor.firstArxivID(in: text) == "1706.03762")
        #expect(MetadataExtractor.yearFromArxivID("1706.03762") == 2017)
    }

    @Test func findsDOIWithoutTrailingPunctuation() {
        let text = "Published version: https://doi.org/10.1145/3292500.3330701."
        #expect(MetadataExtractor.firstDOI(in: text) == "10.1145/3292500.3330701")
    }

    @Test func rejectsJunkTitles() {
        #expect(MetadataExtractor.usableTitle("Microsoft Word - draft3.docx") == nil)
        #expect(MetadataExtractor.usableTitle("paper.pdf") == nil)
        #expect(MetadataExtractor.usableTitle("Deep Residual Learning") == "Deep Residual Learning")
    }

    @Test func cleansFileNames() {
        #expect(MetadataExtractor.cleanedFileName("designing_data-intensive__applications") ==
                "designing data intensive applications")
    }

    @Test func guessesKind() {
        #expect(MetadataExtractor.guessKind(pageCount: 400, leadingText: "", hasIdentifier: false) == .book)
        #expect(MetadataExtractor.guessKind(pageCount: 12, leadingText: "Abstract. We", hasIdentifier: false) == .paper)
        #expect(MetadataExtractor.guessKind(pageCount: 30, leadingText: "", hasIdentifier: true) == .paper)
    }
}
