import SwiftUI
import Foundation

/* C 回调必须是全局函数（闭包会捕获上下文，编译不过） */
private func chrisExceptionHandler(_ ex: NSException) {
    CrashCatcher.report("NSException", "\(ex.name.rawValue): \(ex.reason ?? "")")
}
private func chrisSignalHandler(_ s: Int32) {
    CrashCatcher.report("Signal", "signal \(s)\n" + Thread.callStackSymbols.joined(separator: "\n"))
    signal(s, SIG_DFL)
}

/* 崩溃上报：App 一旦崩，把原因和调用栈发到服务器（data/client-errors.jsonl），
   这样在电脑上就能看到崩在哪一行，不用把手机连电脑抓日志。 */
/// 当前进程占了多少内存（phys_footprint —— 系统就是按这个值决定杀不杀 App）。
/// 打点里带上它，就能看出「一进聊天就被系统杀掉」到底是内存爆了，还是别的原因。
/// 返回 -1 表示这次读不到。
func chrisMemMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576.0
}

/// 「内存 123MB（还能用 4567MB）」这种一行字，直接拼进打点
func chrisMemText() -> String {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return "内存读不到" }
    let used = Double(info.phys_footprint) / 1_048_576.0
    let left = Double(info.limit_bytes_remaining) / 1_048_576.0
    return String(format: "内存%.0fMB(剩%.0fMB)", used, left)
}

enum CrashCatcher {
    private static var installed = false

    /* ⚠ 以前崩溃信息只写在 UserDefaults 里。UserDefaults 不是马上落盘的：
       崩的瞬间写完、进程紧接着被系统杀掉（看门狗 / SIGKILL），这一条就**丢了** ——
       我们服务器上看到的就是「只有启动、没有崩溃栈」。
       所以现在**同时写一份文件**（.atomic 写完就落盘），下次启动一定补得回去。 */
    private static var crashFile: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("chris-last-crash.txt")
    }
    private static func saveCrashFile(_ text: String) {
        guard let f = crashFile else { return }
        try? Data(text.prefix(20000).utf8).write(to: f, options: [.atomic])
    }
    private static func loadCrashFile() -> String {
        guard let f = crashFile, let d = try? Data(contentsOf: f) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    private static func clearCrashFile() { if let f = crashFile { try? FileManager.default.removeItem(at: f) } }

    static func install() {
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler(chrisExceptionHandler)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, chrisSignalHandler)
        }
        /* 上次崩了但没发出去（崩的瞬间网络不通 / 进程被系统直接杀掉）：
          这次一进来就补发一遍，这样电脑这边才看得到崩在哪。 */
        uploadPending()
        /* 启动打点：每次打开 App 记一条。被系统直接杀掉（比如卡死被看门狗干掉）不会留崩溃栈，
           但「这个时间点启动过、之后就没消息了」这条线索能说明问题。 */
        launchBeacon()
    }

    private static func launchBeacon() {
        let payload: [String: Any] = [
            "kind": "launch",
            "text": AppInfo.build,
            "app": String(AppInfo.build.prefix(28))
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: API.shared.base + "/api/clientlog") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        /* ⚠ 必须用 App 自己的会话（TrustAllDelegate）—— 用 URLSession.shared 的话
           我们的自签证书过不了校验，日志**一条都发不出来**（线上 10-07 之后就断在这儿了） */
        API.shared.session.dataTask(with: req).resume()
    }

    /// 补发上次没送出去的崩溃信息（存成 kind\ntext\n\nstack 这种格式）
    static func uploadPending() {
        /* 先看落盘那份（更靠得住），没有再用 UserDefaults 里的 */
        let fromFile = loadCrashFile()
        let raw = fromFile.isEmpty ? (UserDefaults.standard.string(forKey: "chris.lastCrash") ?? "") : fromFile
        let at = UserDefaults.standard.string(forKey: "chris.lastCrashAt") ?? ""
        guard !raw.isEmpty else { return }
        if (UserDefaults.standard.string(forKey: "chris.lastCrashSent") ?? "") == at { return }
        let parts = raw.components(separatedBy: "\n\n")
        let head = parts.first ?? raw
        let stack = parts.count > 1 ? parts[1] : ""
        let headLines = head.components(separatedBy: "\n")
        let kind = headLines.first ?? "Crash"
        let text = headLines.dropFirst().joined(separator: "\n")
        var payload: [String: Any] = [
            "kind": "补报/" + kind,
            "text": String(text.prefix(3000)),
            "stack": String(stack.prefix(6000)),
            "app": AppInfo.build.prefix(28).description,
            "at": at.isEmpty ? ISO8601DateFormatter().string(from: Date()) : at,
            "late": true
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let url = URL(string: API.shared.base + "/api/clientlog") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 6
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            API.shared.session.dataTask(with: req) { _, resp, _ in
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    UserDefaults.standard.set(at, forKey: "chris.lastCrashSent")
                    clearCrashFile()
                }
            }.resume()
        }
    }

    /// 主动上报（不一定崩，也可以记异常）
    static func report(_ kind: String, _ text: String) {
        note(kind, text, keepLocal: true)
    }

    /// 「设置 → 诊断工具」要看的：本机落盘的那份上次崩溃（没有就是空串）
    static func savedCrash() -> String { loadCrashFile() }

    /// 只上报、不当崩溃记（不写 lastCrash，所以不会在 App 里弹「上次崩了」）：
    /// 排查线上问题用，比如「视频号哪条没起来、为什么」。
    static func note(_ kind: String, _ text: String, keepLocal: Bool = false) {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        if keepLocal {
            /* 先存在本机上：万一网络不通，下次打开 App 会把这页弹出来，截图发我一样能看 */
            UserDefaults.standard.set("\(kind)\n\(text)\n\n\(stack)".prefix(6000).description,
                                      forKey: "chris.lastCrash")
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "chris.lastCrashAt")
            /* 顺手**落盘**一份：被杀掉也不丢（见上面 crashFile 那段说明） */
            saveCrashFile("\(kind)\n\(text)\n\n\(stack)")
        }
        let payload: [String: Any] = [
            "kind": kind,
            "text": String(text.prefix(4000)),
            "stack": keepLocal ? String(stack.prefix(6000)) : "",
            "lang": Lang.code,
            "app": AppInfo.build.prefix(28).description,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
        guard let url = URL(string: API.shared.base + "/api/clientlog"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        if keepLocal {
            /* 崩的时候主线程已经不可靠了，用同步发送，确保能发出去 */
            let sem = DispatchSemaphore(value: 0)
            API.shared.session.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + 3)
        } else {
            /* 普通日志：异步发就行，别卡着界面 */
            API.shared.session.dataTask(with: req).resume()
        }
    }
}
