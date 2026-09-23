# Keep the executable name in recognition controls

Measured 2026-09-23 on macOS 27 arm64, integrated implementation `be89f8c`.
The release executable SHA-256 is
`9406f40c131d51466082fbb39979ebc43187ef46b3f2775f458a716f7a05c268`.
The source is the pinned Census report; its identity and four compact run results are in
`comparison.json`. The ordinary evaluator, default conversion options and EPUBCheck were used.

Copying these exact executable bytes under the name `pdf-reflow` reproduces the build-directory
output. Copying them to `renamed-cli` in the same directory changes recognized output on eleven
Census pages. The renamed result exactly repeats an earlier run under another renamed path.
All four runs pass the existing content and structural gates. The binary hash is identical;
this comparison therefore cannot identify a source-code regression or establish a particular
framework mechanism. It records a reproducible executable-name sensitivity on this host.

The first twenty-document integration lane accidentally used a renamed frozen executable.
It passed, but its broad OCR differences were not accepted as change-specific evidence.
The replacement lane uses a frozen directory containing the original `pdf-reflow` basename.
That lane reproduces baseline ordinary OCR text and crop behavior; the independent native
heading audit still identifies a Census paragraph promotion requiring its own layout guard.
This control does not excuse such semantic differences.

For converter comparisons, freeze each binary into a distinct directory while preserving its
basename, and record its hash. Keep raw EPUBs, progress and framework logs outside the repository.
This is a single-host control, not a determinism guarantee for other builds or machines.
