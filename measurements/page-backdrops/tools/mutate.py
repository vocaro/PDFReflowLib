#!/usr/bin/env python3
"""usage: mutate.py  apply each #164 negative-control mutation to the pipeline in turn, run
PageBackdropTests and IllustratedPageTests, and restore the file.

Run from the repository root. Prints the failing tests for each mutation."""
import re, subprocess, sys
from pathlib import Path

PIPELINE = Path('Sources/PDFReflowLib/PDFReflowLibPipeline.swift')
FILTER = 'PageBackdropTests|IllustratedPageTests'
MUTATIONS = {
    'a page-sized image is a backdrop': (
        'return !pageSized.isEmpty && pageSized.allSatisfy { $0.filled && !$0.image }',
        'return !pageSized.isEmpty && pageSized.allSatisfy { $0.filled || $0.image }'),
    'a page-sized outline is a backdrop': (
        'return !pageSized.isEmpty && pageSized.allSatisfy { $0.filled && !$0.image }',
        'return !pageSized.isEmpty'),
    'a page with no page-sized paint is a backdrop page': (
        'return !pageSized.isEmpty && pageSized.allSatisfy { $0.filled && !$0.image }',
        'return pageSized.allSatisfy { $0.filled && !$0.image }'),
    'art holding text keeps its crop': (
        '            return coversPage(paint.rect, bounds) || lines.contains { mostlyInside($0.rect, paint.rect) }',
        '            return coversPage(paint.rect, bounds)'),
    'art inside a text box keeps its crop': (
        '            return !boxes.contains { $0 != paint.rect && $0.contains(paint.rect) }',
        '            return true'),
    'an image inside a text box is decoration': (
        '            if paint.image { return true }\n',
        ''),
    'the backdrop is composed with every other paint': (
        'let composed = TintDetector.compose(art ?? graphics.paints, lines: content.lines, bounds: bounds)',
        'let composed = TintDetector.compose(graphics.paints, lines: content.lines, bounds: bounds)'),
    'a backdrop page may lose every word to its crops': (
        'return outcome.taken * (backdrop ? 2 : 10) <= outcome.total',
        'return outcome.taken * (backdrop ? 0 : 10) <= outcome.total'),
    'a backdrop page keeps #117 word share': (
        'return outcome.taken * (backdrop ? 2 : 10) <= outcome.total',
        'return outcome.taken * 10 <= outcome.total'),
    'a crop covering the page is allowed': (
        '        guard !outcome.coversPage else { return false }\n',
        ''),
    'no page keeps a backdrop reference': (
        '            if !content.requiresPageImage, !imageBackedText, backdropReference {',
        '            if false, !content.requiresPageImage, !imageBackedText, backdropReference {'),
    'every backdrop page keeps a reference': (
        '                    && cropOutcome(content).taken > 0',
        '                    && cropOutcome(content).taken >= 0'),
}
original = PIPELINE.read_text()
try:
    for name, (old, new) in MUTATIONS.items():
        assert original.count(old) == 1, name
        PIPELINE.write_text(original.replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        failing = sorted(set(re.findall(r'✘ Test (\w+)\(', run.stdout + run.stderr)))
        if not failing and 'error:' in run.stderr:
            failing = ['(did not build)']
        print(f'{name}: {", ".join(failing) or "NO FAILURES"}')
        sys.stdout.flush()
        PIPELINE.write_text(original)
finally:
    PIPELINE.write_text(original)
