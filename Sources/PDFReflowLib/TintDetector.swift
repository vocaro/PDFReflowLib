import CoreGraphics
import Foundation

/// Separates page decoration painted as rectangles (sidebar boxes, tint bands behind prose,
/// table cell shading and the rules between them) from the graphics that must stay images (#54).
///
/// `GraphicsReader` records every painted footprint but cannot tell a figure background from a
/// tint because it does not see the text. Here the page's lines decide: a cluster of rectangles
/// that holds at least three wide prose lines untouched by any other ink is a tinted text block.
/// Its rectangles that carry text no longer seed crops, and the thin rules inside it that touch
/// no other graphic are separators rather than figures. Images, shadings, paths, rectangles
/// painted inside `/Figure` marks and rectangles holding no text keep seeding crops, so a chart
/// inside a sidebar keeps its own image while the prose around it reflows. A cluster without
/// that prose evidence (a figure background with tick labels, a flowchart node, a bar chart)
/// is left exactly as before.
enum TintDetector {
    struct Result: Equatable {
        /// Crop seeds, clustered as `GraphicsReader.Result.regions` would have been.
        var graphics: [CGRect]
        /// The tinted rectangles themselves, unclustered: bands and frames behind reflowed text.
        var tints: [CGRect]
        /// Thin rules dropped inside tinted blocks: row and column separators.
        var separators: [CGRect] = []
    }

    /// The share of `rect` covered by any of `covers`, sampled on a grid.
    static func coverage(of rect: CGRect, by covers: [CGRect]) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var hits = 0
        for i in 0..<16 {
            for j in 0..<16 {
                let point = CGPoint(x: rect.minX + rect.width * (CGFloat(i) + 0.5) / 16,
                                    y: rect.minY + rect.height * (CGFloat(j) + 0.5) / 16)
                if covers.contains(where: { $0.contains(point) }) { hits += 1 }
            }
        }
        return CGFloat(hits) / 256
    }

    /// A rule after the reader's two-point padding, horizontal or vertical.
    static func isThin(_ rect: CGRect) -> Bool { min(rect.width, rect.height) <= 6 }

    /// A line of at least four words of two or more letters: the measure of body prose, a
    /// caption or a table cell's sentence, never a chart's tick label or an illustration's
    /// one- or two-word callout.
    static func readsAsProse(_ line: TextLine) -> Bool {
        !line.monospaced && line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
    }

    /// The page's blocks of running text (#158): a run of at least three lines of one type size,
    /// each within nine tenths of a line of the one above, overlapping its measure and set on the
    /// block's left edge give or take three sizes (a hanging index entry, a paragraph opening),
    /// of which at least two read as prose or open in the middle of a sentence. A column of body
    /// text, a caption, a sidebar's paragraphs and an index's entries qualify; a derivation's
    /// annotations beside its steps (Wallace page 198's `Distribute 2x and− 5` / `Multiply out
    /// each term` / `Combine like terms` / `Our Solution`), a chart's tick labels and an
    /// illustration's callouts carry too little prose, stand alone or stand too far apart.
    ///
    /// A crop may take a figure's label, but not a line of running text: crops neither grow over
    /// one nor bridge art across one.
    ///
    /// Cost: one pass down the page's lines against the blocks open beside them, and a page with
    /// more than `blockTextLineLimit` lines has no block text.
    static let blockTextLineLimit = 2_000
    static func blockText(_ lines: [TextLine]) -> [TextLine] {
        guard lines.count >= 3, lines.count <= blockTextLineLimit else { return [] }
        let sorted = lines.filter { !$0.monospaced && !$0.rect.isNull && $0.rect.isFinite && $0.rect.width > 0 }
            .sorted { $0.rect.minY > $1.rect.minY }
        var blocks: [(edge: CGFloat, lines: [TextLine])] = []
        for line in sorted {
            let index = blocks.lastIndex { block in
                guard let last = block.lines.last else { return false }
                let size = max(last.fontSize, line.fontSize)
                let overlap = min(last.rect.maxX, line.rect.maxX) - max(last.rect.minX, line.rect.minX)
                return abs(last.fontSize - line.fontSize) <= size * 0.1
                    && last.rect.minY - line.rect.maxY <= size * 0.9 && last.rect.minY > line.rect.minY
                    && overlap > 0 && abs(line.rect.minX - block.edge) <= size * 3
            }
            if let index {
                blocks[index].edge = min(blocks[index].edge, line.rect.minX)
                blocks[index].lines.append(line)
            } else {
                blocks.append((line.rect.minX, [line]))
            }
        }
        // Wrapped lines: running text carries lines of words that open in the middle of a
        // sentence, which a stack of labels, a column of variables or a derivation's annotations
        // (each opening with a capital) does not.
        func wraps(_ line: TextLine) -> Bool {
            let text = line.text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“‘(["))
            return text.first?.isLowercase == true
                && text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 2
        }
        return blocks.filter {
            $0.lines.count >= 3 && ($0.lines.filter(readsAsProse).count >= 2 || $0.lines.filter(wraps).count >= 2)
        }.flatMap(\.lines)
    }

    /// Prose evidence: a line of at least four words spanning at least 40% of the block.
    private static func isProse(_ line: TextLine, in hull: CGRect) -> Bool {
        !line.monospaced && line.rect.width >= hull.width * 0.4
            && line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
    }

    private static func mostlyInside(_ rect: CGRect, _ container: CGRect) -> Bool {
        let overlap = rect.intersection(container)
        return !overlap.isNull && overlap.width * overlap.height >= rect.width * rect.height * 0.5
    }

    /// `clusters`, keeping each cluster's members.
    private static func groups(_ rects: [CGRect], distance: CGFloat) -> [[CGRect]] {
        var result: [(hull: CGRect, members: [CGRect])] = []
        for rect in rects where !rect.isNull && rect.isFinite {
            var merged = (hull: rect, members: [rect])
            var previousCount = -1
            while previousCount != result.count {
                previousCount = result.count
                result.removeAll { existing in
                    if existing.hull.insetBy(dx: -distance, dy: -distance).intersects(merged.hull) {
                        merged.hull = merged.hull.union(existing.hull)
                        merged.members += existing.members
                        return true
                    }
                    return false
                }
            }
            result.append(merged)
        }
        return result.map(\.members)
    }

    /// Collinear thin strokes joined into one edge: InDesign draws a box side as one segment
    /// per table row, so a side is the union of the segments sharing its line.
    private static func edges(_ rules: [CGRect], horizontal: Bool) -> [(rect: CGRect, strokes: [CGRect])] {
        var result: [(rect: CGRect, strokes: [CGRect])] = []
        for rule in rules where horizontal ? rule.width > rule.height : rule.height >= rule.width {
            let position = horizontal ? rule.midY : rule.midX
            if let index = result.firstIndex(where: { abs((horizontal ? $0.rect.midY : $0.rect.midX) - position) <= 1.5
                && (horizontal ? $0.rect.minX <= rule.maxX + 3 && rule.minX <= $0.rect.maxX + 3
                    : $0.rect.minY <= rule.maxY + 3 && rule.minY <= $0.rect.maxY + 3) }) {
                result[index].rect = result[index].rect.union(rule)
                result[index].strokes.append(rule)
            } else { result.append((rule, [rule])) }
        }
        return result.filter { horizontal ? $0.rect.width >= 40 : $0.rect.height >= 40 }
    }

    /// Four thin edges meeting at their corners draw the same box as a stroked `re`.
    static func strokedRectangles(_ rules: [CGRect]) -> [(rect: CGRect, strokes: [CGRect])] {
        let horizontals = edges(rules, horizontal: true)
        let verticals = edges(rules, horizontal: false)
        var result: [(rect: CGRect, strokes: [CGRect])] = []
        for (index, top) in horizontals.enumerated() {
            for bottom in horizontals[(index + 1)...]
            where abs(top.rect.minX - bottom.rect.minX) <= 3 && abs(top.rect.maxX - bottom.rect.maxX) <= 3
                && abs(top.rect.midY - bottom.rect.midY) >= 12 {
                let rect = top.rect.union(bottom.rect)
                let sides = verticals.filter { side in
                    abs(side.rect.minY - rect.minY) <= 3 && abs(side.rect.maxY - rect.maxY) <= 3
                        && (abs(side.rect.midX - rect.minX) <= 3 || abs(side.rect.midX - rect.maxX) <= 3)
                }
                guard sides.contains(where: { abs($0.rect.midX - rect.minX) <= 3 }),
                      sides.contains(where: { abs($0.rect.midX - rect.maxX) <= 3 }) else { continue }
                result.append((rect, top.strokes + bottom.strokes + sides.flatMap(\.strokes)))
            }
        }
        // Only the outermost box is a frame; the rules of a table inside it stay a grid.
        return result.filter { candidate in !result.contains { $0.rect != candidate.rect && $0.rect.contains(candidate.rect) } }
    }

    /// A frame without prose evidence whose rules and bands the table detector reads as a text
    /// table (#65): Fed page 46's Table 3.1, a shaded title band and header band over body rows
    /// separated only by rules. The table must have a header row on its own band and at least two
    /// body rows, no solid ink may lie in the frame, and every line in the frame other than the
    /// table's own lies above it (a title band). Anything else keeps its image, as before.
    private static func ruledTextTable(hull: CGRect, tinted: [CGRect], lines: [TextLine], inside: [TextLine],
                                       rules: [CGRect], solidInk: [CGRect], bounds: CGRect, body: CGFloat) -> Bool {
        guard !solidInk.contains(where: { $0.intersects(hull) }) else { return false }
        let grid = rules.filter { hull.insetBy(dx: -body, dy: -body).contains($0) }
        guard grid.filter({ $0.width > $0.height }).count >= 2 else { return false }
        var trial = PageContent(number: 0, bounds: bounds, lines: lines, graphics: [])
        trial.tints = tinted
        trial.separators = grid
        return ShadedTableDetector.tables(in: trial, lines: lines).contains { table in
            let owned = table.lines
            let bodyRows = table.rows.filter { !$0.header }
            return table.rows.first?.header == true && bodyRows.count >= 2
                && hull.insetBy(dx: -2, dy: -2).contains(table.bounds)
                && inside.allSatisfy { line in
                    owned.contains { $0.rect == line.rect && $0.text == line.text } || line.rect.minY >= table.bounds.maxY - 1
                }
        }
    }

    /// Title backdrops painted into other art (#117). `LayoutReconstructor.titleArt` judges a
    /// painted cluster, so a section band or tab that touches an icon, a photograph or a connector
    /// is never judged on its own: DGA pages 3–6 set each 18-pt section title on a gradient band
    /// abutting a circular photo, and page 7's callout title on a tab joined to its box. Here each
    /// vector paint is judged with the non-image paints it touches inside its own height (a band's
    /// inner stroke and end tick), largest first, before anything clusters. Title art is removed
    /// or trimmed exactly as the cluster rule would; images, rectangle frames (`TintDetector`'s own
    /// evidence) and rows lying inside another paint (a boxed figure's title bar, Fed page 130) are
    /// never judged here.
    ///
    /// Cost is bounded for vector-dense drawings: a page with more than `titleBackdropCandidateLimit`
    /// candidate paints is left to clustering (the English corpus's densest candidate-bearing pages
    /// hold 1,000–2,100, FAA figures whose output this rule never changed; DGA's hold at most 25). A
    /// paint is judged only when a title-size line reaches into its height, and its row is read from
    /// the paints sorted by their lower edge.
    static let titleBackdropCandidateLimit = 500
    static func withoutTitleBackdrops(_ paints: [GraphicsReader.Paint], lines: [TextLine]) -> [GraphicsReader.Paint] {
        guard !lines.isEmpty else { return paints }
        let body = max(4, LayoutReconstructor.bodySize(lines))
        func usable(_ paint: GraphicsReader.Paint) -> Bool {
            !paint.image && !paint.rect.isNull && paint.rect.isFinite && paint.rect.width > 0 && paint.rect.height > 0
        }
        let candidates = paints.indices.filter {
            usable(paints[$0]) && (!paints[$0].frame || paints[$0].grouped) && !isThin(paints[$0].rect)
        }
        guard candidates.count <= titleBackdropCandidateLimit else { return paints }
        // `titleArt` needs a line of title type touching the row, which lies within the paint's height.
        let titles = lines.filter { line in
            !line.monospaced && line.fontSize >= body * 1.25 && line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
        }.map(\.rect)
        guard !titles.isEmpty else { return paints }
        let order = candidates
            .sorted { paints[$0].rect.width * paints[$0].rect.height > paints[$1].rect.width * paints[$1].rect.height }
        let byLowerEdge = paints.indices.filter { usable(paints[$0]) }.sorted { paints[$0].rect.minY < paints[$1].rect.minY }
        var removed = Set<Int>()
        var trimmed: [GraphicsReader.Paint] = []
        for index in order where !removed.contains(index) {
            let rect = paints[index].rect
            guard titles.contains(where: { $0.maxY >= rect.minY - 2 && $0.minY <= rect.maxY + 2 }) else { continue }
            // A row member's lower edge lies within rect.minY - 2 ... rect.maxY + 2.
            var low = 0, high = byLowerEdge.count
            while low < high {
                let middle = (low + high) / 2
                if paints[byLowerEdge[middle]].rect.minY < rect.minY - 2 { low = middle + 1 } else { high = middle }
            }
            var row: [Int] = []
            for other in byLowerEdge[low...] {
                let candidate = paints[other].rect
                if candidate.minY > rect.maxY + 2 { break }
                if !removed.contains(other) && candidate.insetBy(dx: -4, dy: -4).intersects(rect) && candidate.maxY <= rect.maxY + 2 {
                    row.append(other)
                }
            }
            let members = Set(row)
            let hull = union(row.map { paints[$0].rect })
            // A title bar inside a painted box is that figure's own (the Fed's boxed figures).
            guard !paints.indices.contains(where: { !members.contains($0) && paints[$0].rect.insetBy(dx: -2, dy: -2).contains(hull) }),
                  let art = LayoutReconstructor.titleArt(hull, in: lines, body: body, stacked: true) else { continue }
            removed.formUnion(row)
            if let kept = art { trimmed.append(GraphicsReader.Paint(rect: kept, frame: false)) }
        }
        guard !removed.isEmpty else { return paints }
        return paints.indices.filter { !removed.contains($0) }.map { paints[$0] } + trimmed
    }

    /// Crop seeds clustered as the reader's regions are, except that a thin rule touching no text
    /// does not bridge art into a hull over prose (#117). DGA pages 3–5 draw a timeline down the
    /// left margin from the footer band through each section's icon, and page 6 a short connector
    /// from its icon to the banner: joined, one hull covered every column. When a cluster's hull
    /// meets at least two prose lines that none of its parts meets once such rules are set aside,
    /// the rules are dropped. Rules touching a label, and clusters that take no prose, stay.
    ///
    /// Cost is bounded: rules and prose are found once for the page, only the hulls holding a rule
    /// are examined, and a page whose rules times hulls, or rule-bearing hulls times seeds, exceed
    /// `seedClusterWorkLimit` (thousands of isolated strokes) clusters as before.
    static let seedClusterWorkLimit = 2_000_000
    static func seedClusters(_ rects: [CGRect], lines: [TextLine]) -> [CGRect] {
        let seeds = rects.filter { !$0.isNull && $0.isFinite }
        let prose = lines.filter { line in
            !line.monospaced && line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
        }
        guard prose.count >= 2 else { return clustersKeepingText(clusters(seeds, distance: 4), seeds: seeds, lines: lines) }
        let body = max(4, LayoutReconstructor.bodySize(lines))
        // A rule standing more than two bodies clear of every line (a grid's rules sit against
        // their cells), or a horizontal rule touching only the one line it underlines.
        let text = union(lines.map(\.rect))
        let rules = Set(seeds.indices.filter { index in
            let rule = seeds[index]
            guard isThin(rule) else { return false }
            if !lines.contains(where: { rule.insetBy(dx: -body * 2, dy: -body * 2).intersects($0.rect) }) { return true }
            let touched = lines.filter { rule.intersects($0.rect) }
            // A rule across the page that strikes no line at all is a divider, not a figure's own
            // stroke: the magazine's index pages rule off their title above three columns of
            // entries (#158).
            let struck = touched.filter { line in
                let overlap = rule.intersection(line.rect)
                return !overlap.isNull && overlap.height >= 1
            }
            if struck.isEmpty, rule.width > rule.height, rule.width >= text.width * 0.5 { return true }
            return rule.width > rule.height && touched.count == 1 && rule.midY <= touched[0].rect.minY + 3
                && rule.minX >= touched[0].rect.minX - 4 && rule.maxX <= touched[0].rect.maxX + 4
                && !lines.contains { $0 != touched[0] && rule.insetBy(dx: 0, dy: -3).intersects($0.rect) }
        })
        let hulls = clusters(seeds, distance: 4)
        guard !rules.isEmpty, rules.count * hulls.count <= seedClusterWorkLimit else {
            return clustersKeepingText(hulls, seeds: seeds, lines: lines)
        }
        var ruled: [Int: [Int]] = [:]
        for rule in rules {
            if let hull = hulls.firstIndex(where: { $0.contains(seeds[rule]) }) { ruled[hull, default: []].append(rule) }
        }
        guard ruled.count * seeds.count <= seedClusterWorkLimit else {
            return clustersKeepingText(hulls, seeds: seeds, lines: lines)
        }
        var dropped = Set<Int>()
        for (hullIndex, hullRules) in ruled {
            let hull = hulls[hullIndex]
            let members = seeds.indices.filter { hull.contains(seeds[$0]) }
            guard hullRules.count < members.count else { continue }
            let own = Set(hullRules)
            let parts = clusters(members.filter { !own.contains($0) }.map { seeds[$0] }, distance: 4)
            let escaped = prose.filter { line in line.rect.intersects(hull) && !parts.contains { $0.intersects(line.rect) } }
            if escaped.count >= 2 { dropped.formUnion(own) }
        }
        let kept = dropped.isEmpty ? seeds : seeds.indices.filter { !dropped.contains($0) }.map { seeds[$0] }
        return clustersKeepingText(dropped.isEmpty ? hulls : clusters(kept, distance: 4), seeds: kept, lines: lines)
    }

    /// Clustering joins art by the bounding box it grows, so a hull can span text that none of its
    /// parts touches: the magazine's index pages bridge a holly ornament to the rule under the
    /// title across three columns of entries, its FORUM page bridges the running-foot rule to the
    /// signature box across the foot of every column, and the TechPort gallery bridges three
    /// pictures across the captions beneath the shorter ones (#158, #166). Where a hull takes
    /// block text (`blockText`) that no part of it takes, its parts are clustered again, joining
    /// two groups only where the box around them takes none of that text. Art that holds or
    /// touches the text keeps it, so a chart's labels, a map's names and an illustration's
    /// callouts cluster exactly as before.
    ///
    /// Cost: a hull whose parts times the escaped lines exceed `seedClusterWorkLimit` is left
    /// whole, and the parts of one hull are joined in at most as many passes as it has parts.
    static func clustersKeepingText(_ hulls: [CGRect], seeds: [CGRect], lines: [TextLine]) -> [CGRect] {
        let text = blockText(lines)
        guard !text.isEmpty else { return hulls }
        var result: [CGRect] = []
        var changed = false
        for hull in hulls {
            let members = seeds.filter { hull.contains($0) }
            let escaped = text.filter { line in
                line.rect.intersects(hull) && !members.contains { $0.intersects(line.rect) }
            }
            guard escaped.count >= 2, members.count >= 2,
                  members.count * escaped.count <= seedClusterWorkLimit else { result.append(hull); continue }
            var groups = members
            var joined = true
            while joined {
                joined = false
                outer: for i in groups.indices {
                    for j in groups.indices where j > i {
                        guard groups[i].insetBy(dx: -4, dy: -4).intersects(groups[j]) else { continue }
                        let union = groups[i].union(groups[j])
                        guard !escaped.contains(where: { $0.rect.intersects(union) }) else { continue }
                        groups[i] = union
                        groups.remove(at: j)
                        joined = true
                        break outer
                    }
                }
            }
            if groups.count > 1 { changed = true }
            result += groups
        }
        return changed ? result : hulls
    }

    /// Vector shapes behind prose that are not rectangles (#117): a rounded callout box (DGA
    /// pages 3, 5, 6 and 7 draw `Gut Health`, `Added Sugars`, `Sodium` and the infant-feeding list
    /// in one) holds the same prose evidence a rectangle frame must. A shape counts when it is
    /// filled, holds no other paint (only text: a boxed figure holds its art, Fed page 130), and
    /// the lines mostly inside it include at least three prose lines making up a third of them. A
    /// filled shape touching such a box and holding only lines that fit inside it, with no other
    /// paint within it, is the box's tab. Images are never backdrops.
    private static func shapeBackdrops(_ finite: [GraphicsReader.Paint], lines: [TextLine]) -> [CGRect] {
        let shapes = finite.filter { !$0.frame && !$0.image && $0.filled && !isThin($0.rect) }.map(\.rect)
        var boxes: [CGRect] = []
        for shape in shapes where !boxes.contains(shape) {
            let inside = lines.filter { mostlyInside($0.rect, shape) }
            let prose = inside.filter { isProse($0, in: shape) }
            // The prose evidence first: only a shape holding it pays for the scan of every paint.
            guard prose.count >= 3, prose.count * 3 >= inside.count,
                  !finite.contains(where: { $0.rect != shape && shape.contains($0.rect) }) else { continue }
            boxes.append(shape)
        }
        guard !boxes.isEmpty else { return [] }
        let tabs = shapes.filter { tab in
            guard !boxes.contains(tab), boxes.contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(tab) }) else { return false }
            let held = lines.filter { tab.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            return !held.isEmpty && held.allSatisfy { tab.insetBy(dx: -2, dy: -2).contains($0.rect) }
                && !finite.contains { $0.rect != tab && tab.contains($0.rect) }
        }
        return boxes + tabs
    }

    /// Text set on a band across a photograph's edge (#141). DGA page 2 paints `Message from the
    /// Secretaries` on a tab over the lower edge of its header photograph and the welcome line on
    /// a full-width band beneath it; photograph, tab and band cluster into one crop that took both
    /// lines. A crop keeps only its art beyond such a band when:
    ///
    /// - the lines it meets all lie, with the painted backdrops beneath them, in one strip at its
    ///   top or bottom edge;
    /// - every one of those lines sits on a filled backdrop that is not an image (a tab, a band),
    ///   the backdrops together span the crop's width, and each line is a title (1.25 body,
    ///   carrying a word) or prose (four words);
    /// - beyond the strip, images cover at least 90% of the rest of the crop, which is at least a
    ///   third of its height. The rest holds no text: every line the crop meets is in the strip.
    ///
    /// The crop becomes the images' part of that rest. On DGA page 2 it starts above the tab, so the
    /// photograph loses the 38 pt beside the tab rather than show a piece of it.
    ///
    /// Labels on a chart or map, and an illustration's callouts, sit on the art itself or on boxes
    /// narrower than it, so their crops are unchanged. `paints` are the page's paints before any
    /// title backdrop was removed, since those are the backdrops the lines sit on.
    ///
    /// Cost is bounded as `seedClusters` is: each crop scans the page's images and lines, and a crop
    /// whose lines all read scans the filled paints under them; a page whose crops times its images,
    /// lines and filled paints exceed `seedClusterWorkLimit` keeps its crops.
    static func withoutEdgeBands(_ hulls: [CGRect], paints: [GraphicsReader.Paint], lines: [TextLine]) -> [CGRect] {
        let images = paints.filter { $0.image && !$0.rect.isNull && $0.rect.isFinite }.map(\.rect)
        let filled = paints.filter(\.filled).map(\.rect)
        guard !images.isEmpty, !lines.isEmpty,
              hulls.count * (images.count + lines.count + filled.count) <= seedClusterWorkLimit else { return hulls }
        let body = max(4, LayoutReconstructor.bodySize(lines))
        func reads(_ line: TextLine) -> Bool {
            guard !line.monospaced else { return false }
            if line.fontSize >= body * 1.25, line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil { return true }
            return line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
        }
        return hulls.map { hull in
            // Early exits: a crop with no image or no text has nothing to keep apart.
            let art = images.filter { hull.insetBy(dx: -1, dy: -1).contains($0) }
            guard !art.isEmpty else { return hull }
            let held = lines.filter { $0.rect.intersects(hull) }
            guard !held.isEmpty, held.allSatisfy(reads) else { return hull }
            let backdrops = filled.filter { paint in held.contains { paint.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) } }
            guard held.allSatisfy({ line in backdrops.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }),
                  union(backdrops).width >= hull.width * 0.9 else { return hull }
            let strip = union(backdrops + held.map(\.rect))
            let gap: CGFloat = 0.5
            // The rest's extent, measured before it becomes a rectangle (whose height is never
            // negative): a strip reaching past both edges, such as a box around the whole figure,
            // leaves none.
            let low: CGFloat, high: CGFloat
            if strip.minY <= hull.minY + 1 {
                (low, high) = (strip.maxY + gap, hull.maxY)
            } else if strip.maxY >= hull.maxY - 1 {
                (low, high) = (hull.minY, strip.minY - gap)
            } else { return hull }
            let rest = CGRect(x: hull.minX, y: low, width: hull.width, height: max(0, high - low))
            guard high - low >= hull.height / 3, coverage(of: rest, by: art) >= 0.9 else { return hull }
            return union(art.map { $0.intersection(rest) }.filter { !$0.isNull })
        }
    }

    /// Images that text is set over or against (#158, #166).
    ///
    /// - A background: an image holding at least three prose lines (four words, at least 0.9 body)
    ///   that make up a third of the lines inside it, where the text block covers so much of it
    ///   that less than half of the image lies beyond the block, or what lies beyond is under
    ///   another image. The Agricultural Research magazine sets its columns over a faded flag
    ///   (pages 5, 7, 8, 10, 13, 14) and a pull quote over a photograph (pages 11, 12, 14); the
    ///   image seeded a crop that took every column line over it. It seeds nothing now. A picture
    ///   that keeps most of itself beyond the text (a caption box set over a photograph) is left
    ///   as it was, with its text.
    /// - An overhanging line: a title (1.25 body, a word of three letters) or a prose line that
    ///   meets an image but lies mostly beyond it. Magazine page 16 sets its title box across the
    ///   photograph's edge; the crop took the title, widened to the column beside the photograph
    ///   and took the column. The image gives up the side the line is on, keeping the largest
    ///   part, when that part is at least half of it.
    /// - A caption on its own band: a filled paint mostly inside the image that holds at least two
    ///   lines, one of them prose, and no other paint. Text set on a band over a picture is an
    ///   overlay, not the picture's own label (magazine pages 4, 8 and 16), so the image gives up
    ///   that strip, again keeping at least half of itself. A legend box holding art of its own is
    ///   part of the picture.
    ///
    /// Cost: a page whose images times lines exceed `seedClusterWorkLimit` keeps its paints.
    static func withoutTextBackdrops(_ paints: [GraphicsReader.Paint], lines: [TextLine]) -> [GraphicsReader.Paint] {
        let images = paints.indices.filter { index in
            let rect = paints[index].rect
            return paints[index].image && !rect.isNull && rect.isFinite && rect.width > 0 && rect.height > 0
        }
        guard !images.isEmpty, !lines.isEmpty, images.count * lines.count <= seedClusterWorkLimit else { return paints }
        let body = max(4, LayoutReconstructor.bodySize(lines))
        func prose(_ line: TextLine) -> Bool {
            !line.monospaced && line.fontSize >= body * 0.9
                && line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
        }
        func title(_ line: TextLine) -> Bool {
            !line.monospaced && line.fontSize >= body * 1.25 && line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
        }
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        /// The largest part of `rect` beyond `zone` on one side.
        func beyond(_ zone: CGRect, in rect: CGRect) -> CGRect {
            let gap: CGFloat = 0.5
            let sides = [
                CGRect(x: rect.minX, y: zone.maxY + gap, width: rect.width, height: rect.maxY - zone.maxY - gap),
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: zone.minY - gap - rect.minY),
                CGRect(x: zone.maxX + gap, y: rect.minY, width: rect.maxX - zone.maxX - gap, height: rect.height),
                CGRect(x: rect.minX, y: rect.minY, width: zone.minX - gap - rect.minX, height: rect.height),
            ].filter { $0.width > 0 && $0.height > 0 }
            return sides.max { area($0) < area($1) } ?? .null
        }
        /// Whether a block of text over a picture runs on past it: one of `held`'s lines stacks
        /// with a line of its size and measure that lies beyond the picture. A caption set inside
        /// a photograph stands alone there; a column that a background is painted under does not.
        func continues(_ held: [TextLine], beyond rect: CGRect, lines: [TextLine]) -> Bool {
            lines.contains { other in
                guard !mostlyInside(other.rect, rect) else { return false }
                return held.contains { line in
                    abs(other.fontSize - line.fontSize) <= max(other.fontSize, line.fontSize) * 0.1
                        && min(other.rect.maxX, line.rect.maxX) - max(other.rect.minX, line.rect.minX) > 0
                        && max(other.rect.minY - line.rect.maxY, line.rect.minY - other.rect.maxY) <= line.fontSize * 0.9
                }
            }
        }
        var result = paints
        var removed = Set<Int>()
        for index in images {
            let rect = paints[index].rect
            let meeting = lines.filter { $0.rect.intersects(rect) }
            guard !meeting.isEmpty else { continue }
            let inside = meeting.filter { mostlyInside($0.rect, rect) }
            let text = inside.filter(prose)
            if text.count >= 3, text.count * 3 >= inside.count {
                let rest = beyond(union(inside.map(\.rect)).intersection(rect), in: rect)
                let others = images.filter { $0 != index && !removed.contains($0) }.map { paints[$0].rect }
                if area(rest) < area(rect) / 2 || coverage(of: rest, by: others) >= 0.9 {
                    removed.insert(index)
                    continue
                }
                if continues(text, beyond: rect, lines: lines) {
                    // The picture is not the text's own: its block runs on past the picture, which
                    // keeps what lies beyond the block (magazine page 14's columns over the flag).
                    result[index].rect = rest
                    continue
                }
                // Otherwise the text stands inside the picture, which keeps it unless it is set
                // on a band of its own (below).
            }
            var kept = rect
            for line in meeting where !mostlyInside(line.rect, rect) && (prose(line) || title(line)) && kept.intersects(line.rect) {
                kept = beyond(line.rect.intersection(kept), in: kept)
                guard !kept.isNull else { break }
            }
            // A caption set on its own band over a picture is an overlay, not the picture's own
            // label: the picture gives up the band's strip so the caption can reflow (#158,
            // magazine page 16). The band must hold only text of its own, as a tint does.
            let bands = paints.filter { paint in
                guard !paint.image, !isThin(paint.rect), mostlyInside(paint.rect, rect) else { return false }
                let held = lines.filter { paint.rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                return held.count >= 2 && held.contains(where: readsAsProse)
                    && !paints.contains { $0.rect != paint.rect && !$0.image && paint.rect.contains($0.rect) }
            }
            if !bands.isEmpty {
                let strip = union(bands.map(\.rect) + lines.filter { line in
                    bands.contains { $0.rect.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) }
                }.map(\.rect))
                let beyondBand = beyond(strip.intersection(kept), in: kept)
                if area(beyondBand) >= area(rect) / 2 { kept = beyondBand }
            }
            if kept != rect, area(kept) >= area(rect) / 2 { result[index].rect = kept }
        }
        return result.indices.filter { !removed.contains($0) }.map { result[$0] }
    }

    static func compose(_ paints: [GraphicsReader.Paint], lines: [TextLine], bounds: CGRect) -> Result {
        let paints = withoutTextBackdrops(paints, lines: lines)
        let result = composeTints(paints, lines: lines, bounds: bounds)
        let graphics = withoutEdgeBands(result.graphics, paints: paints, lines: lines)
        guard graphics != result.graphics else { return result }
        return Result(graphics: graphics, tints: result.tints, separators: result.separators)
    }

    /// Whether a panel's lines make one column of text (#166): every line it holds stands on the
    /// edge of its running text, give or take three body sizes. A sidebar's headings, labelled
    /// fields and contents entries do; a ratings grid's fragments, set in three columns beside
    /// three lines of prose, and a table's cells do not, so those keep their image.
    static func oneColumnOfText(_ inside: [TextLine], block: [TextLine], body: CGFloat) -> Bool {
        guard let edge = block.map(\.rect.minX).min() else { return false }
        return inside.allSatisfy { abs($0.rect.minX - edge) <= body * 3 }
    }

    /// A band across the page carrying its title (#166): a filled rectangle at least four fifths
    /// of the page wide, standing against the page's top or bottom edge, holding a title and only
    /// rows of three words or a title, with every line it holds clear of the art inside it. The TechPort
    /// print sets the division, the project title and its state on a dark band beside the NASA
    /// insignia on every page, and that band took the document's own title into a crop.
    ///
    /// Rows, not lines: a print's band breaks a date range into `Completed Technology Project
    /// (2015`, `-` and `2020)`, which read as one row. Art inside the band (the insignia) is kept
    /// by the block's own carving, which leaves a graphic standing beside the text its own extent.
    static func bannerBand(hull: CGRect, inside: [TextLine], lines: [TextLine], bounds: CGRect, body: CGFloat) -> Bool {
        guard hull.width >= bounds.width * 0.8, inside.count >= 2,
              hull.minY <= bounds.minY + hull.height || hull.maxY >= bounds.maxY - hull.height,
              lines.allSatisfy({ line in !mostlyInside(line.rect, hull) || inside.contains { $0.rect == line.rect && $0.text == line.text } })
        else { return false }
        var rows: [[TextLine]] = []
        for line in inside.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            if let index = rows.firstIndex(where: { row in
                row.contains { other in
                    min(other.rect.maxY, line.rect.maxY) - max(other.rect.minY, line.rect.minY)
                        >= min(other.rect.height, line.rect.height) * 0.5
                }
            }) { rows[index].append(line) } else { rows.append([line]) }
        }
        var holdsTitle = false
        for row in rows {
            let text = row.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: " ")
            let words = text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count
            let title = (row.map(\.fontSize).max() ?? 0) >= body * 1.25
                && text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
            guard words >= 3 || title else { return false }
            holdsTitle = holdsTitle || title
        }
        return holdsTitle
    }

    private static func composeTints(_ paints: [GraphicsReader.Paint], lines: [TextLine], bounds: CGRect) -> Result {
        let paints = withoutTitleBackdrops(paints, lines: lines)
        let finite = paints.filter { !$0.rect.isNull && $0.rect.isFinite }
        let stroked = strokedRectangles(finite.filter { isThin($0.rect) }.map(\.rect))
        let shapes = lines.isEmpty ? [] : shapeBackdrops(finite, lines: lines)
        let candidates = finite.filter { $0.frame && !isThin($0.rect) }.map(\.rect) + stroked.map(\.rect) + shapes
        guard !candidates.isEmpty, !lines.isEmpty else {
            return Result(graphics: seedClusters(paints.map(\.rect), lines: lines), tints: [])
        }
        let strokes = stroked.flatMap(\.strokes)
        let ink = finite.filter { (!$0.frame || isThin($0.rect)) && !strokes.contains($0.rect) && !shapes.contains($0.rect) }.map(\.rect)
        let solidInk = ink.filter { !isThin($0) }
        var tints: [CGRect] = []
        var blocks: [(hull: CGRect, prose: [TextLine], ruled: Bool)] = []
        let body = max(4, LayoutReconstructor.bodySize(lines))
        let running = blockText(lines)
        for members in groups(candidates, distance: 4) {
            let hull = union(members)
            let inside = lines.filter { line in
                mostlyInside(line.rect, hull) && !solidInk.contains { $0.intersects(line.rect) }
            }
            let prose = inside.filter { isProse($0, in: hull) }
            // A panel of a page laid out for the web holds headings, labelled fields and a
            // contents list rather than a third of its lines in prose, but its paragraphs still
            // stack as running text (#166: TechPort's header band and sidebars).
            let block = inside.filter { line in running.contains { $0.rect == line.rect && $0.text == line.text } }
            let tinted = members.filter { member in
                lines.contains { member.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            }
            // Prose must carry the text that would reflow: a figure whose labels PDFKit merges
            // into short fragments (a ratings grid, columns of bullets) keeps its image.
            if prose.count >= 3, prose.count * 3 >= inside.count {
                guard !tinted.isEmpty else { continue }
                tints += tinted
                blocks.append((union(tinted), prose, false))
            } else if !tinted.isEmpty, ruledTextTable(hull: hull, tinted: tinted, lines: lines, inside: inside,
                                                      rules: ink.filter(isThin), solidInk: solidInk, bounds: bounds, body: body) {
                tints += tinted
                blocks.append((union(tinted), prose, true))
            } else if !tinted.isEmpty, block.count >= 3, oneColumnOfText(inside, block: block, body: body),
                      ink.filter({ isThin($0) && $0.width > $0.height && hull.insetBy(dx: -body, dy: -body).contains($0) }).count < 2 {
                tints += tinted
                blocks.append((union(tinted), prose.isEmpty ? block : prose, false))
            } else if !tinted.isEmpty, bannerBand(hull: hull, inside: inside, lines: lines, bounds: bounds, body: body) {
                tints += tinted
                blocks.append((union(tinted), inside, false))
            }
        }
        guard !tints.isEmpty else {
            return Result(graphics: seedClusters(paints.map(\.rect), lines: lines), tints: [])
        }
        // Rules that only touch each other inside a tinted block separate its rows and columns.
        // A rule connected to solid ink (a chart axis) stays with that graphic. A lone fraction
        // bar keeps its terms; a grid of rules between single-letter cells is not a fraction.
        // A ruled grid whose cells are not shaded stays an image with the frame drawn around it,
        // unless the table reader already accepted its block as a ruled text table (#65).
        var separators: [CGRect] = []
        var carved: [CGRect] = []
        var consumed: [CGRect] = []
        var restored: [CGRect] = []
        for members in groups(ink, distance: 4) {
            let hull = union(members)
            if members.allSatisfy(isThin) {
                // A stroked frame sits a little outside the bands it encloses.
                guard let block = blocks.first(where: { $0.hull.insetBy(dx: -body, dy: -body).contains(hull) }),
                      !(members.count <= 2 && members.contains { LayoutReconstructor.isFractionBar($0, in: lines, body: body) })
                else { continue }
                let interior = block.hull.insetBy(dx: 6, dy: 6)
                let rules = members.filter { $0.width >= $0.height && $0.midY > interior.minY && $0.midY < interior.maxY }
                // The box around the table shades nothing; its bands and cells must.
                let shading = tints.filter { tint in
                    !(tint.width * tint.height >= block.hull.width * block.hull.height * 0.9
                      && tints.contains { $0 != tint && tint.contains($0) })
                }
                if !block.ruled && rules.count >= 2 && coverage(of: union(rules), by: shading) < 0.8 {
                    restored += stroked.filter { $0.rect.intersects(hull) }.flatMap(\.strokes)
                    continue
                }
                separators += members
                continue
            }
            // Solid ink inside a tinted block (a chart in a sidebar) keeps the block's full-width
            // band between the prose above and below it, so tick labels, legends, captions and
            // notes that only the raster carries stay with the graphic while the prose reflows.
            guard let block = blocks.first(where: { mostlyInside(hull, $0.hull) }) else { continue }
            // Border strokes along the block's edges are decoration connected to the figure;
            // the figure's own extent decides which prose lies above and below it.
            let edges = block.hull.insetBy(dx: 6, dy: 6)
            let core = union(members.filter { member in
                !isThin(member) || (member.width > member.height
                    ? member.midY > edges.minY && member.midY < edges.maxY
                    : member.midX > edges.minX && member.midX < edges.maxX)
            })
            guard !core.isNull else { continue }
            // Art that stands beside the block's text rather than between its lines (the insignia
            // on a header band) keeps its own extent; anything the text runs across keeps the
            // block's full-width band between the lines above and below it.
            if !block.prose.contains(where: { min($0.rect.maxX, core.maxX) - max($0.rect.minX, core.minX) > 0 }) {
                carved.append(core)
                consumed += members
                continue
            }
            let above = block.prose.filter { $0.rect.minY >= core.maxY - 1 }.map(\.rect.minY).min() ?? block.hull.maxY
            let below = block.prose.filter { $0.rect.maxY <= core.minY + 1 }.map(\.rect.maxY).max() ?? block.hull.minY
            carved.append(CGRect(x: block.hull.minX, y: below, width: block.hull.width, height: max(0, above - below)).union(core))
            consumed += members
        }
        // A stroked box that became a tint gives up its strokes unless a ruled grid inside it
        // restored them; a stroked box that is not a tint keeps them as ordinary ink.
        let framed = stroked.filter { tints.contains($0.rect) && !restored.contains($0.strokes[0]) }
        let consumedStrokes = framed.flatMap(\.strokes)
        let kept = paints.map(\.rect).filter { rect in
            !tints.contains(rect) && !separators.contains(rect) && !consumed.contains(rect) && !consumedStrokes.contains(rect)
        }
        let tinted = tints.filter { tint in !stroked.contains { $0.rect == tint && restored.contains($0.strokes[0]) } }
        return Result(graphics: seedClusters(kept + carved, lines: lines), tints: tinted, separators: separators)
    }
}
