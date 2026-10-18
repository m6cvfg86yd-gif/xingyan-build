import SwiftUI
import UIKit
import MultipeerConnectivity
import Photos
import UniformTypeIdentifiers

/// 面对面传输码。二维码只带一次性会话号和显示名，不包含账号或好友关系。
struct NearbyDropInvite: Identifiable, Equatable {
    let id: String
    let name: String

    var link: String {
        var c = URLComponents()
        c.scheme = "xingyan"
        c.host = "drop"
        c.queryItems = [
            URLQueryItem(name: "sid", value: id),
            URLQueryItem(name: "name", value: name)
        ]
        return c.string ?? "xingyan://drop?sid=\(id)"
    }

    static func parse(_ text: String) -> NearbyDropInvite? {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "xingyan",
              (c.host ?? "").lowercased() == "drop" else { return nil }
        let sid = c.queryItems?.first(where: { $0.name == "sid" })?.value ?? ""
        guard sid.count >= 8 else { return nil }
        let name = c.queryItems?.first(where: { $0.name == "name" })?.value ?? "对方"
        return NearbyDropInvite(id: sid, name: name.isEmpty ? "对方" : name)
    }
}

enum NearbyDropPhase: Equatable {
    case idle
    case waiting
    case searching
    case connected
}

/// 双机近距离传输：一边展示二维码并广播，另一边扫码加入。
/// 媒体文件走 MultipeerConnectivity 的点对点连接，不经过聊天服务器。
final class NearbyDropCenter: NSObject, ObservableObject {
    @Published private(set) var phase: NearbyDropPhase = .idle
    @Published private(set) var invite: NearbyDropInvite?
    @Published private(set) var peerName = ""
    @Published private(set) var status = "准备连接…"
    @Published private(set) var activity: [String] = []
    @Published private(set) var sending = 0
    @Published private(set) var receiving = 0

    private let serviceType = "xydrop"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var sessionId = ""
    private var localName = ""
    private var sendQueue: [URL] = []
    private var browseToken = UUID()
    private var tempFiles: [URL] = []

    var isConnected: Bool { phase == .connected }

    func startHosting(name: String) {
        reset()
        let sid = UUID().uuidString.lowercased()
        sessionId = sid
        localName = name.isEmpty ? "星言用户" : name
        let inv = NearbyDropInvite(id: sid, name: localName)
        invite = inv
        status = "等待对方扫码…"
        phase = .waiting

        let peer = makePeerID()
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s

        let a = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["sid": sid, "name": localName],
            serviceType: serviceType
        )
        a.delegate = self
        advertiser = a
        a.startAdvertisingPeer()
    }

    func join(_ target: NearbyDropInvite) {
        reset()
        sessionId = target.id
        localName = UIDevice.current.name
        invite = target
        peerName = target.name
        status = "正在连接 \(target.name)…"
        phase = .searching

        let peer = makePeerID()
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s

        let b = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        b.delegate = self
        browser = b
        b.startBrowsingForPeers()

        let token = UUID()
        browseToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.browseToken == token, self.phase == .searching else { return }
            self.status = "没有找到对方：请两台手机都打开这个页面，并允许本地网络权限"
            self.browser?.stopBrowsingForPeers()
        }
    }

    func stop() {
        reset()
    }

    private func reset() {
        browseToken = UUID()
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
        sendQueue.removeAll()
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles.removeAll()
        phase = .idle
        invite = nil
        peerName = ""
        status = "准备连接…"
        sending = 0
        receiving = 0
    }

    private func makePeerID() -> MCPeerID {
        let raw = UIDevice.current.name.isEmpty ? "星言用户" : UIDevice.current.name
        let suffix = String(UUID().uuidString.prefix(4))
        return MCPeerID(displayName: String(raw.prefix(40)) + "-" + suffix)
    }

    func send(images: [UIImage]) {
        guard !images.isEmpty else { return }
        status = "正在整理照片…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var urls: [URL] = []
            for (i, image) in images.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drop-photo-\(UUID().uuidString)-\(i + 1).jpg")
                if (try? data.write(to: url, options: .atomic)) != nil {
                    urls.append(url)
                }
            }
            DispatchQueue.main.async {
                self.enqueue(urls)
            }
        }
    }

    func send(files: [URL]) {
        guard !files.isEmpty else { return }
        status = "正在准备文件…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var copied: [URL] = []
            for file in files {
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drop-file-\(UUID().uuidString)-\(file.lastPathComponent)")
                if (try? FileManager.default.copyItem(at: file, to: dst)) != nil {
                    copied.append(dst)
                }
            }
            DispatchQueue.main.async {
                self.enqueue(copied)
            }
        }
    }

    private func enqueue(_ urls: [URL]) {
        guard isConnected, !urls.isEmpty else {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
            status = "对方还没连上"
            return
        }
        tempFiles.append(contentsOf: urls)
        sendQueue.append(contentsOf: urls)
        sending += urls.count
        status = "准备发送 \(urls.count) 个文件…"
        sendNext()
    }

    private func sendNext() {
        guard let s = session, let peer = s.connectedPeers.first else {
            status = "对方已断开"
            sending = 0
            return
        }
        guard !sendQueue.isEmpty else {
            status = "发送完成"
            sending = 0
            return
        }
        let url = sendQueue.removeFirst()
        let name = UUID().uuidString.prefix(6) + "-" + url.lastPathComponent
        status = "正在发送 \(url.lastPathComponent)…"
        s.sendResource(at: url, withName: name, toPeer: peer) { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: url)
                self.tempFiles.removeAll { $0 == url }
                if let error {
                    self.status = "发送失败：" + error.localizedDescription
                    self.sending = 0
                    self.sendQueue.removeAll()
                    return
                }
                self.sending = max(0, self.sending - 1)
                self.addActivity("已发送 " + url.lastPathComponent)
                self.sendNext()
            }
        }
    }

    private func addActivity(_ text: String) {
        activity.insert(text, at: 0)
        if activity.count > 8 { activity = Array(activity.prefix(8)) }
    }

    private func saveReceived(_ temp: URL, name: String) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("面对面传输", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = temp.pathExtension.isEmpty
            ? (URL(fileURLWithPath: name).pathExtension)
            : temp.pathExtension
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let safeBase = base.replacingOccurrences(of: "/", with: "_")
        let dst = dir.appendingPathComponent(
            (safeBase.isEmpty ? "文件" : safeBase) + "-" + String(UUID().uuidString.prefix(5))
                + (ext.isEmpty ? "" : "." + ext)
        )
        do {
            try fm.copyItem(at: temp, to: dst)
        } catch {
            DispatchQueue.main.async {
                self.status = "接收失败：" + error.localizedDescription
                self.receiving = max(0, self.receiving - 1)
            }
            return
        }

        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .image) == true {
            if let image = UIImage(contentsOfFile: dst.path) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { state in
                    guard state == .authorized || state == .limited else { return }
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
            }
        } else if type?.conforms(to: .movie) == true {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { state in
                guard state == .authorized || state == .limited else { return }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: dst)
                }
            }
        }

        DispatchQueue.main.async {
            self.receiving = max(0, self.receiving - 1)
            self.status = "已收到 " + dst.lastPathComponent
            self.addActivity("已收到 " + dst.lastPathComponent)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

extension NearbyDropCenter: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.status = "无法开启碰一碰：" + error.localizedDescription
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let session else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }
}

extension NearbyDropCenter: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.status = "无法搜索对方：" + error.localizedDescription
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard phase == .searching, info?["sid"] == sessionId, let session else { return }
        browser.stopBrowsingForPeers()
        peerName = info?["name"] ?? peerID.displayName
        status = "正在连接 \(peerName)…"
        browser.invitePeer(peerID, to: session, withContext: Data(sessionId.utf8), timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { }
}

extension NearbyDropCenter: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.phase = .connected
                self.advertiser?.stopAdvertisingPeer()
                self.browser?.stopBrowsingForPeers()
                self.peerName = self.peerName.isEmpty ? peerID.displayName : self.peerName
                self.status = "已连接，可以发送照片或视频"
                self.addActivity("已连接 " + self.peerName)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .connecting:
                self.status = "正在连接…"
            case .notConnected:
                if self.phase != .idle {
                    self.phase = self.invite == nil ? .idle : .searching
                    self.status = "对方已断开"
                }
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { }

    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) { }

    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        DispatchQueue.main.async {
            self.receiving += 1
            self.status = "正在接收 " + resourceName
        }
    }

    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.receiving = max(0, self.receiving - 1)
                self.status = "接收失败：" + error.localizedDescription
            }
            return
        }
        guard let localURL else { return }
        saveReceived(localURL, name: resourceName)
    }
}
