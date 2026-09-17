import Foundation
import CoreGraphics
import CoreText
import Vision

// Render at `scale` of a 1600-wide canvas, then upsample back (blurs like a low-DPI scan).
func render(_ lines: [String], fontSize: CGFloat, scale: CGFloat) -> CGImage {
    let w = 1600, h = 200 + lines.count * Int(fontSize * 1.8)
    let sw = Int(CGFloat(w) * scale), sh = Int(CGFloat(h) * scale)
    let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    small.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); small.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
    small.scaleBy(x: scale, y: scale)
    let font = CTFontCreateWithName("Times New Roman" as CFString, fontSize, nil)
    for (i, s) in lines.enumerated() {
        let attr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
        small.textPosition = CGPoint(x: 60, y: CGFloat(h - 100) - CGFloat(i) * fontSize * 1.8)
        CTLineDraw(CTLineCreateWithAttributedString(attr), small)
    }
    let smallImage = small.makeImage()!
    let big = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    big.interpolationQuality = .low
    big.draw(smallImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    return big.makeImage()!
}

let texts: [String: [String]] = [
    "fr": [
        "Le général a été élevé à Besançon, où l'été est très chaud.",
        "Après la rentrée, les élèves répètent leurs leçons à côté du théâtre.",
        "La société française préfère les fenêtres ouvertes même en hiver.",
        "Il était déjà là quand sa sœur arriva ; ça ne l'a pas étonné.",
        "Les numéros de téléphone sont écrits sur la première page du cahier.",
        "On a dû créer une bibliothèque près de l'hôpital et de la gare.",
    ],
    "de": ["Die Straße führt über die Brücke zur Mühle.", "Größere Häuser stehen hinter dem schönen Gebäude."],
    "ru": ["Москва является столицей России.", "Эта книга была написана в прошлом году."],
    "ja": ["日本語の文章を認識できますか。", "東京は日本の首都です。"],
    "vi": ["Tiếng Việt là ngôn ngữ chính thức của Việt Nam.", "Người dân ở đây rất thân thiện và hiếu khách."],
    "uk": ["Київ є столицею України.", "Її батьки їздили до Львова минулого літа."],
    "zht": ["這本書是去年寫的。", "臺灣的學校圖書館很大。"],
    "th": ["ภาษาไทยเป็นภาษาราชการของประเทศไทย", "นักเรียนไปโรงเรียนทุกวัน"],
    "ar": ["اللغة العربية هي اللغة الرسمية", "ذهب الطلاب إلى المدرسة صباحا"],
    "hi": ["हिन्दी भारत की एक भाषा है।", "बच्चे विद्यालय जाते हैं।"],
    "ko": ["한국어는 대한민국의 공용어입니다.", "학생들은 매일 학교에 갑니다."],
    "homo": ["КОМАР ТАРА МОРЕ СОРТ ХОР", "BOPOH TOPT MAMA KAPTA CAXAP"],
    "frshort": ["été", "à côté", "où", "élève", "déjà vu", "sœur"],
    "en": ["The quick brown fox jumps over the lazy dog near the river bank.",
           "Census data were collected by the bureau during the spring survey."],
]
let args = CommandLine.arguments
guard args.count >= 6 else {
    // Probe 1: the supported list, the default, and which tags `contains` accepts.
    let supported = RecognizeDocumentsRequest(.revision1).supportedRecognitionLanguages
    print("supported", supported.count, supported.map(\.maximalIdentifier))
    print("default", RecognizeDocumentsRequest(.revision1).textRecognitionOptions.recognitionLanguages.map(\.maximalIdentifier))
    for id in ["en", "en-US", "fr", "fr-FR", "de", "pt", "zh", "zh-Hans", "zh-TW", "en-GB", "fr-CA", "tlh"] {
        print(id, "contains:", supported.contains(Locale.Language(identifier: id)))
    }
    exit(0)
}
let mode = args[1]
let fontSize = CGFloat(Double(args[2])!)
let scale = CGFloat(Double(args[3])!)
let correction = args[4] == "1"
let ids = Array(args[5...])
let img = render(texts[mode]!, fontSize: fontSize, scale: scale)
for id in ids {
    for detect in [true, false] {
        var req = RecognizeDocumentsRequest(.revision1)
        req.textRecognitionOptions.useLanguageCorrection = correction
        req.textRecognitionOptions.automaticallyDetectLanguage = detect
        if id != "default" { req.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: id)] }
        do {
            let obs = try await req.perform(on: img, orientation: nil)
            let text = obs.first?.document.text.lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " / ") ?? ""
            print("== \(mode) size=\(fontSize) scale=\(scale) corr=\(correction) lang=\(id) detect=\(detect)\n\(text)")
        } catch { print("== lang=\(id) detect=\(detect) ERROR \(error)") }
    }
}
