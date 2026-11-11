/*
 * A small memory log for diagnosing the app being ended for using too much memory:
 * every 15 s, a line in Caches/memory.log with the app's footprint (what the system
 * holds against its ~2 GB limit) and what the texture caches hold. The last ~1,000 lines
 * are kept. Read it from the Mac with
 *   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
 *     --domain-identifier com.marioalonso.PhotomosaicTV --source Library/Caches/memory.log --destination .
 */
import Foundation

@MainActor
enum MemoryLog {
    static let file = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("memory.log")

    /// The app's physical footprint in MB.
    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint >> 20) : -1
    }

    static func run(_ player: Player) {
        Task { @MainActor [weak player] in
            write("--- start \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")")
            while let p = player {
                var line = "footprint \(footprint()) MB"
                if let c = p.cache {
                    let m = c.census(.mid), h = c.census(.hires)
                    line += String(format: " · mid %d MB (%d held, %d loading) · full %d MB (%d held, %d loading)",
                                   c.used[.mid]! >> 20, m.held, m.loading, c.used[.hires]! >> 20, h.held, h.loading)
                }
                write(line)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private static var lines = 0

    private static func write(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date()))  \(text)\n"
        lines += 1
        if lines > 1000, let old = try? String(contentsOf: file, encoding: .utf8) {   // keep the last part
            try? (old.split(separator: "\n").suffix(500).joined(separator: "\n") + "\n" + line)
                .write(to: file, atomically: true, encoding: .utf8)
            lines = 500
            return
        }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
