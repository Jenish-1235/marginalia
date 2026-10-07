import Foundation
import Testing
@testable import Marginalia

struct PaperMetadataTests {
    @Test func parsesArxivFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>ArXiv Query: id_list=1706.03762</title>
          <entry>
            <published>2017-06-12T17:57:34Z</published>
            <title>Attention Is All
              You Need</title>
            <author><name>Ashish Vaswani</name></author>
            <author><name>Noam Shazeer</name></author>
            <author><name>Niki Parmar</name></author>
            <author><name>Jakob Uszkoreit</name></author>
          </entry>
        </feed>
        """
        let paper = try #require(ArxivFeedParser.parse(Data(xml.utf8)))
        #expect(paper.title == "Attention Is All You Need")
        #expect(paper.authors.count == 4)
        #expect(paper.year == 2017)
        #expect(paper.authorLine == "Ashish Vaswani et al.")
    }

    @Test func parsesCrossref() throws {
        let json = """
        {"message": {"title": ["Deep Residual Learning for Image Recognition"],
          "author": [{"given": "Kaiming", "family": "He"}, {"given": "Xiangyu", "family": "Zhang"}],
          "issued": {"date-parts": [[2016, 6]]}}}
        """
        let paper = try #require(PaperMetadata.parseCrossref(Data(json.utf8)))
        #expect(paper.title == "Deep Residual Learning for Image Recognition")
        #expect(paper.authorLine == "Kaiming He, Xiangyu Zhang")
        #expect(paper.year == 2016)
    }
}
