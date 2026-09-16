# PDFKit concurrent attributed-text extraction can abort with a nil NSFont

Suggested area: macOS / PDFKit (or the PDF framework component available in Feedback Assistant).
Type: Incorrect/Unexpected Behavior; uncaught exception terminates the process.

## Summary

A standalone Swift command-line program using only Foundation, PDFKit and Darwin opens a
one-page PDF from independent `PDFDocument` instances on multiple threads and reads each
page's attributed text. No `PDFDocument`, `PDFPage`, `PDFSelection` or `NSAttributedString`
crosses threads; each iteration opens, reads and releases its own objects inside an
autoreleasepool. Under concurrent load, `PDFSelection.attributedString` can terminate the
process with an uncaught `NSInvalidArgumentException`:

```
*** -[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: NSFont)
PDFSelection.createAttributedStringForCGSelection:scaled:
PDFSelection.attributedStringScaled:
PDFSelection.attributedString
```

The crash is intermittent: in a five-trial matrix of eight concurrent worker processes doing
1,000 iterations each, 1 of 10 concurrent attributed-extraction runs aborts; 10/10 serial
attributed runs and 20/20 plain-text runs complete cleanly. This is separate from the
attributed-text memory leak already reported as **FB24783799**.

No PDFReflowLib code, third-party dependencies or EPUB packaging participate in this
reproducer; it is Apple-SDK-only.

## Environment

```
ProductName:		macOS
ProductVersion:		27.0
BuildVersion:		26A428
arm64
Mac17,6
38654705664
Xcode 27.0
Build version 27A266a
```

The two hardware values following arm64 are the Mac model identifier and installed RAM bytes.
Fresh diagnostics were collected on 2026-09-15 local time. Physical iOS/iPadOS reproduction has
not been performed.

## Steps to reproduce

1. Unzip the attached bundle (`apple-reproducer.zip`, ~100 KB). It contains the 47-line probe
   source, two tiny original one-page PDF fixtures (1,362 and 797 bytes), an MIT license, a
   captured failing run, and a README with exact commands. No corpus download is required.
2. Select a full Xcode installation with `xcode-select`, or set `DEVELOPER_DIR` appropriately.
3. Build: `xcrun swiftc -swift-version 6 -O -parse-as-library probe.swift -o probe`
4. Run concurrently (intermittent crash; a single invocation can pass):
   `./probe rolemap.pdf attributed 8 1000 > out.log 2> err.log`
5. Inspect `err.log` for the uncaught exception and SIGABRT. Repeat a few times if the first
   run passes — the failure rate observed here is roughly 1 in 10.

Serial and plain-text controls, each in a fresh process, do not reproduce the crash:
```
./probe rolemap.pdf attributed 1 1000 > serial.log 2> serial-err.log
./probe rolemap.pdf plain 8 1000 > plain.log 2> plain-err.log
```

## Expected result

Reading attributed text for a page from independent, non-shared PDFKit objects on separate
threads should either succeed or raise a recoverable error. It should not terminate the process.

## Actual result

Reproduced fresh on the environment above: the concurrent attributed run aborted on the 3rd of
5 trials (`fresh-crash-2026-09-15.stderr.log.gz`, gzip-compressed capture of the full run,
tail contains the exception and stack trace). The originally captured failure is also attached
(`sdk-crash.stderr.log` inside the bundle). Both show the identical exception and stack:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason:
'*** -[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: NSFont)'
*** First throw call stack:
(
	...
	2   CoreFoundation    -[__NSDictionaryM setObject:forKey:] + 1284
	3   PDFKit            __60-[PDFSelection createAttributedStringForCGSelection:scaled:]_block_invoke + 156
	4   Foundation        -[NSAttributedString enumerateAttributesInRange:options:usingBlock:] + 256
	5   PDFKit            -[PDFSelection createAttributedStringForCGSelection:scaled:] + 188
	6   PDFKit            -[PDFSelection attributedStringScaled:] + 204
	7   PDFKit            -[PDFSelection attributedString] + 84
	...
)
```

A second fixture (`untagged.pdf`) removes the PDF's structure tree while keeping identical
visible text/font content-stream instructions; both fixtures pass `qpdf --check` with no
syntax or stream-encoding errors, and both fixtures can trigger the crash. This does not
identify whether the structure tree is relevant, only that it is not required.

These small trial counts do not establish a precise crash rate, an exact thread-safety
contract for `PDFSelection`, or the internal ownership defect; only that independent,
non-shared PDFKit object graphs used concurrently from multiple threads can hit this path.

## Impact and workaround

Our on-device PDF-to-EPUB library reads page text (including attributed runs, to preserve
formatting) and needs to process documents without serializing all extraction work, since
serialization trades away concurrent throughput. As a bounded mitigation, the library now
serializes its own synchronous page-text extraction across converter instances, which avoids
the crash within a single copy of the library but cannot coordinate a host application's own,
independent PDFKit calls, nor is it a fix for the underlying framework behavior.

Related public tracking: https://github.com/vocaro/PDFReflowLib/issues/21
The attached fixtures are original, synthetic, single-page PDFs created for this report; no
private or third-party content is included.
