import Testing
@testable import YzVibeKit

struct MarkdownTableTests {
    @Test func screenshotTableAndAlignment() throws {
        let parsed = try #require(MarkdownTable.parse([
            "| 方向 | 产品连接与角色感觉 | 核心轮廓 |",
            "| :--- | :---: | ---: |",
            "| **A · 柚柚随行** | 水果伙伴 | 圆柚子 |",
            "| B | 小女孩 | 柚子头套 |",
            "接下来的段落"
        ], startingAt: 0))
        #expect(parsed.table.header.count == 3)
        #expect(parsed.table.rows.count == 2)
        #expect(parsed.table.rows[0][0] == "**A · 柚柚随行**")
        #expect(parsed.table.alignments == [.leading, .center, .trailing])
        #expect(parsed.nextIndex == 4)
    }
    @Test func escapedPipesMissingCellsAndOptionalOuterPipes() throws {
        let parsed = try #require(MarkdownTable.parse([
            "名称 | 描述", "--- | ---", #"A\|B | `a\|b`"#, "只有一列 |", ""
        ], startingAt: 0))
        #expect(parsed.table.rows == [[#"A\|B"#, #"`a\|b`"#], ["只有一列", ""]])
    }
    @Test func ordinaryPipesAndIncompleteSeparatorAreNotTables() {
        #expect(MarkdownTable.parse(["a | b", "ordinary text"], startingAt: 0) == nil)
        #expect(MarkdownTable.parse(["a | b", "-- | ---"], startingAt: 0) == nil)
        #expect(MarkdownTable.parse(["a | b", "---"], startingAt: 0) == nil)
    }
}
