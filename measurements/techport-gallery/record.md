# TechPort gallery caption order — bounded #191 helper

Source: NASA TechPort, *Tank Health Monitoring*, NTRS 20210020887, physical pages
2 and 5. Original PDF SHA-256:
`0fce4b68983ad8a216c8228ec44697c61ab41977ad41733c465ebebec3976ff0`.
The original was checksum-verified and both complete pages rendered and visually
reviewed on 2026-09-23. The owner-approved 2026-09-17 text-derivative scope applies;
no PDF, raster, crop, or EPUB is committed. NASA insignia and uncredited artwork
remain subject to the corpus manifest's exclusions. The source fixture is supplied
by the enclosing #191 change, not duplicated by this helper commit.

Page 5 has three top-aligned pictures, each 150 points wide, at x=36.75, 194.25,
351.75 and top y=655.5. Their heights are 69, 96.75, 47.25. Every caption starts
3.70 points beneath its own picture. The correct left-to-right units are:

1. Lander/Gateway artwork; `Tank Health Monitoring - In-Space Propellant Gauging`;
   description ending `without propulsive settling maneuvers`; image URL 41318.
2. Comparison slide; `Tank Health Monitoring: Existing propellant gauging methods
   comparison`; repeated short description; image URL 41319.
3. Formula; `The Basic Formula`; `Tank Health Monitoring Basic Formula`; URL 41316.

The draft `/tmp/pdfreflow-191-techport-draft.epub` first emits all three images,
then interleaves the caption rows by height. Simply attaching each caption to its
image still orders formula first: the ordinary fallback compares box centers.
`GalleryCaptions` requires a repeated row of similarly wide, top-aligned pictures,
adjacent aligned caption lines, and no competing text or picture ownership. It
returns original line indices and a shared vertical **reading footprint** for each
card, so short cards cannot leapfrog their left-hand neighbors. It never changes
the source crop or rewrites styled text.

Validation: `swift test --filter Gallery` passes two tests, including exact source
line ownership and full caption text, left-to-right and right-to-left ordering,
8.25/9-point body estimates, crop-border tolerance, and declining single images,
displaced pictures, remote captions, crossing prose, and unrelated text beneath a
short card. This helper is not yet hooked into conversion; full source conversion
and EPUB contracts belong to the enclosing #191 integration.

Integration: call `groups(lines:images:body:)` on remaining native lines and actual
preserved image rectangles before existing picture-caption association. Reserve
returned line indices and use the corresponding image path, original caption
lines, and returned reading rectangle in `Element.pictureCaption`. Do not use that
reading rectangle as a crop. Preserve existing claims by quotations/tables; decline
groups that conflict with them. All other pictures retain their existing path.

Page 2 TRL audit: native rows 51–53 state `Start: 4`, `Current: 6`, and
`Estimated End: 7`, at x=418.5 and y=280.27, 269.77, 259.27 respectively. Each box
is 72.62 by 10.03 points. The draft puts these in the chart crop. The source places
them to the upper left of its sloped chart; its paint bounding box can overlap the
rows without owning their letters. Reflow these proven label/value rows while
retaining the graphical chart and its axis labels. No inferred chart table is
needed. The enclosing #191 sidebar change owns that implementation and regression.
