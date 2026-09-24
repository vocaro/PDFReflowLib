import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private struct ClosedUnitCapture: Decodable {
    struct Page: Decodable { var nativePage: PageContent; var paintOperations: [GraphicsReader.Paint] }
    var sourceSHA256: String
    var pages: [Page]
}

@Test func capturedFedClosedUnitsPreserveCrossPageBody() throws {
    let capture = try JSONDecoder().decode(ClosedUnitCapture.self,
        from: Data(contentsOf: fixtureURL("fed-cross-page-panels.json")))
    #expect(capture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    var pages: [Int: PageContent] = [:]
    for source in capture.pages {
        var page = source.nativePage
        page.closedNativeFrames = ClosedSourceUnits.frames(paints: source.paintOperations, bounds: page.bounds)
        page.lines.removeAll { $0.rect.minY > 730 || $0.rect.maxY < 40 }
        pages[page.number] = page
    }
    let vocabulary = LayoutReconstructor.vocabulary(in: Array(pages.values)).union(["majority", "institutions"])
    func make(_ page: PageContent) -> [ReflowBlock] {
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: page,
            images: LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element,"p\(page.number)-\($0.offset)") },
            vocabulary: vocabulary, warnings: &warnings, documentBody: 10)
    }
    let cases: [(Int,String,String)] = [
        (21,"Board four times","a year, as required by law"),
        (40,"When the","securities are bought or sold"),
        (47,"The vast major","ity of the Federal Reserve"),
        (55,"for large banking","institutions and the Financial Stability Report"),
        (93,"interbank transactions)","and between businesses"),
        (97,"Much of the recent","growth in ACH payments"),
        (98,"all institu","tions dealing with the Federal Reserve directly"),
        (100,"before a business","day and closes at 7:00 p.m."),
        (103,"Bureau of Engraving","and Printing (BEP)")]
    func canonical(_ text: String) -> String { text.lowercased().filter(\.isLetter) }
    for (number,left,right) in cases {
        let previous = try #require(pages[number]), next = try #require(pages[number+1])
        let before = make(previous), after = make(next)

        var result: [ReflowBlock] = [], warnings: [ConversionWarning] = []
        LayoutReconstructor.appendPage(before, page: previous, previousPage: nil, to: &result,
            vocabulary: vocabulary, warnings: &warnings)
        let tail = LayoutReconstructor.amendableTail(of: result)
        let emitted = Array(result.dropLast(tail)); result = Array(result.suffix(tail))
        LayoutReconstructor.appendPage(after, page: next, previousPage: previous, to: &result,
            vocabulary: vocabulary, warnings: &warnings)
        result = emitted + result
        let expected = canonical(left+right)
        #expect(result.contains { canonical($0.text).contains(expected) && $0.sourcePages.contains(number+1) }, "Source \(number)→\(number+1)")
        #expect(result.filter { $0.closedUnit != nil } == (before+after).filter { $0.closedUnit != nil })
        #expect(result.filter(\.isImage).map(\.page) == (before+after).filter(\.isImage).map(\.page))
        if number == 21 {
            let council = try #require(result.firstIndex { $0.text.hasPrefix("established by the Board of Governors in 2012") })
            let sidebar = try #require(result.firstIndex { $0.text.hasPrefix("More on Federal Reserve Advisory Councils") })
            let nextItem = try #require(result.firstIndex { $0.text.hasPrefix("4. Community Advisory Council") })
            #expect(council < sidebar && sidebar < nextItem)
        }
    }
}

@Test func genuineOpeningSourceBoxesKeepTheirPositionAndPageMarker() throws {
    let capture = try JSONDecoder().decode(ClosedUnitCapture.self,
        from: Data(contentsOf: fixtureURL("gpo-cross-page-panels.json")))
    #expect(capture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    let pages = Dictionary(uniqueKeysWithValues:capture.pages.map { source in
        var page = source.nativePage
        page.lines.removeAll { $0.rect.minY > 550 }
        return (page.number,page)
    })
    for (number,box,continuation) in [(163,"Detainee Interrogation Reports","school, KSM left Kuwait"),
                                     (373,"June 2001:","responsible for making it work")] {
        let previous = try #require(pages[number]), next = try #require(pages[number+1])
        var warnings: [ConversionWarning] = [], result: [ReflowBlock] = []
        let vocabulary = LayoutReconstructor.vocabulary(in:[previous,next])
        for page in [previous,next] {
            let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element,"p\(page.number)-\($0.offset)") }
            let blocks = LayoutReconstructor.blocks(page:page,images:images,vocabulary:vocabulary,warnings:&warnings,documentBody:9.5)
            LayoutReconstructor.appendPage(blocks,page:page,previousPage:page.number == number ? nil : previous,
                to:&result,vocabulary:vocabulary,warnings:&warnings)
        }
        let marker = try #require(result.firstIndex { $0.content == .sourcePage(number+1) })
        let framed = try #require(result.firstIndex { $0.page == number+1 && $0.text.contains(box) })
        let body = try #require(result.firstIndex { $0.text.hasPrefix(continuation) })
        #expect(marker < framed && framed < body)
        #expect(result[body].page == number+1 && result[body].sourcePages.isEmpty)
    }
}

private func closedBlocks(page: Int = 1) -> [ReflowBlock] {
    ["A source-framed heading", "The sidebar contains its own complete explanation."].enumerated().map { index,text in
        var block = ReflowBlock(content:.paragraph(InlineText(text,style:.italic)),page:page)
        block.closedUnit = .init(id:7,position:index,count:2)
        return block
    }
}

@Test(arguments:["complete","missing","count","position","page","marker","inlineMarker","unproved"])
func onlyCompleteSourceUnitsCanRemainInTheStreamingTail(variant:String) {
    var unit = closedBlocks()
    switch variant {
    case "missing": unit.removeFirst()
    case "count": unit[0].closedUnit?.count=3
    case "position": unit[0].closedUnit?.position=1
    case "page": unit[0].page=2
    case "marker": unit[0].content = .sourcePage(1)
    case "inlineMarker": unit[0].content = .paragraph(InlineText(elements:[.sourcePage(2)]))
    case "unproved": unit[0].closedUnit=nil
    default: break
    }
    let paragraph = ReflowBlock(content:.paragraph(InlineText("A sentence continues across the source page boundary")),page:1)
    let blocks = [ReflowBlock(content:.sourcePage(1),page:1),paragraph]+unit
    #expect(LayoutReconstructor.amendableTail(of:blocks) == (variant == "complete" ? 3 : 1))
    #expect(LayoutReconstructor.amendableTail(of:blocks+[.init(content:.sourcePage(2),page:2)]+closedBlocks(page:2)) == 1)
}

@Test func sourceUnitsRejectSharedTagsAndInterruptedOwnership() {
    let panel = CGRect(x:10,y:100,width:200,height:80)
    var elements = (0..<3).map { index in
        let line = TextLine(text:"The source panel has a complete sentence with enough words on each row.",
            rect:CGRect(x:20,y:150-Double(index)*15,width:180,height:10),fontSize:10)
        return LayoutReconstructor.Element(rect:line.rect,line:line)
    }
    #expect(ClosedSourceUnits.ranges(elements,panels:[panel,panel.insetBy(dx:2,dy:2)]) == [0..<3])
    let tag = TextStructure(group:8,order:0,headingLevel:0,lineCount:2)
    elements[0].line?.structure=tag
    var outside = TextLine(text:"Outside body paragraph shares the source tag.",rect:CGRect(x:20,y:220,width:180,height:10),fontSize:10)
    outside.structure=tag
    elements.append(.init(rect:outside.rect,line:outside))
    #expect(ClosedSourceUnits.ranges(elements,panels:[panel]).isEmpty)
    for wrapper in [LayoutReconstructor.Element(rect:outside.rect,aside:[outside]),
                    .init(rect:outside.rect,quotation:[outside]),
                    .init(rect:outside.rect,caption:[outside]),
                    .init(rect:outside.rect,nativePanel:[outside]),
                    .init(rect:outside.rect,image:"photo",pictureCaption:[outside])] {
        elements[3]=wrapper
        #expect(ClosedSourceUnits.ranges(elements,panels:[panel]).isEmpty)
    }
    elements[3] = .init(rect:outside.rect,line:outside)
    elements[0].line?.structure=nil
    #expect(ClosedSourceUnits.ranges(elements,panels:[panel]) == [0..<3])
    elements.swapAt(1,3)
    #expect(ClosedSourceUnits.ranges(elements,panels:[panel]).isEmpty)
}

@Test func closedFrameProofRequiresAllFourContinuousStrokeSides() {
    let bounds=CGRect(x:0,y:0,width:600,height:800)
    func stroke(_ a:CGPoint,_ b:CGPoint)->GraphicsReader.Paint {
        .init(rect:CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)),strokeOnly:true,vertices:[a,b])
    }
    let strokes=[stroke(.init(x:50,y:100),.init(x:550,y:100)),stroke(.init(x:50,y:400),.init(x:550,y:400)),
        stroke(.init(x:50,y:100),.init(x:50,y:250)),stroke(.init(x:50,y:250),.init(x:50,y:400)),
        stroke(.init(x:550,y:100),.init(x:550,y:400))]
    #expect(ClosedSourceUnits.frames(paints:strokes,bounds:bounds)==[CGRect(x:50,y:100,width:500,height:300)])
    for index in strokes.indices { #expect(ClosedSourceUnits.frames(paints:strokes.enumerated().filter{$0.offset != index}.map(\.element),bounds:bounds).isEmpty) }
    var filled=strokes;filled[0].strokeOnly=false;filled[0].filled=true
    #expect(ClosedSourceUnits.frames(paints:filled,bounds:bounds).isEmpty)
    #expect(ClosedSourceUnits.frames(paints:Array(repeating:strokes[0],count:2001),bounds:bounds).isEmpty)
}

@Test func continuedParagraphKeepsOnePackagedParagraphAndClosedUnitStyles() async throws {
    let bounds=CGRect(x:0,y:0,width:600,height:800)
    let previous=PageContent(number:1,bounds:bounds,lines:[TextLine(text:"A continuing sentence with enough words in its ordinary body paragraph reaches",rect:CGRect(x:40,y:50,width:300,height:10),fontSize:10)],graphics:[])
    let next=PageContent(number:2,bounds:bounds,lines:[TextLine(text:"the next source page.",rect:CGRect(x:40,y:740,width:300,height:10),fontSize:10)],graphics:[])
    var blocks=[ReflowBlock(content:.sourcePage(1),page:1),.init(content:.paragraph(InlineText("A continuing sentence with enough words in its ordinary body paragraph reaches",style:.bold)),page:1)]+closedBlocks()
    let unit=Array(blocks.suffix(2))
    var warnings:[ConversionWarning]=[]
    LayoutReconstructor.appendPage([.init(content:.paragraph(InlineText("the next source page.",style:.italic)),page:2)],
        page:next,previousPage:previous,to:&blocks,vocabulary:[],warnings:&warnings)
    #expect(Array(blocks[1...2])==unit)
    #expect(blocks.last?.sourcePages == [2])
    let directory=try testPDFDirectory();defer{try? FileManager.default.removeItem(at:directory)}
    let book=ReflowDocument(metadata:.init(title:"Closed source units",language:"en"),blocks:blocks,assets:[])
    let output=try await EPUBWriter.write(book,maximumOutputBytes:1_000_000,directory:directory,progress:{_ in})
    let archive=try Archive(url:output,accessMode:.read)
    let chapter=try archive.entryText("EPUB/chapter-1.xhtml")
    let paragraphs=chapter.components(separatedBy:"</p>")
    #expect(paragraphs.contains{$0.contains("A continuing sentence with enough words in its ordinary body paragraph reaches") && $0.contains("the next source page.") && $0.contains("page-2")})
    #expect(chapter.components(separatedBy:"id=\"page-2\"").count-1 == 1)
    #expect(chapter.contains("<em>The sidebar contains its own complete explanation.</em>"))
}

@Test(arguments:[false,true])
func sourceUnitsAreBarriersAtAJoinEndpoint(opening:Bool) {
    let bounds=CGRect(x:0,y:0,width:600,height:800)
    let previous=PageContent(number:1,bounds:bounds,lines:[TextLine(text:"An ordinary paragraph has enough words and continues",rect:CGRect(x:40,y:50,width:300,height:10),fontSize:10)],graphics:[])
    let next=PageContent(number:2,bounds:bounds,lines:[TextLine(text:"on the next page.",rect:CGRect(x:40,y:740,width:300,height:10),fontSize:10)],graphics:[])
    var left=ReflowBlock(content:.paragraph(InlineText(previous.lines[0].text)),page:1)
    var right=ReflowBlock(content:.paragraph(InlineText(next.lines[0].text)),page:2)
    // A partial marked unit must never fall back to the ordinary paragraph join.
    if opening { right.closedUnit = .init(id:0,position:0,count:2) }
    else { left.closedUnit = .init(id:0,position:1,count:2) }
    var blocks=[left],warnings:[ConversionWarning]=[]
    LayoutReconstructor.appendPage([right],page:next,previousPage:previous,to:&blocks,vocabulary:[],warnings:&warnings)
    #expect(blocks == [left,.init(content:.sourcePage(2),page:2),right])
}

@Test func closedUnitBoundariesPreventHeadingContinuation() {
    var assembler=BlockAssembler(page:1,body:10,hyphens:HyphenContext())
    func line(_ text:String,_ y:CGFloat)->TextLine {
        TextLine(text:text,rect:CGRect(x:40,y:y,width:100,height:10),fontSize:10)
    }
    assembler.append(line("表題",100),as:.heading)
    let start=assembler.beginClosedUnit()
    assembler.append(line("説明",90),as:.heading)
    assembler.endClosedUnit(start:start)
    assembler.append(line("本文",80),as:.heading)
    let blocks=assembler.finish()
    #expect(blocks.map(\.text)==["表題","説明","本文"])
    #expect(blocks.map(\.closedUnit)==[nil,.init(id:1,position:0,count:1),nil])
}
