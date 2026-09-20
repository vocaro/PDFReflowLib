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
              'GlyphIdentityReader.swift', 'ContentStreamWalk.swift', 'CGPDFObjects.swift',
              'AnchorMatcher.swift', 'DocumentModel.swift', 'ReflowDocument.swift', 'ConversionTypes.swift']
# Page rasterization with the options and model types it takes.
RASTER = ['PageRasterizer.swift', 'ConversionTypes.swift', 'DocumentModel.swift', 'ReflowDocument.swift']

PROBE_SOURCES = {
    'probe-pdfkit-concurrency.swift': EXTRACTION,       # native mode; -D PDFREFLOW_NATIVE
    'probe-pdfkit-memory.swift': [],                    # Apple SDKs only
    'probe-raster-environment.swift': RASTER,
    'probe-vision-titles.swift': RASTER,
    'inspect-structure.swift': ['StructureTreeReader.swift', 'CGPDFObjects.swift',
                                'DocumentModel.swift', 'ReflowDocument.swift'],
    'inspect-chapter-boundaries.swift': EXTRACTION + ['ChapterBoundaryReader.swift', 'PDFPageSource.swift'],
    'capture-layout-fixture.swift': EXTRACTION + ['GraphicsReader.swift'],
    'capture-spacing-source.swift': [],                 # Apple SDKs only
    'capture-algebra-layout.swift': EXTRACTION + ['GraphicsReader.swift'],
    'capture-ocr-layout-fixture.swift': RASTER + ['OCRReader.swift'],
    'audit-report-margins.swift': EXTRACTION + ['FurnitureDetector.swift'],
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
