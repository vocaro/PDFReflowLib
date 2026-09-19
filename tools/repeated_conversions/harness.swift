// Repeated in-process conversions through the public API (#4). One JSON line per conversion.
// usage: harness ROUNDS OUTPUT-DIRECTORY input.pdf...
// LEAKS=1 (macOS only) runs /usr/bin/leaks on this process after every round. Packaging is
// pinned, so every round of one input must produce the same EPUB digest. See record.md.
import CryptoKit
import Darwin
import Foundation
import PDFReflowLib

func memory() -> [String: Any] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let capacity = Int(count)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    // The default zone alone: the purgeable zone holds Core Graphics caches the system may drop.
    var stats = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &stats)
    return ["footprint": Int(info.phys_footprint), "peakRSS": Int(usage.ru_maxrss),
            "defaultZoneInUse": Int(stats.size_in_use)]
}

func emit(_ record: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

#if os(macOS)
func leaks() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/leaks")
    process.arguments = [String(getpid())]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n")
        .first { $0.contains("leaks for") }.map(String.init) ?? "unavailable"
}
#endif

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, let rounds = Int(arguments[0]), rounds > 0 else {
    FileHandle.standardError.write(Data("usage: harness ROUNDS OUTPUT-DIRECTORY input.pdf...\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let inputs = arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var options = ConversionOptions()
options.packageIdentifier = "urn:uuid:00000000-0000-0000-0000-000000000004"
options.modificationDate = Date(timeIntervalSince1970: 1_767_225_600)
var start = memory()
start["event"] = "start"
emit(start)
let converter = PDFConverter()
for round in 1...rounds {
    for input in inputs {
        let destination = output.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".epub")
        try? FileManager.default.removeItem(at: destination)
        let began = Date()
        let report = try await converter.convert(from: input, to: destination, options: options)
        let digest = SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.removeItem(at: destination)
        var record = memory()
        record["round"] = round
        record["input"] = input.lastPathComponent
        record["pages"] = report.pageCount
        record["seconds"] = Date().timeIntervalSince(began)
        record["sha256"] = digest
        emit(record)
    }
    #if os(macOS)
    if ProcessInfo.processInfo.environment["LEAKS"] == "1" { emit(["round": round, "leaks": leaks()]) }
    #endif
}
