#!/usr/bin/env python3
"""The library sources each standalone Swift probe under tools/probes compiles against.

Probes are single files compiled with swiftc beside the library files they call, not through
SwiftPM, so the list of those files lives here alone: the gates read it, the documented capture
recipes read it, and test_swift_sources.py checks that every listed file exists. Run from the
repository root to print a probe's sources for a swiftc command line:

    swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \\
        -o /tmp/capture-layout-fixture
"""
import sys

LIBRARY = 'Sources/PDFReflowLib'
PROBES = 'tools/probes'

# Native text extraction: NativeTextReader, the readers it consults, and the value types it returns.
EXTRACTION = ['NativeTextReader.swift', 'NativeSpacingReader.swift', 'NativeSpacingOwnership.swift',
              # A margin rule an inherited recognition read as letters is cut where the box is
              # formed (#264), so every probe that extracts text compiles the reading with it.
              'MarginRuleMarks.swift',
              # A row of two columns PDFKit merged into one line is cut where the box is formed
              # (#270), for the same reason and from the same character boxes.
              'ColumnGutterCut.swift', 'DetachedTextReader.swift', 'TextLineGeometry.swift',
              'GlyphIdentityReader.swift', 'DiscretionaryHyphenReader.swift',
              'GlyphIndexDecoder.swift', 'TextEncodingCheck.swift',
              'EnglishText.swift', 'CJKText.swift', 'ArabicText.swift', 'VerticalJapaneseColumns.swift', 'ContentStreamWalk.swift',
              'CGPDFObjects.swift',
              'AnchorMatcher.swift',
              # `PageContent` carries each located table's cell counts (#31), so every probe
              # compiling the model compiles the measurement with it.
              'TableCellEvidence.swift',
              'DocumentModel.swift', 'ReflowDocument.swift', 'ConversionTypes.swift',
              'MathExpression.swift', 'FormBlank.swift']
# Page rasterization with the options and model types it takes.
RASTER = ['PageRasterizer.swift', 'ImageContentClassifier.swift', 'ConversionTypes.swift',
          'TableCellEvidence.swift', 'DocumentModel.swift', 'ReflowDocument.swift',
          'MathExpression.swift', 'FormBlank.swift']

# Vision recognition: `OCRReader` with the two measurements it applies to its own reading.
RECOGNITION = RASTER + ['OCRReader.swift', 'OCRTextCoverage.swift', 'CJKText.swift', 'EnglishText.swift']

PROBE_SOURCES = {
    'probe-pdfkit-concurrency.swift': EXTRACTION,       # native mode; -D PDFREFLOW_NATIVE
    'probe-pdfkit-memory.swift': [],                    # Apple SDKs only
    'probe-raster-environment.swift': RASTER,
    'probe-raster-sweep.swift': RASTER,
    'probe-vision-titles.swift': RASTER,
    # A password reaches every open through PDFPageSource's SourceDocument, so the two probes
    # that open a document themselves compile it and the options type it takes (#252).
    'inspect-structure.swift': ['StructureTreeReader.swift', 'CGPDFObjects.swift',
                                'TableCellEvidence.swift',
                                'DocumentModel.swift', 'ReflowDocument.swift',
                                'ConversionTypes.swift', 'MathExpression.swift', 'PDFPageSource.swift', 'EmbeddedImageReader.swift',
                                'ImageAlphaBounds.swift', 'SourceMetadata.swift',
                                'XMLText.swift', 'FormBlank.swift'],
    'inspect-chapter-boundaries.swift': EXTRACTION + ['ChapterBoundaryReader.swift', 'PDFPageSource.swift',
                                                      'EmbeddedImageReader.swift', 'ImageAlphaBounds.swift',
                                                      'SourceMetadata.swift', 'XMLText.swift'],
    'capture-layout-fixture.swift': EXTRACTION + ['GraphicsReader.swift', 'PanelOutline.swift'],
    'capture-spacing-source.swift': [],                 # Apple SDKs only
    'capture-algebra-layout.swift': EXTRACTION + ['GraphicsReader.swift', 'PanelOutline.swift'],
    # `OCRReader` checks its own reading against the page's ink (#116) and measures how much of
    # each table it located it transcribed (#31), so it needs both measurements.
    'capture-ocr-layout-fixture.swift': RECOGNITION,
    'probe-ocr-text-loss.swift': RECOGNITION,
    # #240 weighs a second signal against the same measurement, so it needs the same sources.
    'probe-ocr-coverage-signals.swift': RECOGNITION,
    # #31 measures the cells of the tables a recognition of a scanned page locates.
    'probe-table-cell-evidence.swift': RECOGNITION,
    'audit-report-margins.swift': EXTRACTION + ['FurnitureDetector.swift'],
    'audit-invisible-spacing.swift': EXTRACTION + ['GraphicsReader.swift', 'PanelOutline.swift'],
}


def probe_path(probe):
    """The probe's path relative to the repository root."""
    return f'{PROBES}/{probe}'


def library_sources(probe):
    """The library files the probe compiles against, relative to the repository root."""
    return [f'{LIBRARY}/{name}' for name in PROBE_SOURCES[probe]]


def sources(probe):
    """Every file a swiftc invocation of the probe needs: its library sources, then the probe."""
    return library_sources(probe) + [probe_path(probe)]


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1 or argv[0] not in PROBE_SOURCES:
        print('usage: swift_sources.py PROBE\nprobes: ' + ' '.join(sorted(PROBE_SOURCES)), file=sys.stderr)
        return 2
    print(' '.join(sources(argv[0])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
