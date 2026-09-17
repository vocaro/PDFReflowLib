"""Mutation run for #145 (run from the worktree root). Each mutant replaces one exact snippet in
LayoutReconstructor.swift, runs the #145 and #118 tests, and restores the file.
usage: mutate.py [name ...]"""
import re
import subprocess
import sys

SRC = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
TESTS = ['Tests/PDFReflowLibTests/CaptionWrapsAndOpenSentencesTests.swift',
         'Tests/PDFReflowLibTests/ColumnContinuationRecountTests.swift']
names = []
for t in TESTS:
    names += re.findall(r'@Test func (\w+)\(', open(t).read())
FILTER = '|'.join(names)

M = {
    'noop': ('joinWrappedCaptionLines(&result', 'joinWrappedCaptionLines(&result'),
    'caption-rule-off': ('        joinWrappedCaptionLines(&result, page: page, body: body, vocabulary: vocabulary, warnings: &warnings)\n', ''),
    'caption-adjacent-allowed': ('blocks.indices.dropFirst(index + 2)', 'blocks.indices.dropFirst(index + 1)'),
    'caption-closed-sentence-allowed': ('isCaption(caption.text), !endsSentence(caption),', 'isCaption(caption.text),'),
    'caption-candidate-caption-allowed': ('!isCaption(text.text), let first = firstLine', 'let first = firstLine'),
    'caption-body-type-off': ('$0.fontSize < body * 0.95 && wrapsCaption', 'wrapsCaption'),
    'caption-beneath-off': ('return beneath.contains(first)', 'return true'),
    'wrap-size-off': ('guard first.fontSize < last.fontSize * 1.15, gap', 'guard gap'),
    'wrap-above-off': ('gap > -size * 0.4, gap < size * 0.9,', 'gap < size * 0.9,'),
    'wrap-leading-off': ('gap > -size * 0.4, gap < size * 0.9,', 'gap > -size * 0.4,'),
    'wrap-edge-off': ('abs(first.rect.minX - last.rect.minX) <= body * 0.5 || abs(first.rect.midX - last.rect.midX) <= body * 0.5', 'true'),
    'wrap-centre-off': (' || abs(first.rect.midX - last.rect.midX) <= body * 0.5,', ','),
    'wrap-between-off': ('        return !page.lines.contains { other in\n            other != last && other != first && other.rect.midY < last.rect.midY && other.rect.midY > first.rect.midY\n                && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX\n                && other.rect.maxX > last.rect.minX',
                         '        return !page.lines.contains { other in\n            false && other != first && other.rect.midY < last.rect.midY && other.rect.midY > first.rect.midY\n                && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX\n                && other.rect.maxX > last.rect.minX'),
    'comma-page-off': ('\n                || right.text.first?.isLowercase == true && endsOnAComma(last, body: max(4, bodySize(previousPage.lines))),', ','),
    'comma-page-lowercase-off': ('|| right.text.first?.isLowercase == true && endsOnAComma(last, body: max(4, bodySize(previousPage.lines)))', '|| endsOnAComma(last, body: max(4, bodySize(previousPage.lines)))'),
    'comma-column-off': ('\n                || right.text.first?.isLowercase == true && endsOnAComma(last, body: body) else { return false }', ' else { return false }'),
    'comma-column-lowercase-off': ('|| right.text.first?.isLowercase == true && endsOnAComma(last, body: body) else', '|| endsOnAComma(last, body: body) else'),
    'comma-letter-off': ('text.hasSuffix(","), text.dropLast().last?.isLetter == true else', 'text.hasSuffix(",") else'),
    'comma-comma-off': ('guard text.hasSuffix(","), text.dropLast().last?.isLetter == true else', 'guard text.last != nil, text.dropLast().last?.isLetter == true else'),
    'comma-words-off': ('return wordCount(text) >= 3 && last.rect.width >= body * 12 && Int', 'return last.rect.width >= body * 12 && Int'),
    'comma-width-off': ('wordCount(text) >= 3 && last.rect.width >= body * 12 && Int(last.fontSize.rounded()) == Int(body)', 'wordCount(text) >= 3 && Int(last.fontSize.rounded()) == Int(body)'),
    'comma-body-size-off': (' && Int(last.fontSize.rounded()) == Int(body)\n', '\n'),
    'tag-off': ('if sameTag || leavesParenthesisOpen(left.text) { return true }', 'if leavesParenthesisOpen(left.text) { return true }'),
    'paren-off': ('if sameTag || leavesParenthesisOpen(left.text) { return true }', 'if sameTag { return true }'),
    'paren-sentence-bound-off': ('.flatMap { Range($0.range, in: text)?.upperBound } ?? text.startIndex', '.map { _ in text.startIndex } ?? text.startIndex'),
    'paren-last-sentence-off': ('sentenceEnd.matches(in: text, range: whole).last', 'sentenceEnd.matches(in: text, range: whole).first'),
    'tag-heading-off': ('left.group == right.group && left.headingLevel == 0 && right.headingLevel == 0', 'left.group == right.group'),
    'tag-group-off': ('left.group == right.group && left.headingLevel == 0', 'left.headingLevel == 0'),
    'tag-page-off': ('sameTag: sameParagraphTag(last, firstLine(of: right.text, in: page.lines))),', 'sameTag: false),'),
    'tag-column-off': ('continuesSentence(left, into: right, sameTag: sameParagraphTag(last, first)),', 'continuesSentence(left, into: right),'),
}

selected = sys.argv[1:] or list(M)
original = open(SRC).read()
results = []
try:
    for name in selected:
        old, new = M[name]
        if original.count(old) != 1:
            results.append((name, f'SNIPPET x{original.count(old)}'))
            print(name, results[-1][1], flush=True)
            continue
        open(SRC, 'w').write(original.replace(old, new))
        r = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        out = r.stdout + r.stderr
        if 'error:' in out and 'Test run' not in out:
            verdict = 'BUILD ERROR'
        else:
            failed = sorted(set(re.findall(r'✘ Test (\w+)\(\) (?:failed|recorded)', out)))
            verdict = ('KILLED by ' + ', '.join(failed)) if failed else 'SURVIVED'
        results.append((name, verdict))
        print(name, verdict, flush=True)
finally:
    open(SRC, 'w').write(original)
with open('/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i145/mutants.log', 'a') as f:
    for name, verdict in results:
        f.write(f'{name}: {verdict}\n')
