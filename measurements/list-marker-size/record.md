# A list marker's size, and the line's

`NativeTextReader.textLine` takes a line's size from the font of its first character. A list
marker is drawn at whatever size the page likes, so a marker larger than its item states the
marker's size for the whole line (#183). This record measures the three rules tried for it and
why the narrow one is the one that landed — the survey the issue asked for before changing.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Library source at `91dd1ba`
plus this change. Measured 2026-09-20 with the release CLI at library defaults.

## What it costs today

IRS Publication 596 sets a bullet large enough that five of its bulleted sentences read as
headings and appear in the navigation:

```
• 您提交了附表 E（表格 1040）。
• 您申报了个人非商用住宅的租金收入。
• 您在附表 1（表格 1040）第 8z 行申报了表格 8814
• 您因某项被动活动产生了收入或亏损。
• 您在表格 1040 或 1040-SR 第 7a 行申报了含表格
```

## Three rules, measured

**Every character weighted equally.** The line's size becomes the size most of its characters
carry. Four corpus cases fail. The Fed loses all seven of its chapter contents entries — a line
like `1 Overview of the Federal Reserve System . . . . . 1` is mostly leader dots, set small — and
Our Flag loses its Pledge of Allegiance display lines.

**Letters and digits only.** Three of those four recover, but the Fed's contents entries and Our
Flag's Pledge lines still go, and IRS gains three starred footnotes as headings.

| Rule | Corpus cases failing | Fed headings | Our Flag headings | IRS headings |
| --- | ---: | ---: | ---: | ---: |
| unchanged | 0 | 189 | 54 | 89 |
| every character | 4 | 182 | 50 | 82 |
| letters and digits | 1 | 182 | 50 | 82 (3 false gained) |
| a larger marker only | 0 | 189 | 54 | 84 |

**A larger marker only.** Where a line opens with a marker glyph and a space, and that marker is
drawn larger than the text after it, the size comes from the text. Nothing else at the start of a
line qualifies, so a drop cap, an opening quotation mark and a contents line's leaders are
untouched — which is what keeps the Fed and Our Flag exactly as they were.

## What the narrow rule costs

The full corpus lane passes, 18 of 18. Sixteen of the eighteen books are untouched. IRS loses the
five false bullet headings and gains none; its chapter text is identical to the character, and the
107 characters that leave the package are those five entries leaving the navigation, where they
never belonged. Wallace's heading count is unchanged and its non-whitespace text is identical; its
diff is a reordering of contents lines.

A marker *smaller* than its text understates the line in the same way. Correcting that in the same
place promotes IRS Publication 596's starred footnotes — `* 如果您要从工作表中查找的金额至少为
19,100 美元…` — into headings, three of them, so it is deliberately not done here, and is
filed as #254. #183 names #180 as having fixed that half already; it has not, on this tree —
`textLine` took the line's size from its first character in either direction until this change,
which is another instance of the pattern #231 catalogues.
