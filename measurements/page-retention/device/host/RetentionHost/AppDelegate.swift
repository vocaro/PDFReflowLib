import CryptoKit
import Foundation
import os
import PDFReflowLib
import UIKit

// Temporary physical-device measurement host for the #15 page-retention selection.
// Launch with PDFREFLOW_DEVICE_CASE (warren|noaa) and PDFREFLOW_PAGE_RETENTION set; the
// library reads the retention variable itself. One strategy per process launch.

private func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

private final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var samples = 0
    private let timer: DispatchSourceTimer

    init() {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "footprint-sampler", qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [self] in
            let value = footprintBytes()
            lock.lock(); peak = max(peak, value); samples += 1; lock.unlock()
        }
    }

    func start() { timer.resume() }

    func stop() -> (peak: UInt64, samples: Int) {
        timer.cancel()
        lock.lock(); defer { lock.unlock() }
        return (peak, samples)
    }
}

private let logURL: URL = {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documents.appendingPathComponent("measurement.log")
}()

private func emit(_ line: String) {
    let stamped = "\(Date().timeIntervalSince1970) " + line
    print(stamped)
    fflush(stdout)
    FileHandle.standardError.write(Data((stamped + "\n").utf8))
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile(); handle.write(Data((stamped + "\n").utf8)); try? handle.close()
    } else {
        try? Data((stamped + "\n").utf8).write(to: logURL)
    }
}

enum Measurement {
    static func run() async {
        let environment = ProcessInfo.processInfo.environment
        emit("PDFREFLOW_DEVICE_ENV " + environment.keys.filter { $0.hasPrefix("PDFREFLOW") }.sorted().joined(separator: ","))
        guard let caseName = environment["PDFREFLOW_DEVICE_CASE"],
              let source = Bundle.main.url(forResource: caseName, withExtension: "pdf") else {
            emit("PDFREFLOW_DEVICE_ERROR missing PDFREFLOW_DEVICE_CASE or bundled source"); return
        }
        let retention = environment["PDFREFLOW_PAGE_RETENTION"] ?? "default"
        var options = ConversionOptions()
        switch caseName {
        case "noaa":
            options.referenceImages = .automatic
            options.maximumOutputBytes = 4 * 1_024 * 1_024 * 1_024
            options.maximumEPUBBytes = 4 * 1_024 * 1_024 * 1_024
        case "warren":
            options.referenceImages = .never
        case "faa":
            options.referenceImages = .automatic
        default:
            emit("PDFREFLOW_DEVICE_ERROR unknown case \(caseName)"); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retention-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent(caseName + ".epub")
        let device = await MainActor.run { "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }
        let before = footprintBytes()
        let availableBefore = os_proc_available_memory()
        emit("PDFREFLOW_DEVICE_START case=\(caseName) retention=\(retention) device=\(device) footprintBefore=\(before) available=\(availableBefore)")
        let sampler = FootprintSampler()
        sampler.start()
        let started = Date()
        let lastTenth = OSAllocatedUnfairLock(initialState: -1)
        do {
            let report = try await PDFConverter().convert(from: source, to: destination, options: options) { event in
                let tenth = Int(event.fractionCompleted * 10)
                let changed = lastTenth.withLock { state -> Bool in
                    if tenth != state { state = tenth; return true }
                    return false
                }
                if changed { emit("PDFREFLOW_DEVICE_PROGRESS \(tenth * 10)% \(event.stage.rawValue) footprint=\(footprintBytes())") }
            }
            let seconds = Date().timeIntervalSince(started)
            let (peak, samples) = sampler.stop()
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            var hasher = SHA256()
            for warning in report.warnings {
                hasher.update(data: Data("\(warning.code.rawValue):\(warning.page):\(warning.message)".utf8))
            }
            hasher.update(data: Data("\(report.pageCount):\(report.reflowedPageCount):\(report.recognizedPageCount):\(report.imageCount)".utf8))
            let record: [String: Any] = [
                "case": caseName, "retention": retention, "device": device,
                "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                "availableMemoryBeforeBytes": availableBefore,
                "footprintBeforeBytes": before, "peakFootprintBytes": peak, "footprintSamples": samples,
                "peakRSSBytes": usage.ru_maxrss, "seconds": seconds, "epubBytes": size,
                "pages": report.pageCount, "reflowedPages": report.reflowedPageCount,
                "recognizedPages": report.recognizedPageCount, "images": report.imageCount,
                "warnings": report.warnings.count,
                "reportFingerprint": hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            ]
            let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            emit("PDFREFLOW_DEVICE_RESULT " + String(decoding: json, as: UTF8.self))
        } catch {
            _ = sampler.stop()
            emit("PDFREFLOW_DEVICE_ERROR \(error)")
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.isIdleTimerDisabled = true
        Task.detached {
            await Measurement.run()
            emit("PDFREFLOW_DEVICE_DONE")
            exit(0)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// iOS 27 requires the scene lifecycle; the generated manifest names this class.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(frame: window.bounds)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "PDFReflowLib retention measurement running.\nKeep this app in the foreground."
        controller.view.addSubview(label)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }
}
