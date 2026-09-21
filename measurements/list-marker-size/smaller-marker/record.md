# The other half: a marker smaller than its item

Measured under [#254](https://github.com/vocaro/PDFReflowLib/issues/254), baseline `ff74b33`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults. The first half — a
marker drawn *larger* than its item — is the [parent record](../record.md).

`NativeTextReader.sizeAfterListMarker` corrected a line whose marker was drawn larger than its
text and deliberately left the mirror case alone, because correcting both in the same place
promoted IRS Publication 596's starred footnotes into headings. The issue asked for either
somewhere else for the corrected size to go, or a heading rule that does not read a footnote's
body size as a heading's.

## The rule that landed

The size correction now reads both directions, and a **bulleted line is not a heading**,
whatever size its text is set in: a page that draws a bullet has said the line belongs to a
list. Only the bullet glyphs `• * − – — -` followed by a space count. The alphanumeric markers
`isList` also accepts are deliberately excluded, because `1. Introduction` is a heading in many
books.

## What it costs

Nothing, on all eighteen corpus books: every one is identical in heading count and in
non-whitespace characters against the baseline, and the lane passes 16 of 18 covered with no
content-contract failures.

That the mechanism fires at all is shown by the variant without the heading rule, built and
converted for this measurement. IRS Publication 596 then reads four of its starred footnotes as
headings —

```
* 如果您要从工作表中查找的金额至少为 19,100 美元, 但低于 19,104 美元…
* 如果您要从工作表中查找的金额至少为 26,200 美元, 但低于 26,214 美元…
* 如果您要从工作表中查找的金额至少为 50,400 美元, 但低于 50,434 美元…
* 如果您要从工作表中查找的金额至少为 68,650 美元, 但低于 68,675 美元…
```

— which is the issue's prediction, at four rather than the three it estimated. With the rule,
that book's 84 headings are the baseline's 84, to the character.

## What this does not fix

The four lines the starred footnotes displace in that variant are themselves false headings that
the baseline already has: the continuation halves of the same footnotes,
`如果您要从工作表中查找的金额不低于 19,104 美元…`, which open with no marker and are read as
headings by size alone. They are unaffected by this change in either direction, and are filed as
[#256](https://github.com/vocaro/PDFReflowLib/issues/256).

Nothing else in the corpus depends on the corrected size today. What it improves is the page's
own body-size statistics and heading ranking, which is where the understated number was wrong;
no book's visible output moves, which is exactly what the issue predicted when it filed this as
low priority.
