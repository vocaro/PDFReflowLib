import CryptoKit
import Foundation
import os
import PDFReflowLib
import UIKit

// One conversion per process. Environment settings and source identity travel with the result.
private func memory() -> [String: UInt64] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { return ["availableBytes": UInt64(os_proc_available_memory())] }
    return ["footprintBytes": info.phys_footprint, "residentBytes": info.resident_size,
            "purgeableResidentBytes": info.purgeable_volatile_resident,
            "compressedBytes": info.compressed, "availableBytes": UInt64(os_proc_available_memory())]
}

private final class Sampler: @unchecked Sendable {
    let lock = NSLock()
    var samples: [[String: UInt64]] = []
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "raster-memory"))
    init() {
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [self] in
            let sample = memory()
            lock.lock(); samples.append(sample); lock.unlock()
        }
        timer.resume()
    }
    func stop() -> [[String: UInt64]] {
        timer.cancel()
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}

private func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

private func sourceHash(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.isIdleTimerDisabled = true
        Task.detached {
            do { try await Self.measure() }
            catch { print("RASTER_ERROR \(error)"); fflush(stdout); exit(1) }
            print("RASTER_DONE"); fflush(stdout); exit(0)
        }
        return true
    }

    static func measure() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let name = env["RASTER_CASE"], let source = Bundle.main.url(forResource: name, withExtension: "pdf"),
              let dpi = Double(env["RASTER_DPI"] ?? "180"),
              let pixels = Int(env["RASTER_PIXELS"] ?? "12000000") else { throw CocoaError(.fileReadNoSuchFile) }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("current")
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options = ConversionOptions()
        options.rasterDPI = dpi; options.maximumRasterPixels = pixels
        options.packageIdentifier = "raster-qualification-28"
        options.modificationDate = Date(timeIntervalSince1970: 1_767_225_600)
        if env["RASTER_OCR"] == "always" { options.ocr = .always }
        if env["RASTER_OCR"] == "never" { options.ocr = .never }
        // Only stress cases opt into forced full-page references.
        if env["RASTER_REFERENCES"] == "always" { options.referenceImages = .always }
        if let value = env["RASTER_OUTPUT_BUDGET"] {
            guard let bytes = Int64(value), bytes > 0 else { throw ConversionError.invalidOptions("output budget must be positive") }
            options.maximumOutputBytes = bytes
        }
        let output = directory.appendingPathComponent(name + ".epub")
        let hash = try sourceHash(source)
        let device = await MainActor.run { "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }
        var record: [String: Any] = ["case": name, "sourceSHA256": hash, "rasterDPI": dpi,
            "maximumRasterPixels": pixels, "maximumOutputBytes": options.maximumOutputBytes, "ocr": env["RASTER_OCR"] ?? "automatic",
            "referenceImages": env["RASTER_REFERENCES"] ?? "automatic",
            "device": device, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "before": memory(), "status": "started"]
        try writeJSON(record, to: directory.appendingPathComponent("metrics.json"))
        print("RASTER_START \(name) dpi=\(dpi) pixels=\(pixels)"); fflush(stdout)
        let sampler = Sampler()
        let start = Date()
        do {
            let report = try await PDFConverter().convert(from: source, to: output, options: options)
            record["status"] = "completed"
            record["epubBytes"] = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: directory.appendingPathComponent("conversion-report.json"))
        } catch {
            record["status"] = "failed"; record["error"] = String(describing: error)
        }
        record["seconds"] = Date().timeIntervalSince(start)
        let samples = sampler.stop()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        record["peakRSSBytes"] = usage.ru_maxrss
        record["sampledPeakFootprintBytes"] = samples.compactMap { $0["footprintBytes"] }.max()
        record["sampledPeakPurgeableResidentBytes"] = samples.compactMap { $0["purgeableResidentBytes"] }.max()
        record["minimumAvailableBytes"] = samples.compactMap { $0["availableBytes"] }.min()
        record["after"] = memory()
        try writeJSON(samples, to: directory.appendingPathComponent("memory-samples.json"))
        try writeJSON(record, to: directory.appendingPathComponent("metrics.json"))
        print("RASTER_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
        fflush(stdout)
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller; window.makeKeyAndVisible(); self.window = window
    }
}
