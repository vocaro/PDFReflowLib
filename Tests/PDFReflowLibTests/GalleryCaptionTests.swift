import Foundation
import Testing
@testable import PDFReflowLib

@Test func techportGalleryKeepsEachCompleteCaptionWithItsPicture() throws {
    let fixture = try SourceLayoutFixture.load("techport-magazine-5")
    #expect(fixture.sourceSHA256 == "0fce4b68983ad8a216c8228ec44697c61ab41977ad41733c465ebebec3976ff0")
    let page = fixture.content()
    let groups = GalleryCaptions.groups(lines: page.lines, images: page.pictures, body: 9)
    #expect(groups.map(\.image) == [0, 1, 2])
    #expect(groups.map(\.lines) == [Array(5...12), Array(18...24), Array(13...17)])
    #expect(groups.flatMap(\.lines).count == Set(groups.flatMap(\.lines)).count)
    let text = groups.map { group in group.lines.map { page.lines[$0].text }.joined(separator: " ") }
    #expect(text == [
        "Tank Health Monitoring - In- Space Propellant Gauging Accurate measurement of cryogenic liquid propellant quantity in space without propulsive settling maneuvers (https://techport.nasa.gov/imag e/41318)",
        "Tank Health Monitoring: Existing propellant gauging methods comparison Existing propellant gauging methods comparison (https://techport.nasa.gov/imag e/41319)",
        "The Basic Formula Tank Health Monitoring Basic Formula (https://techport.nasa.gov/imag e/41316)",
    ])
    // The grouped units themselves now have a shared upper edge and separate measures.
    let elements = groups.map { LayoutReconstructor.Element(rect: $0.rect, image: String($0.image)) }
    #expect(LayoutReconstructor.ordered(elements, bodySize: 9).map(\.image) == ["0", "1", "2"])
    #expect(LayoutReconstructor.ordered(elements, bodySize: 9, rightToLeft: true).map(\.image) == ["2", "1", "0"])
    // Source body estimation may choose Verdana 8.25 or the nine-point caption runs.
    #expect(GalleryCaptions.groups(lines: page.lines, images: page.pictures, body: 8.25).map(\.lines)
            == groups.map(\.lines))
    // A preserved crop can include the small border around each source image.
    #expect(GalleryCaptions.groups(lines: page.lines,
                                   images: page.pictures.map { $0.insetBy(dx: -1, dy: -1) }, body: 9).map(\.lines)
            == groups.map(\.lines))
}

@Test func galleryRequiresRepeatedPictureAndCaptionGeometry() throws {
    let page = try SourceLayoutFixture.load("techport-magazine-5").content()
    #expect(GalleryCaptions.groups(lines: page.lines, images: [page.pictures[0]], body: 9).isEmpty)
    var staggered = page.pictures
    staggered[1] = staggered[1].offsetBy(dx: 0, dy: 20)
    // A displaced image cannot carry the caption left behind at its old position.
    #expect(!GalleryCaptions.groups(lines: page.lines, images: staggered, body: 9).contains { $0.image == 1 })
    var crossing = page.lines
    crossing.append(TextLine(text: "Prose crossing two pictures' caption measures",
                             rect: CGRect(x: 36, y: 500, width: 300, height: 10), fontSize: 9))
    #expect(GalleryCaptions.groups(lines: crossing, images: page.pictures, body: 9).isEmpty)
    var remote = page.lines
    for index in 5...24 { remote[index].rect = remote[index].rect.offsetBy(dx: 0, dy: -40) }
    #expect(GalleryCaptions.groups(lines: remote, images: page.pictures, body: 9).isEmpty)
    var unrelated = page.lines
    unrelated.append(TextLine(text: "Unrelated text below the shortest card",
                              rect: CGRect(x: 351, y: 480, width: 145, height: 10), fontSize: 9))
    #expect(GalleryCaptions.groups(lines: unrelated, images: page.pictures, body: 9).isEmpty)
}
