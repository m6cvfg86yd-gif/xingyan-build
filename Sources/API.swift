import Foundation
import UIKit
import SwiftUI          // 服务页样式里要算颜色（Color）
import AVFoundation     // 视频边下边播要用 AVURLAsset

/* ============================================================ 数据模型 */

struct User: Codable, Identifiable, Hashable {
    var id: String
    /// 脱敏实名（服务端 realNameOf 算好的）：转账页「转账给 **宇」用；
    /// 只有本人和好友的名片才带这个值，陌生人返回空串。
    var realName: String?
    var requestId: String?
    var moodText: String?
    var moodIcon: String?
    var moodColor: String?
    var moodColor2: String?
    /// 状态名（后台配的「摸鱼」这种）和「说点什么」那句自定义文案，是分开的两层
    var moodLabel: String?
    var moodCaption: String?
    /// 状态什么时候过期（毫秒时间戳，0 = 没有状态）
    var moodExpiresAt: Double?
    /// 状态收到的赞（谁赞的）——「朋友的状态」那一页显示 + 判断我赞过没有
    var moodLikes: [String]?
    var moodLikeCount: Int?
    var username: String?
    var nickname: String?
    var avatar: String?
    var bio: String?
    var gender: String?
    var region: String?
    var phone: String?
    var status: String?
    var chatBackground: String?
    var birthday: String?
    var momentCover: String?
    /// 拍一拍后缀（微信：我 → 个人资料 → 拍一拍）：别人拍我时念成「拍了拍我的＿＿」
    var patText: String?
    var bot: Bool?
    /// 这个账号有没有「App 内的管理」权限（上新音乐 / 换图标）——
    /// 服务器 users.json 里 ops=true 才会有；别人看不到这个入口
    var ops: Bool?
    var online: Bool?
    var balance: Double?
    /// 我和他的关系：self / friend / incoming / requested / none（名片页按钮按它变）
    var relation: String?
    /// 他发过几条朋友圈（名片上朋友圈那一行有没有）
    var momentCount: Int?
    /// 他的朋友圈可见范围：3d 最近三天 / 6m 最近半年 / all 全部。
    /// 只有「我加了他」的名片（/api/users/{id} 走 memberProfile）才带这个值 ——
    /// 名片上那句「朋友仅展示最近三天的朋友圈」用的就是它。
    var momentsRange: String?
    /// 好友申请里那句验证消息（「新的朋友」里显示）
    var requestMessage: String?
    /// 我给这个人设的备注名（设了以后列表/会话标题都显示它）
    var remark: String?
    /// 他的真实昵称（有备注时用它显示小字）
    var realNickname: String?
    /// 我给他打的标签
    var tags: [String]?
    /// 星标朋友
    var star: Bool?
    /// 我拉黑了他
    var block: Bool?
    /// 我不看他（她）的朋友圈
    var noMoments: Bool?
    /// 好友添加时间 / 来源（我加的 / 他加的我）
    var addedAt: String?
    var source: String?
    /// 我和他共同在几个群里
    var mutualGroups: Int?
    /// 群昵称（微信「设置群昵称」）：只有群成员列表里才带，没设就是空
    var alias: String?
    /// 等级（QQ 那套：活跃天换算出来的级别），0 = 还没开始
    var qqLevel: Int?
    /* 会员：有值就是会员（列表里挂徽章、名字上色用） */
    var memberTier: String?
    var memberShort: String?
    var memberColor: String?
    var memberColor2: String?

    var name: String {
        if let n = nickname, !n.isEmpty { return n }
        if let u = username, !u.isEmpty { return u }
        return "未知用户"
    }
    /// 群里显示的名字：设了群昵称就用群昵称（和微信一样）
    var groupName: String {
        if let a = alias, !a.isEmpty { return a }
        return name
    }
    var avatarPath: String { avatar ?? "" }
}

struct LastMessage: Decodable, Hashable {
    var id: String?
    var senderId: String?
    var senderName: String?
    var kind: String?
    var preview: String?
    var createdAt: String?
    /// 这条 @ 了我（会话列表那一行会带「[有人@我]」）
    var mentionMe: Bool?
}

struct Chat: Decodable, Identifiable, Hashable {
    var id: String
    var type: String?
    var title: String?
    var avatar: String?
    /// 好友的「状态」（微信那种：会话列表头像右下角挂一个 emoji）
    var moodIcon: String?
    var moodText: String?
    var unread: Int?
    var pinned: Bool?
    var botRank: Int?
    /// 单聊对方是哪个机器人账号：ai / housekeeper / qqnews / kefu（不是机器人就是空）
    /// —— 「星联世界」那一页（qqnews）要换成腾讯新闻那种排版，就靠这个认
    var bot: String?
    /// 「星言团队」那条系统通知会话（照微信的「微信团队」做：底下带自助工具 / 联系客服）
    var sysTeam: Bool?
    /// 这条会话对面是公众号的话，给的是那个号的 id（点进去直接开「公众号页面」）
    var oaId: String?
    /// 对面是「订阅号消息」这个汇总号（点进去开公众号列表）
    var oaDigest: Bool?
    /// 单聊对方的等级（QQ 那套）：会话列表昵称旁边挂图标用
    var qqLevel: Int?
    var memberCount: Int?
    /// 会话成员（单聊里用来找「对方是谁」，打语音/视频要用）
    var memberIds: [String]?
    var lastMessage: LastMessage?
    var updatedAt: String?
    /// 消息免打扰（群屏蔽）
    var muted: Bool?
    /// 这个会话是「左滑 → 标为未读」点过的（微信里这种只点一个小红点，
    /// 不给数字；进会话就消掉）。服务端算好给客户端。
    var flagged: Bool?
    /// 群主 id（群聊才有）
    var ownerId: String?
    /// 群公告（群聊才有）
    var announce: String?
    /// 群禁言：全员禁言 / 我有没有被单独禁言
    var muteAll: Bool?
    var meMuted: Bool?
    /* 会员（我们自己那套）：单聊看对方、群聊看群主，列表里挂徽章用 */
    var memberTier: String?
    var memberShort: String?
    var memberColor: String?
    var memberColor2: String?

    var name: String { (title?.isEmpty == false) ? title! : "会话" }
    var unreadCount: Int { unread ?? 0 }
}

/// 图片消息正文 → 图片地址。
/// 老消息存的是纯路径（/uploads/x.jpg）；这里同时兼容
/// {"url":"...","w":..,"h":..} 这种信封写法，以后换格式也不会把老图读坏。
func imageRefPath(_ content: String) -> String {
    let b = content
    guard b.hasPrefix("{"), let d = b.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let u = o["url"] as? String, !u.isEmpty else { return b }
    return u
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var chatId: String?
    var seq: Int?
    var senderId: String?
    var kind: String?
    var content: String?
    var createdAt: String?
    var recalled: Bool?
    var senderName: String?
    var senderAvatar: String?
    /// 通话记录专用的附加信息（服务端写系统消息时带上）
    var call: CallMeta?
    /// 这条消息 @ 了谁（群里才有：存的是被 @ 的 userId 列表）
    var mentions: [String]?
    /// 图片消息的原始像素宽高（发送端带上来的 / 服务端给老消息补的）：
    /// 聊天气泡第一帧就按真实比例把框占好，行高全程不变（骨架落位）
    var imgW: Int?
    var imgH: Int?

    var kindName: String { kind ?? "text" }
    var body: String { content ?? "" }
    var isRecalled: Bool { recalled ?? false }

    /// 图片消息里真正的图片地址。老消息存的是纯路径（/uploads/x.jpg）；
    /// 也兼容 {"url":"...","w":..,"h":..} 这种信封写法。
    var imagePath: String { imageRefPath(body) }

    /// 图片消息的原始像素尺寸（老消息可能没有 → nil）
    var imagePixelSize: CGSize? {
        if let w = imgW, let h = imgH, w > 1, h > 1 { return CGSize(width: CGFloat(w), height: CGFloat(h)) }
        let b = body
        if b.hasPrefix("{"), let d = b.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let w = (o["w"] as? Int) ?? Int((o["w"] as? Double) ?? 0)
            let h = (o["h"] as? Int) ?? Int((o["h"] as? Double) ?? 0)
            if w > 1, h > 1 { return CGSize(width: w, height: h) }
        }
        return nil
    }

    /// 这条消息有没有 @ 这个人
    func mentionsUser(_ userId: String) -> Bool {
        guard !userId.isEmpty, let ids = mentions else { return false }
        return ids.contains(userId)
    }

    /* ---------------- 拍一拍（双击头像）---------------- */
    /// 服务端写的那条「拍一拍」消息里带的客观信息：谁拍了谁、双方当时的显示名
    private var patInfo: [String: Any]? {
        guard kindName == "pat",
              let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }
    var patFrom: String { (patInfo?["from"] as? String) ?? "" }
    var patTo: String { (patInfo?["to"] as? String) ?? "" }
    var patFromName: String { (patInfo?["fn"] as? String) ?? "" }
    var patToName: String { (patInfo?["tn"] as? String) ?? "" }
    /// 被拍的人设的「拍一拍」后缀（微信：我 → 个人资料 → 拍一拍 → 朋友拍了拍我的＿＿）
    var patTail: String { (patInfo?["tt"] as? String) ?? "" }
    /// 这条「拍了拍」在**我这台手机**上该怎么念（微信的三种说法）
    func patText(myId: String) -> String {
        let fn = patFromName, tn = patToName
        /* 被拍的人设过后缀：微信会念成「拍了拍我的{后缀}」。
           没设就还是原来的「拍了拍了谁」——老消息（没有 tt 字段）自然走这一支。 */
        let tail = patTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTail = tail.isEmpty ? "" : ("的" + tail)      // 别人看他：「张三」拍了拍「李四」的X
        let meTail = tail.isEmpty ? "我" : ("我的" + tail)      // 我是被拍的：「张三」拍了拍我的X
        if !patFrom.isEmpty, patFrom == myId, !tn.isEmpty { return "我拍了拍“" + tn + "”" + targetTail }
        if !patTo.isEmpty, patTo == myId, !fn.isEmpty { return "“" + fn + "”拍了拍" + meTail }
        if !fn.isEmpty, !tn.isEmpty { return "“" + fn + "”拍了拍“" + tn + "”" + targetTail }
        return "拍了拍"
    }

    /// 这行系统消息是不是一条通话记录
    var isCallRecord: Bool {
        if call != nil { return true }
        let t = body
        return t.contains("通话") || t == "已取消" || t == "未接听" || t == "对方无应答"
            || t == "对方已拒绝" || t == "对方忙线中" || t == "对方不在线"
    }
    /// 视频通话（图标画摄像机）
    var isVideoCall: Bool { (call?.media ?? "").contains("video") || body.contains("视频") }
    /// 这条通话记录是谁打出去的（服务端写的；老记录没有，空字符串）
    var callFrom: String { call?.from ?? "" }
    /// 这条通话记录是不是「没接通」那种（微信里这几种是红字）：
    /// 正文里找关键词 + 服务端写的 call.state 一起看 ——
    /// 新记录正文可能只有「通话时长 00:00」而状态写在 call.state 里，
    /// 只看正文会漏，就会显示成普通黑字。
    var isBadCallRecord: Bool {
        guard isCallRecord else { return false }
        let t = body + " " + (call?.state ?? "")
        let words = ["未接听", "已拒绝", "已取消", "无应答", "不在线", "忙线", "未接通",
                     "无人接听", "cancel", "reject", "timeout", "missed", "busy", "offline"]
        return words.contains { t.contains($0) }
    }
    /// 通话记录显示成微信那样：「通话时长 00:12」（老记录的「通话结束 · 时长 0:15」也统一过来）
    var callText: String {
        var t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        for pre in ["视频通话结束", "通话结束"] where t.hasPrefix(pre) {
            if let r = t.range(of: "时长") { t = "通话时长" + String(t[r.upperBound...]) }
            break
        }
        if t.hasPrefix("视频通话时长") { t = "通话时长" + String(t.dropFirst("视频通话时长".count)) }
        if t.hasPrefix("通话时长") {
            let rest = t.dropFirst("通话时长".count).trimmingCharacters(in: .whitespaces)
            let p = rest.split(separator: ":")
            if p.count == 2, let mm = Int(p[0]), let ss = Int(p[1]) {
                t = String(format: "通话时长 %02d:%02d", mm, ss)
            }
        }
        return t
    }
}

/// 通话系统消息的附加信息：媒体类型、状态、时长
struct CallMeta: Codable, Hashable {
    var media: String?
    var state: String?
    var secs: Int?
    /// 谁打出去的（客户端靠它把这条记录摆到左边还是右边）
    var from: String?
    var to: String?
}

/* ============================================================ 附近的人 */

/// 附近名单里的一个人
struct NearbyPerson: Decodable, Identifiable, Hashable {
    var id: String
    var nickname: String?
    var avatar: String?
    var gender: String?
    var region: String?
    var bio: String?
    var moodText: String?
    var moments: Int?
    var online: Bool?
    var friend: Bool?
    /// 距离（公里，服务器算好的，一位小数）
    var km: Double?
    /// 几分钟前报的位置
    var minutes: Int?

    var name: String { (nickname?.isEmpty == false) ? nickname! : "附近的人" }
    var isFemale: Bool { (gender ?? "") == "female" }
    /// 距离文字：照参考图那种微信写法 —— 不到 1 公里「500米以内」，超过就「1.2公里以内」
    var distanceText: String {
        guard let km = km else { return "" }
        if km < 1 {
            let m = max(100, Int(ceil(km * 1000 / 100)) * 100)      // 往大取到 100 米
            return "\(m)米以内"
        }
        return String(format: "%.1f公里以内", km)
    }
    var timeText: String {
        guard let m = minutes else { return "" }
        if m <= 0 { return "刚刚" }
        if m < 60 { return "\(m) 分钟前" }
        return "\(m / 60) 小时前"
    }
}

private struct NearbyPayload: Decodable {
    var people: [NearbyPerson]
    /// 5 公里内没人时：20 公里内有几个（提示「扩大范围」用）
    var wider: Int?
    var maxKm: Double?
}
private struct NearbyHelloPayload: Decodable { var chatId: String?; var text: String? }

/// 摇一摇的结果：摇到人就是 matched，没人同时在摇就是 nil
struct ShakeResult: Decodable {
    var matched: NearbyPerson?
    /// 现在有几台设备在摇（微信也会提示「同时有 N 人在摇」）
    var shaking: Int?
}

/* ---------------- 直播专场 ---------------- */
private struct LivePayload: Decodable { var rooms: [LiveRoom] }
private struct LiveJoinPayload: Decodable { var watching: Int? }
private struct LiveLikePayload: Decodable { var likes: Int? }
private struct GamesPayload: Decodable { var items: [MiniGame] }

/// 小游戏：玩法写在客户端，服务器只发列表（后台能改 data/games.json）
struct MiniGame: Decodable, Identifiable, Hashable {
    var id: String
    var label: String?
    var desc: String?
    var icon: String?
    var kind: String?
    var enabled: Bool?
    /// 网页小游戏的地址（服务器 /games/xxx/index.html）——
    /// 这一版 4 款游戏都是网页的，App 用内置浏览器全屏打开
    var url: String?
}

/* ---------------- 视频号 ---------------- */
/// 视频号的后台可调样式（后台「视频号」面板里改）
struct FeedStyle: Decodable, Hashable {
    var avatar: Double?
    var nameSize: Double?
    var descSize: Double?
    var musicSize: Double?
    var railIcon: Double?
    var railGap: Double?
    var padBottom: Double?
}

/// 视频号的开关
struct FeedFlags: Decodable, Hashable {
    var allowPublish: Bool?
    var allowTrim: Bool?
    var showRail: Bool?
    var autoPlay: Bool?
}

private struct FeedPayload: Decodable {
    var items: [FeedItem]
    var style: FeedStyle?
    var flags: FeedFlags?
}
private struct FeedLikePayload: Decodable { var liked: Bool?; var likes: Int? }
private struct FeedCommentPayload: Decodable { var comments: Int? }
private struct FeedCommentsPayload: Decodable { var comments: [FeedCommentItem]?; var count: Int? }
private struct FeedSeriesPayload: Decodable { var series: String?; var name: String?; var items: [FeedItem]? }
private struct FeedFavoritePayload: Decodable { var favorited: Bool?; var favorites: Int? }
/// 视频号一条评论
struct FeedCommentItem: Decodable, Hashable, Identifiable {
    var id: String
    var name: String?
    var avatar: String?
    var text: String?
    var at: String?
}
private struct FeedPublishPayload: Decodable { var id: String?; var video: String? }
private struct FeedTrimPayload: Decodable { var url: String?; var width: Int?; var height: Int? }

struct MomentLike: Codable, Hashable {
    var userId: String?
    var nickname: String?
    var at: String?
}

struct MomentComment: Codable, Hashable {
    var id: String?
    var userId: String?
    var nickname: String?
    var replyToName: String?
    var content: String?
    var at: String?
}

/// ⚠ B160+：改成 Codable —— 朋友圈要做**本机缓存**（照微信：进页面先铺缓存再刷、
/// 断网也能看上次那几屏），落盘要能编码。
struct Moment: Codable, Identifiable, Hashable {
    var id: String
    var authorId: String?
    var author: User?
    var content: String?
    var images: [String]?
    /// 每张图的宽高（发表时一起带上来的）：列表一上来就按真实比例把框画好，
    /// 不会再「先 4:3、加载完跳一下」（尺寸跳变）
    var imageSizes: [String: [Int]]?
    /// 朋友圈视频（和微信一样：一条动态要么九张图、要么一条视频）
    var video: String?
    var videoCover: String?
    var videoSeconds: Int?
    var videoW: Int?
    var videoH: Int?
    /// 发表时选的「所在位置」（微信发表页那一行，不填就是空）
    var location: String?
    /// 我置顶的那条动态（置顶的永远排在朋友圈最上面）
    var pinned: Bool?
    var createdAt: String?
    var likes: [MomentLike]?
    var likedByMe: Bool?
    var comments: [MomentComment]?
    var mine: Bool?
}

private struct ChatsPayload: Decodable { var chats: [Chat] }
private struct ChatPayload: Decodable { var chat: Chat? }
private struct ChatMembersPayload: Decodable {
    var members: [User]?
    var ownerId: String?
    var createdAt: String?
    var avatar: String?
}
private struct PinPayload: Decodable { var pinned: Bool?; var forced: Bool? }
private struct ChatInfoPayload: Decodable { var name: String?; var announce: String? }
private struct MutePayload: Decodable { var muted: Bool? }
private struct GroupActionPayload: Decodable { var memberCount: Int?; var left: Bool?; var dismissed: Bool? }
private struct SearchPayload: Decodable { var messages: [FoundMessage] }
private struct BankCardsPayload: Decodable { var cards: [BankCard]? }
private struct SendPayload: Decodable { var sent: Bool?; var id: String? }

/// 银行卡（卡号只回后四位）
    struct BankCard: Decodable, Identifiable, Hashable {
        /* 微信银行卡那页要的：卡类型、免密支付、限额、脱敏手机号 */
        var type: String?
        var noPin: Bool?
        var single: Double?
        var day: Double?
        var phoneMask: String?
    var id: String
    var bank: String?
    var holder: String?
    var tail: String?

    var title: String { (bank ?? "银行卡") + " 尾号" + (tail ?? "****") }
}

/// 「查找聊天记录」搜出来的那一条
struct FoundMessage: Decodable, Identifiable, Hashable {
    var id: String
    var seq: Int?
    var kind: String?
    var content: String?
    var createdAt: String?
    var senderId: String?
    var senderName: String?
}
private struct UsersPayload: Decodable { var users: [User] }
private struct MessagesPayload: Decodable {
    var chat: Chat?
    var messages: [Message]
    var hasMore: Bool?
}
private struct MessagePayload: Decodable { var message: Message? }
private struct CreditScorePayload: Decodable { var score: CreditScore }

/// 安全分（服务端按真实记录算：资料 / 登录设备 / 转账 / 记账 / 安全事件）
struct CreditScore: Decodable, Hashable {
    struct Item: Decodable, Hashable {
        var label: String
        var ok: Bool
        var tip: String?
    }
    struct Dim: Decodable, Hashable, Identifiable {
        var key: String
        var label: String
        var score: Int
        var max: Int
        var items: [Item]?
        var id: String { key }
    }
    struct Stats: Decodable, Hashable {
        var deviceCount: Int?
        var sentCount: Int?
        var successCount: Int?
        var expiredCount: Int?
        var ledgerCount: Int?
    }
    var score: Int
    var level: String
    var min: Int
    var max: Int
    var percent: Int
    var updatedAt: String?
    var dims: [Dim]
    var tips: [String]
    var stats: Stats?
}
private struct ContactsPayload: Decodable {
    var friends: [User]
    var incoming: [User]?
    var outgoing: [User]?
    /// 刚通过、还留在「新的朋友」里显示「已添加」的人
    var added: [User]?
}
private struct MePayload: Decodable { var user: User? }
private struct UserPayload: Decodable { var user: User? }
private struct LoginPayload: Decodable { var user: User? }
private struct SessionPayload: Decodable { var authenticated: Bool?; var user: User? }
private struct PhoneCodePayload: Decodable { var sent: Bool?; var devCode: String?; var nickname: String? }
private struct CaptchaPayload: Decodable { var id: String?; var svg: String? }
private struct PairStartPayload: Decodable { var code: String?; var expiresIn: Int? }
private struct PairStatusPayload: Decodable { var status: String?; var user: User?; var token: String? }
private struct MomentsPayload: Decodable {
    var moments: [Moment]
    var hasMore: Bool?
    var unread: Int?
    var total: Int?
    /// 看别人的朋友圈时：这个人设的可见范围（all / 3d / 6m）——
    /// App 用它显示「朋友仅展示最近三天的朋友圈」那句提示（微信有这一句）
    var range: String?
}
private struct BrandingPayload: Decodable { var branding: BrandInfo? }
private struct BadgesPayload: Decodable { var badges: [String: String]? }
private struct EndpointsPayload: Decodable { var endpoints: [String]? }

/* ---------------- 版本更新 + 弹窗公告（服务端 /api/version 下发） ---------------- */
struct AppUpdateInfo: Decodable, Equatable {
    var version: String?
    var notes: String?
    var force: Bool?
    var url: String?
    var downloadPage: String?
}
struct NoticeInfo: Decodable, Equatable {
    var title: String?
    var content: String?
    var kind: String?          // popup=每次打开 / daily=每天一次 / once=只弹一次
    var startAt: String?
    var endAt: String?
    var minVersion: String?
    var maxVersion: String?
}
private struct VersionPayload: Decodable {
    var app: AppUpdateInfo?
    var notice: NoticeInfo?
}

struct BrandInfo: Decodable, Hashable {
    var appName: String?
    var logo: String?
    /// 服务器上配的「默认聊天背景」（用户自己没设时用它）
    var chatBackground: String?
    var fontScale: Double?
    var accentColor: String?
    /// 通话用的 ICE 服务器（后台「语音通话」里配的，跨网络需要 TURN 时填这儿）
    var iceServers: String?
    /// 登录页外观（后台「🎨 登录页」里配的）
    var login: LoginBrand?
    /// 服务器有没有开「登录滑动验证」（安全验证那一块显不显示由它决定）
    var sliderLogin: Bool?
    /// 后台配的启动页图片（没有就用 App 包里那张 splash.png 兜底）
    var splash: String?
}

struct LoginBrand: Decodable, Hashable {
    var accent: String?
    var accent2: String?
    var disabledAccent: String?
    var disabledGray: String?
    var bg: String?
    var card: String?
    var text: String?
    var sub: String?
    /// 深色模式下登录页的文字颜色（后台「深色·文字」）
    var darkText: String?
    var bgImage: String?
    var appName: String?
    var subTitle: String?
    var logo: String?
    var terms: String?
    var privacy: String?
}



struct PlusItem: Decodable, Identifiable, Hashable {
    var id: String?
    var label: String?
    var icon: String?
    var action: String?
    var enabled: Bool?
}

struct Gift: Decodable, Identifiable, Hashable {
    var id: String
    var name: String?
    var icon: String?
    var price: Double?
    var category: String?
}

struct StickerPack: Decodable, Hashable {
    var id: String?
    var name: String?
    var icon: String?
    var stickers: [String]?
}

struct StatusItem: Decodable, Hashable {
    var id: String?
    var icon: String?
    var label: String?
    var color: String?
    var color2: String?
}

struct StatusCategory: Decodable, Hashable {
    var id: String?
    var name: String?
    /// 分类自己的底色（后台「状态」页配的），格子没单独配色就用它
    var color: String?
    var enabled: Bool?
    var items: [StatusItem]?
}

/* ---------------- 我的状态（微信那套：24 小时过期 / 谁看过 / 结束状态） ---------------- */

/// 看过我状态的人
struct StatusViewer: Decodable, Hashable {
    var userId: String?
    var name: String?
    var avatar: String?
    var at: String?
}

/// 我的状态详情：还在不在、是什么、还剩几个小时、谁看过
struct MyStatus: Decodable {
    var alive: Bool?
    var moodText: String?
    var moodIcon: String?
    var moodColor: String?
    var moodColor2: String?
    var moodLabel: String?
    var moodCaption: String?
    var hoursLeft: Int?
    var createdAt: String?
    var viewerCount: Int?
    var views: [StatusViewer]?

    var isAlive: Bool { alive ?? false }
    /// 大卡片上那一行：优先显示「说点什么」，没有就显示状态名
    var shownText: String {
        let cap = (moodCaption ?? "").trimmingCharacters(in: .whitespaces)
        if !cap.isEmpty { return cap }
        return (moodLabel ?? moodText ?? "")
    }
}

/// 状态配色：后台配了就用，没配就用分类色，第二个色自动调亮一点做渐变
enum MoodColor {
    /// 这个颜色偏暗吗？顶部铺状态色时，用它决定名字/文字用白还是黑（微信也是这么处理的）
    static func isDark(_ hex: String) -> Bool {
        let c = clean(hex)
        guard !c.isEmpty, let v = UInt32(c.dropFirst(), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return l < 0.45
    }

    /// "#6f8a38" / "6f8a38" → "#6F8A38"；拿不准就给空串
    static func clean(_ raw: String?) -> String {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return "" }
        return "#" + s.uppercased()
    }

    /// 同色系调亮 / 调暗一点（给渐变的第二格用）
    static func shift(_ hex: String, to light: Bool) -> String {
        let c = clean(hex)
        guard !c.isEmpty, let v = UInt32(c.dropFirst(), radix: 16) else { return "" }
        var r = Double((v >> 16) & 0xFF)
        var g = Double((v >> 8) & 0xFF)
        var b = Double(v & 0xFF)
        let k = light ? 0.28 : -0.18
        let mix = light ? 255.0 : 0.0
        r += (mix - r) * k
        g += (mix - g) * k
        b += (mix - b) * k
        let out = (UInt32(max(0, min(255, r))) << 16)
            | (UInt32(max(0, min(255, g))) << 8)
            | UInt32(max(0, min(255, b)))
        return String(format: "#%06X", out)
    }
}

/// 发现页的一行（后台可以自由增删改）
struct DiscoverItem: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var icon: String?
    var svg: String?
    var color: String?
    var action: String?
    var group: Int?
    var enabled: Bool?
}

private struct StickersPayload: Decodable { var packs: [StickerPack]? }

/* ------------------------------------------------------------ 新闻（星联世界页）
   服务端把国内的源（腾讯 / 头条 / 新浪 / 微博 / 百度）统一成这一份结构。
   有图的（腾讯、头条、新浪）走大图 / 右缩略图的版式；没图的（微博、百度热搜）
   走带名次的榜单版式 —— 两种都是腾讯新闻 App 里的样子。 */
struct NewsChannel: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var desc: String?
}

struct NewsItem: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String?
    var source: String?
    var url: String?
    var img: String?
    /// 热度值（微博 / 百度 / 头条有，腾讯和新浪没有）
    var hot: Double?
    /// 榜上的名次（1 就是第一条）
    var rank: Int?
    /// 「热 / 新 / 沸」那种小标
    var tag: String?
    /// 毫秒时间戳（有的源不给，就是 0）
    var time: Double?

    var link: String { url ?? "" }
    var cover: String { img ?? "" }
    var src: String { (source?.isEmpty == false) ? source! : "星联世界" }
    var tagText: String { tag ?? "" }
    var hotValue: Double { hot ?? 0 }
    var order: Int { rank ?? 0 }
    var at: Double { time ?? 0 }
}

struct NewsFeed: Decodable {
    var list: [NewsItem]?
    var source: String?
    var channels: [NewsChannel]?
    var updatedAt: Double?
    /// 这个源一共多少条（「换一批」用它判断有没有到底）
    var total: Int?

    var items: [NewsItem] { list ?? [] }
    var tabs: [NewsChannel] { channels ?? [] }
}
/// 「我的表情」（微信「我 → 表情」那套）：我添加的表情包 + 我自己添加的单个表情 + 最近使用
struct StickerMine: Decodable, Hashable {
    var packs: [StickerPack]?
    var singles: [String]?
    var recent: [String]?
    var packList: [StickerPack] { packs ?? [] }
    var singleList: [String] { singles ?? [] }
    var recentList: [String] { recent ?? [] }
}
private struct StickerShopPayload: Decodable {
    var packs: [StickerPack]?
    var mine: StickerMine?
    var thirdParty: ThirdParty?
    struct ThirdParty: Decodable { var provider: String?; var enabled: Bool?; var limit: Int? }
}
private struct StatusesPayload: Decodable { var categories: [StatusCategory]? }
private struct DiscoverPayload: Decodable { var items: [DiscoverItem] }

/* ---------------- 服务页（我 → 服务，后台「服务页」模块下发） ---------------- */

/// 绿卡的一半：收付款 / 钱包
struct ServiceHalf: Decodable, Hashable {
    var label: String
    var sub: String?
    var icon: String?
    var svg: String?
    var action: String?
}

/// 绿卡本身（底色 + 左右两半）
struct ServiceCard: Decodable, Hashable {
    var enabled: Bool?
    var bg: String?
    var left: ServiceHalf?
    var right: ServiceHalf?
}

/// 一个分类：标题 + 里面的格子（格子复用发现页那套字段）
/// 版块只给「上 / 下」两个值（块与块之间的空隙；nil = 用默认：上 0 / 下 8）
struct ServiceGroupStyle: Decodable, Hashable {
    var gapTop: Double?
    var gapBottom: Double?
}

struct ServiceGroup: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var enabled: Bool?
    var style: ServiceGroupStyle?
    var items: [DiscoverItem]?
}

/// 服务页的样式：绿卡背景图 / 图标大小 / 各处字体的大小和颜色（后台「服务页 → 样式」里配）
struct ServiceStyle: Decodable, Hashable {
    var cardImage: String?
    var cardTextColor: String?
    var cardTextSize: Double?
    var cardSubSize: Double?
    var curSize: Double?
    var cardSubOpacity: Double?
    var iconSize: Double?
    var gridTitleSize: Double?
    var gridTitleColor: String?
    var gridTextSize: Double?
    var gridTextColor: String?
    var maskAmount: Bool?       // 绿卡右边的零钱打成 ¥****
    var maskReveal: Bool?       // 点一下能不能看

    /// 默认值 = 照参考图量出来的那套
    var icon: CGFloat { CGFloat(iconSize ?? 28) }
    var cardNameSize: CGFloat { CGFloat(cardTextSize ?? 18) }
    var cardSubSizeV: CGFloat { CGFloat(cardSubSize ?? 12) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }
    var cardSubOpacityV: Double { cardSubOpacity ?? 0.5 }
    var titleSize: CGFloat { CGFloat(gridTitleSize ?? 14) }
    var textSize: CGFloat { CGFloat(gridTextSize ?? 13) }
    var cardText: Color { Color(hexString: cardTextColor ?? "#FFFFFF", fallback: 0xFFFFFF) }
    /// 标题颜色：还是默认值就跟主题走（浅色 #7A7A7A / 深色 #8A8A8A）
    var titleColor: Color {
        let v = (gridTitleColor ?? "#7A7A7A").uppercased()
        if v == "#7A7A7A" { return Color.dyn(0x7A7A7A, 0x8A8A8A) }
        return Color(hexString: v, fallback: 0x7A7A7A)
    }
    /// 格子文字颜色：留空就跟主题
    var gridText: Color {
        if let c = gridTextColor, !c.isEmpty { return Color(hexString: c, fallback: 0x191919) }
        return C.label
    }
    /// 尺寸变了，卡片和格子跟着长，不把字挤出去
    var cardHeight: CGFloat { 144 + (icon - 28) + (cardNameSize - 18) + (cardSubSizeV - 12) }
    var cellHeight: CGFloat { 92 + (icon - 28) + (textSize - 13) }
    var titleHeight: CGFloat { 48 + (titleSize - 14) }
}

/// 整页服务页的配置
/// 收付款码（付款码 / 收款码都用这一个）
struct PayCodeInfo: Decodable {
    var code: String?
    var grouped: String?          // 每 4 位空一格（银行卡那种排版）
    var url: String?              // 二维码里装的内容
    var expiresAt: Double?
    var seconds: Int?
    var rows: [String]?           // 二维码点阵
    var size: Int?
    var amount: Double?           // 收款码「设置金额」
    var user: User?
}

/// 扫到的码是谁的、要收多少钱
struct PayScanInfo: Decodable, Identifiable {
    var kind: String              // pay = 付款码（我付给码的主人）/ receive = 收款码
    var amount: Double?
    var user: User?
    var id: String { "\(kind)-\(user?.id ?? "")-\(amount ?? 0)" }
}

/// 付款结果
struct PayCollectResult: Decodable {
    var balance: Double?
    var amount: Double?
    var payee: User?
}

/// 服务页底部那块（账单卡 + 右上角「⋯」菜单）的文案：后台「服务页 → 底部」里配，
/// 留空就用 App 里的默认值（以前这些字全都是写死在 App 里的）
struct ServiceBottom: Decodable, Hashable {
    var billTitle: String? = nil
    var billAll: String? = nil
    var billRecharge: String? = nil
    var billEmpty: String? = nil
    var moreRefresh: String? = nil
    var moreRecharge: String? = nil
    var moreCancel: String? = nil
    /// 「XX 还没接后端」这句提示，{label} 会替换成格子的名字
    var soonTip: String? = nil
}

struct ServiceConfig: Decodable, Hashable {
    var title: String?
    var card: ServiceCard?
    var bottom: ServiceBottom?
    var style: ServiceStyle?
    var groups: [ServiceGroup]?
}

/* ---------------- 钱包页（我 → 服务 → 钱包，后台「钱包页」模块下发） ---------------- */

/// 钱包页的一行
struct WalletItem: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var value: String?
    var valueKind: String?      // "balance" = 这一行的数值现算这个人的零钱
    var note: String?           // 小字，比如「收益率 1.01%」
    var icon: String?
    var svg: String?
    var color: String?
    var action: String?
    var mask: Bool?             // 这一行的金额要不要打星号
    var enabled: Bool?
}

/// 钱包页的一张白卡
struct WalletGroup: Decodable, Identifiable, Hashable {
    var id: String
    var enabled: Bool?
    var items: [WalletItem]?
}

/// 右上角那个按钮（默认是「账单」）
struct WalletRight: Decodable, Hashable {
    var label: String?
    var action: String?
}

/// 底部的蓝色链接（身份信息 / 支付设置）
struct WalletFoot: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var action: String?
    var enabled: Bool?
}

/// 钱包页的样式（行高 / 图标 / 字体 / 颜色）
struct WalletStyle: Decodable, Hashable {
    var rowHeight: Double?
    var iconSize: Double?
    var iconLeft: Double?
    var textLeft: Double?
    var rightInset: Double?
    var labelSize: Double?
    var valueSize: Double?
    var curSize: Double?
    var noteSize: Double?
    var footerSize: Double?
    var groupGap: Double?
    var dividerInset: Double?
    var labelColor: String?
    var valueColor: String?
    var noteColor: String?
    var footerColor: String?
    var maskAmount: Bool?       // 金额打成 ¥****
    var maskReveal: Bool?       // 点一下能不能看

    var row: CGFloat { CGFloat(rowHeight ?? 56.3) }
    var icon: CGFloat { CGFloat(iconSize ?? 20) }
    var iconX: CGFloat { CGFloat(iconLeft ?? 18) }
    var textX: CGFloat { CGFloat(textLeft ?? 56.7) }
    var rightPad: CGFloat { CGFloat(rightInset ?? 18) }
    var labelFont: CGFloat { CGFloat(labelSize ?? 17) }
    var valueFont: CGFloat { CGFloat(valueSize ?? 16) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }
    var noteFont: CGFloat { CGFloat(noteSize ?? 13) }
    var footFont: CGFloat { CGFloat(footerSize ?? 13) }
    var gap: CGFloat { CGFloat(groupGap ?? 12) }
    var divider: CGFloat { CGFloat(dividerInset ?? 56) }
    /// 行标题：留空就跟主题
    var labelColorV: Color {
        if let c = labelColor, !c.isEmpty { return Color(hexString: c, fallback: 0x191919) }
        return C.label
    }
    var valueColorV: Color {
        let v = (valueColor ?? "#1A1A1A").uppercased()
        if v == "#1A1A1A" { return C.label }
        return Color(hexString: v, fallback: 0x1A1A1A)
    }
    var noteColorV: Color { Color(hexString: noteColor ?? "#FA9D3B", fallback: 0xFA9D3B) }
    var footerColorV: Color { Color(hexString: footerColor ?? "#576B95", fallback: 0x576B95) }
    /// 金额打星号（默认开）
    var mask: Bool { maskAmount ?? true }
    var canReveal: Bool { maskReveal ?? true }
}

/// 整页钱包页的配置
struct WalletConfig: Decodable, Hashable {
    var title: String?
    var right: WalletRight?
    var groups: [WalletGroup]?
    var footer: [WalletFoot]?
    var style: WalletStyle?
    var balance: Double?
    /// 没实名：金额被服务端打成 ¥****，钱的动作也全拦着（和微信一样）
    var locked: Bool?
    var needRealName: Bool?
    var isLocked: Bool { (locked ?? false) || (needRealName ?? false) }
}

/* ---------------- 账单（钱包页右上角「账单」进来，数据来自 /api/bills） ---------------- */

/// 一条账单（就是一笔转账，带对方是谁）
struct BillRecord: Decodable, Identifiable, Hashable {
    var id: String
    var chatId: String?
    var amount: Double
    var note: String?
    var method: String?
    var status: String?
    var createdAt: String?
    var expiresAt: Double?
    var receivedAt: String?
    var refundedAt: String?
    var direction: String?          // out = 我转出去 / in = 别人转给我
    var peerId: String?
    var peerName: String?
    var peerAvatar: String?

    var mine: Bool { direction != "in" }
    var peer: String { (peerName?.isEmpty == false) ? peerName! : "好友" }
    var stateText: String {
        let st = status ?? "pending"
        if mine {
            if st == "received" { return "对方已收款" }
            if st == "refunded" { return "已退回" }
            return "待对方收款"
        }
        if st == "received" { return "已收款" }
        if st == "refunded" { return "已退回" }
        return "待收款"
    }
}

/// 账单汇总（in 是关键字，映射成 inSum）
struct BillSummary: Decodable, Hashable {
    var out: Double
    var inSum: Double
    var pendingOut: Int
    var pendingIn: Int
    var count: Int

    enum CodingKeys: String, CodingKey {
        case out
        case inSum = "in"
        case pendingOut, pendingIn, count
    }
}

struct BillsPayload: Decodable, Hashable {
    var bills: [BillRecord]
    var months: [String]?
    var summary: BillSummary?
    var month: String?
    var style: BillsPageStyle?
    var faq: [BalanceFaq]?
}

/// 账单页外观（后台「账单页」里调）
struct BillsPageStyle: Decodable, Hashable {
    var iconSize: Double?
    var titleSize: Double?
    var timeSize: Double?
    var amountSize: Double?
    var curSize: Double?
    var amountWeight: Double?
    var showCur: Bool?
    var monthSize: Double?
    var sumSize: Double?
    var rowHeight: Double?

    var icon: CGFloat { CGFloat(iconSize ?? 48) }
    var titleFont: CGFloat { CGFloat(titleSize ?? 17) }
    var timeFont: CGFloat { CGFloat(timeSize ?? 13) }
    var amountFont: CGFloat { CGFloat(amountSize ?? 16) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }
    /// 金额字重：300 细 / 400 常规 / 500 中 / 600 粗（账单页默认 400，比钱包页细）
    var amountWeightV: Font.Weight {
        switch Int(amountWeight ?? 400) {
        case ..<350: return .light
        case 350..<450: return .regular
        case 450..<550: return .medium
        default: return .semibold
        }
    }
    /// 每行金额要不要带 ¥（默认不带，参考图里只显示 +/− 和数字）
    var showCurV: Bool { showCur ?? false }
    var monthFont: CGFloat { CGFloat(monthSize ?? 15) }
    var sumFont: CGFloat { CGFloat(sumSize ?? 13) }
    var row: CGFloat { CGFloat(rowHeight ?? 80) }
}

/* ---------------- 零钱页（钱包页点「零钱」进来，后台「零钱页」模块下发） ---------------- */

struct BalanceButton: Decodable, Hashable {
    var label: String?
    var action: String?
}

struct BalanceLink: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var action: String?
    var enabled: Bool?
}

struct BalanceFaq: Decodable, Hashable {
    var q: String
    var a: String
}

struct BalanceStyle: Decodable, Hashable {
    var bg: String?
    var circleSize: Double?
    var circleColor: String?
    var yenSize: Double?
    var yenColor: String?
    var titleSize: Double?
    var amountSize: Double?
    var curSize: Double?
    var noteSize: Double?
    var noteColor: String?
    var padTop: Double?
    var gapTitle: Double?
    var gapAmount: Double?
    var gapNote: Double?
    var btnWidth: Double?
    var btnHeight: Double?
    var btnRadius: Double?
    var rechargeBg: String?
    var rechargeInk: String?
    var withdrawBg: String?
    var withdrawInk: String?
    var linkSize: Double?
    var linkColor: String?
    var footerSize: Double?
    var footerColor: String?

    var circle: CGFloat { CGFloat(circleSize ?? 64) }
    var yenFont: CGFloat { CGFloat(yenSize ?? 24) }
    var titleFont: CGFloat { CGFloat(titleSize ?? 18) }
    var amountFont: CGFloat { CGFloat(amountSize ?? 64) }
    var curFont: CGFloat { CGFloat(curSize ?? 28) }
    var noteFont: CGFloat { CGFloat(noteSize ?? 16) }
    var topPad: CGFloat { CGFloat(padTop ?? 60) }
    var gapTitleV: CGFloat { CGFloat(gapTitle ?? 24) }
    var gapAmountV: CGFloat { CGFloat(gapAmount ?? 16) }
    var gapNoteV: CGFloat { CGFloat(gapNote ?? 20) }
    var btnW: CGFloat { CGFloat(btnWidth ?? 183.7) }
    var btnH: CGFloat { CGFloat(btnHeight ?? 47.7) }
    var btnR: CGFloat { CGFloat(btnRadius ?? 8) }
    var linkFont: CGFloat { CGFloat(linkSize ?? 13) }
    var footFont: CGFloat { CGFloat(footerSize ?? 12) }
    /* 后台配的颜色当浅色用，深色模式自动给对应的深色（后台也能写 "#浅色|#深色" 自己定两套）。
       以前这些是写死的单色 —— 深色模式下整页还是白的，就是这儿。 */
    var pageBg: Color { colorDyn(bg, light: 0xFFFFFF, dark: 0x0B0B0D) }
    var circleColorV: Color { colorDyn(circleColor, light: 0xFFD100, dark: 0xFFD100) }
    var yenColorV: Color { colorDyn(yenColor, light: 0xFFFFFF, dark: 0xFFFFFF) }
    var noteColorV: Color { colorDyn(noteColor, light: 0xEB9400, dark: 0xEB9400) }
    var rechargeBgV: Color { colorDyn(rechargeBg, light: 0x07C160, dark: 0x07C160) }
    var rechargeInkV: Color { colorDyn(rechargeInk, light: 0xFFFFFF, dark: 0xFFFFFF) }
    var withdrawBgV: Color { colorDyn(withdrawBg, light: 0xF2F2F2, dark: 0x2C2C2E) }
    var withdrawInkV: Color { colorDyn(withdrawInk, light: 0x313131, dark: 0xEDEDED) }
    var linkColorV: Color { colorDyn(linkColor, light: 0x576B95, dark: 0x7D90A9) }
    var footerColorV: Color { colorDyn(footerColor, light: 0xB3B3B3, dark: 0x8E8E93) }
}

struct BalancePageConfig: Decodable, Hashable {
    var navTitle: String?
    var title: String?
    var note: String?
    var recharge: BalanceButton?
    var withdraw: BalanceButton?
    var links: [BalanceLink]?
    var footer: String?
    var faq: [BalanceFaq]?
    var style: BalanceStyle?
    var balance: Double?
    var frozen: Double?
    /// 没实名：金额被服务端藏起来了（显示 ¥**** + 去实名认证），钱的动作也全拦着
    var locked: Bool?
    var needRealName: Bool?
    var isLocked: Bool { (locked ?? false) || (needRealName ?? false) }
}

private struct PlusPayload: Decodable { var items: [PlusItem]? }
private struct GiftsPayload: Decodable { var gifts: [Gift]? }
private struct UploadPayload: Decodable {
    var url: String?
    var name: String?
    var bytes: Int?
    var image: Bool?
}

/* ============================================================ 网络 */

enum APIError: LocalizedError {
    case message(String)
    /// 服务端判定这次登录有风险，要求补一次滑动验证（微信那种「需要时才弹」）
    case needSlider
    /// 没实名却动了钱（转账/红包/收付款/零钱）—— 服务端要求先实名（和微信一样）
    case needRealName

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .needSlider: return "请完成安全验证"
        case .needRealName: return "根据国家规定，请先完成实名认证"
        }
    }
}

/// 局域网服务器用的是自签名证书，这里直接放行
final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// 上传进度代理：URLSession 每传一段就回调一次，换算成 0…1 的百分比。
/// 挂在单个上传任务上（session.upload(for:fromFile:delegate:)），不影响别的请求。
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    private var last = -1.0

    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let p = min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        /* 每 2% 报一次就够：报太密会把主线程刷爆（大视频一秒能回调几十次） */
        if p >= 1 || p - last >= 0.02 {
            last = p
            onProgress(p)
        }
    }
}

final class API {
    static let shared = API()

    let session: URLSession
    private let trustDelegate = TrustAllDelegate()

    private(set) var token: String = ""
    /// 主入口：**新公网 IP 直连**（2026-10-07 换的）。
    /// 旧的 206.187.208.79 已经被移动那条线路整个 RST 掉（连上就被掐），
    /// 换成这个 IP 之后直连速度不变、也绕开了那段拦截。
    /// 证书是 TrustAllDelegate 无条件接受的，所以用 IP 访问不受"证书上是域名"的影响。
    /// 主入口：**新公网 IP 直连**（2026-10-07 换的 103.233.254.147）。
    /// 这里刻意**不写域名**：域名要等 DNS 缓存过期（最多 30 分钟）才全量生效，
    /// 写 IP 就是"立刻能用"，不受任何 DNS 缓存影响。
    /// 备用入口里再放域名 —— 域名解析全部跟上之后，它就是更灵活的那个。
    /// 主入口：**国内新服务器直连**（2026-10-08 从香港 103.233.254.147 搬过来的）。
    /// 为什么换：香港那台的公网 IP 被移动整条线路 RST，移动用户根本连不上；
    /// 这台的 IP 在国内、不被拦，实测 https://43.242.194.89:5443 从外网 200、0.12 秒；
    /// 香港那台降级成备用入口，官方服务还活着，只是移动连不上。
    private(set) var server: String = "43.242.194.89"
    /// 备用入口（服务器 /api/endpoints 下发的；本地缓存着，主入口连不上时按顺序切）。
    private(set) var backups: [String] = API.builtinBackups

    /// 内置的备用入口（**写死在 App 里**，本地缓存冲不掉它）。
    static let builtinBackups: [String] = [
        "43.242.194.89:5443",
        "43.242.194.89:8443",
        "u.598218.xyz"
    ]
    /// 上一次自动换线路的时间：30 秒内只许切一次，免得来回横跳
    private var lastRotate = Date.distantPast

    /// 上一次请求是不是「连不上服务器」。
    /// 离线时界面**照常显示**（用已经拿到的数据），只是不再有新的；
    /// 这个标记就是用来决定要不要在顶上挂那条「网络不可用」的提示。
    private(set) var offline = false

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: cfg, delegate: trustDelegate, delegateQueue: nil)

        /* 本机存的服务器地址通常优先（尊重用户手动填的），
           但**下面这几个是"我们自己历史上用过、现在已知有问题的"**，
           一律丢掉、换成本包内置的那套 —— 否则装了新包也还在连那个连不上的地址：
             · 192.168.2.7 / :5443 —— 早年局域网那台电脑
             · 206.187.208.79 —— 被移动整条线路 RST 掉的旧公网 IP
             · aa.x8iu.com —— 域名本身没问题，但老设备的 DNS 缓存可能还指着旧 IP；
               交给"主入口 + 备用 IP"这套（连不上会自动切），比死守域名稳
           用户手动填过**别的**地址（比如自己的内网 IP）就不动。 */
        let legacyServers: Set<String> = [
            /* ⚠ 2026-10-09 根因确认：iOS 26 的 App 在 ClientHello 里**只带后量子密钥**
               （X25519MLKEM768），而老服务器（香港、以及国内这台原来的 nginx）
               用的 OpenSSL 3.0.2 不认这个算法，直接 handshake failure（alert 40）。
               Safari 会多带一个经典算法，所以浏览器一直没事、App 一直挂。
               国内这台已经换成 **Node 24 / OpenSSL 3.5** 做 TLS 前端（443/5443/8443），
               后量子握手实测已通。所以：**所有老地址一律作废**，强制回到国内这台。 */
            "192.168.2.7:5443", "192.168.2.7", "206.187.208.79",
            "aa.x8iu.com", "aa.x8iu.com:5443",
            "103.233.254.147", "103.233.254.147:5443",
            "43.242.194.89:5443"
        ]
        if let saved = UserDefaults.standard.string(forKey: "chris.server"),
           !saved.isEmpty,
           !legacyServers.contains(API.normalizeServer(saved)) {
            server = API.normalizeServer(saved)
        } else {
            UserDefaults.standard.set(server, forKey: "chris.server")
        }
        if let list = UserDefaults.standard.array(forKey: "chris.backups") as? [String] {
            let cached = list.filter { !$0.isEmpty }
            /* ⚠ 内置的那条（Cloudflare 隧道）要永远留在列表最前面 ——
               以前这里直接覆盖，本地缓存一份空列表就把内置的冲掉了。 */
            backups = API.builtinBackups + cached.filter { !API.builtinBackups.contains($0) }
        }
        // 令牌优先从钥匙串读（重装 App 也不掉），读不到再看老地方
        if let saved = Keychain.get("token") {
            token = saved
        } else if let saved = UserDefaults.standard.string(forKey: "chris.token") {
            token = saved
            Keychain.set(saved, for: "token")
        }
    }

    /* ---------------------------------------------------------- 多入口（自动换线路）
       上线以后最怕的不是服务器挂，而是「线路被掐」：用户手机连不上，只会骂软件。
       这里维护一份候选入口（当前地址 + 后台下发的备用地址 + 同域名的另一个端口），
       连不上就自动换下一个再试一次；换通了就记住，用户不用重装、也不用手动改。 */

    /// 候选入口：当前 → 后台下发的备用 → 同域名的另一个端口（443 / 5443 互备）
    var candidates: [String] {
        var list: [String] = [server]
        list.append(contentsOf: backups)
        for s in list {
            let parts = s.split(separator: ":")
            if parts.count == 2 {
                let host = String(parts[0])
                let port = String(parts[1])
                list.append(host + (port == "5443" ? ":443" : ":5443"))
            } else if !s.isEmpty {
                list.append(s + ":5443")
            }
        }
        var seen = Set<String>()
        return list.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 服务器下发的入口列表（只认「域名:端口」这种写法，最多留 6 条，本地缓存）
    func setBackups(_ list: [String]) {
        var seen = Set<String>()
        let clean = list.map { API.normalizeServer($0) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !clean.isEmpty else { return }
        backups = Array(clean.prefix(6))
        UserDefaults.standard.set(backups, forKey: "chris.backups")
    }

    /// 换下一条入口。真换了返回 true（调用方可以拿新地址重试一次）
    @discardableResult
    func rotateEndpoint(force: Bool = false) -> Bool {
        let list = candidates
        guard list.count > 1 else { return false }
        let now = Date()
        if !force, now.timeIntervalSince(lastRotate) < 30 { return false }
        lastRotate = now
        let idx = list.firstIndex(of: server) ?? 0
        let next = list[(idx + 1) % list.count]
        guard next != server else { return false }
        server = next
        UserDefaults.standard.set(next, forKey: "chris.server")
        return true
    }

    /// 顺手更新一份备用入口（每次进前台拉一次；老服务器上没这个接口就静默跳过）
    func loadEndpointList() async {
        guard let payload: EndpointsPayload = try? await get("/api/endpoints", as: EndpointsPayload.self) else { return }
        if let list = payload.endpoints { setBackups(list) }
    }

    /// 版本信息 + 弹窗公告（App 启动/回前台各拉一次；老服务器上没有就整段跳过）
    func versionInfo() async -> (app: AppUpdateInfo?, notice: NoticeInfo?) {
        guard let payload: VersionPayload = try? await get("/api/version", as: VersionPayload.self) else {
            return (nil, nil)
        }
        return (payload.app, payload.notice)
    }

    /* ---------------- 看一看 / 搜一搜 ---------------- */

    /// 看一看：朋友在看的（视频）+ 朋友点赞的动态 + 大家都在看
    func lookAround() async throws -> LookAroundData {
        try await get("/api/lookaround", as: LookAroundData.self)
    }

    /// 搜一搜：一次搜完 联系人 / 群聊 / 朋友圈 / 视频号 / 聊天记录
    func searchAll(_ q: String, scope: String = "all") async throws -> SearchAllData {
        let path = "/api/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            + "&scope=" + scope
        return try await get(path, as: SearchAllData.self)
    }

    /// 「猜你想搜」：后台 data/search-hot.json 里配的词（后台改完不用出包）
    func searchHot() async throws -> [String] {
        struct Payload: Decodable { var words: [String]? }
        let p: Payload = try await get("/api/search-hot", as: Payload.self)
        return (p.words ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 是不是「压根连不上」这类错（超时 / 拒绝 / DNS / 断网）——只有这类才换线路
    static func isConnectivity(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        switch e.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed,
             .secureConnectionFailed, .serverCertificateUntrusted:
            return true
        default:
            return false
        }
    }

    /* 一律走加密通道：http 会被同网段的人抓到账号密码。
       证书是自签的，但 App 里带了信任代理（TrustAllDelegate），所以不用装证书也能连。 */
    var base: String { "https://\(server)" }

    /// 把用户填的地址规范化：统一成 https + 5443（老地址 :5180 自动换成 :5443）
    static func normalizeServer(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        v = v.replacingOccurrences(of: "https://", with: "")
        v = v.replacingOccurrences(of: "http://", with: "")
        while v.hasSuffix("/") { v.removeLast() }
        if !v.contains(":") { v += ":5443" }
        v = v.replacingOccurrences(of: ":5180", with: ":5443")
        v = v.replacingOccurrences(of: ":80", with: ":5443")
        return v
    }

    func setServer(_ value: String) {
        let v = API.normalizeServer(value)
        guard !v.isEmpty else { return }
        server = v
        UserDefaults.standard.set(v, forKey: "chris.server")
    }

    func setToken(_ value: String) {
        token = value
        UserDefaults.standard.set(value, forKey: "chris.token")
        Keychain.set(value, for: "token")
    }

    func clearToken() {
        token = ""
        UserDefaults.standard.removeObject(forKey: "chris.token")
        Keychain.remove("token")
    }

    /// /uploads/xxx.png、http://…、data:… 都能转成可加载的地址
    func assetURL(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        if path.hasPrefix("data:") { return nil }
        let p = path.hasPrefix("/") ? path : "/" + path
        return URL(string: base + p)
    }

    /// 取图片专用的下载：**带上登录令牌**。
    /// 服务器对 /uploads 的规则是「要么带签名、要么本人已登录」，
    /// 以前这里用的是不带任何请求头的 session.data(from:)，所以只要拿到的是
    /// 没签名/签名过期的老链接，就一律 403 —— 表现就是「头像能看、背景全加载不出来」。
    func imageData(_ url: URL) async throws -> Data {
        try await assetData(url)
    }

    /// 取任意资源（图片 / 语音 / 文件）的字节：**带登录令牌**。
    /// 语音消息要先把 m4a 下载下来才能播（AVAudioPlayer 只能读本地文件）。
    func assetData(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await session.data(for: req)
        return data
    }

    /* ---------------------------------------------------------- 底层请求 */

    /* ---------------------------------------------------------- 连接诊断（临时排查用） */

    /// 诊断用：把域名解析成 IP（看是不是 DNS 的事）
    static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let r = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = r
        while let cur = p {
            if let sa = cur.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, cur.pointee.ai_addrlen, &buf, socklen_t(buf.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    out.append(String(cString: buf))
                }
            }
            p = cur.pointee.ai_next
        }
        return out
    }

    /// 诊断用：直接打一次请求，把**原始错误**原样吐出来（不包装成"连不上服务器"）
    /// 传绝对地址就用绝对地址（用来测公网大站 / 明文口，判断是不是 App 自己的网络能力有问题）
    func probeAbsolute(_ urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "地址无效：\(urlString)" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return "成功 HTTP \(code)，\(data.count) 字节"
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    func probe(_ path: String) async -> String {
        await probeAbsolute(base + path)
    }

    /// 诊断用：取回一段**文本**（比如 /api/branding，用来确认 ICE/TURN 配置）
    func probeText(_ urlString: String, _ limit: Int = 600) async -> String {
        guard let url = URL(string: urlString) else { return "地址无效" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let txt = String(data: data, encoding: .utf8) ?? "(非文本)"
            return "HTTP \(code)：" + String(txt.prefix(limit))
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    /// 诊断用（老签名，保留兼容）
    func probeOld(_ path: String) async -> String {
        guard let url = URL(string: base + path) else { return "地址拼不出来：\(base + path)" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return "成功 HTTP \(code)，\(data.count) 字节"
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    /// 诊断用：当前这份候选入口（App 实际会按这个顺序试）
    var diagCandidates: [String] { candidates }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, retried: Bool = false) async throws -> Any {
        guard let url = URL(string: base + path) else {
            throw APIError.message("服务器地址不正确")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        /* 报一下自己是哪一版（"B456 · 09-23 21:08" 这种）——
           排查「两台手机版本不一样」时，服务器日志里一眼就能看出来 */
        req.setValue(AppInfo.build, forHTTPHeaderField: "X-App-Build")
        /* 设备标识：服务器拿它判断「这次是不是换了设备」，只有换了设备才弹滑动验证 */
        req.setValue(AppInfo.deviceId, forHTTPHeaderField: "X-Device-Id")
        /* 「登录设备管理」那一页要显示的三样：设备名 / 机型 / 系统。
           老客户端没有这三个头，服务器就退回按 UA 猜（只能猜出「浏览器 · iOS」）。 */
        if !AppInfo.deviceName.isEmpty {
            req.setValue(AppInfo.deviceName, forHTTPHeaderField: "X-Device-Name")
        }
        req.setValue(AppInfo.deviceModel, forHTTPHeaderField: "X-Device-Model")
        req.setValue(AppInfo.deviceOs, forHTTPHeaderField: "X-Device-Os")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
            offline = false                     // 通了：离线提示撤掉
        } catch {
            /* 连不上（超时 / 拒绝 / DNS / 断网）：自动换一条线路再试一次。
               上线以后线路抽风是常态，卡在「正在连接」比报个错更让人骂。 */
            if !retried, API.isConnectivity(error), rotateEndpoint() {
                return try await request(method, path, body: body, retried: true)
            }
            if API.isConnectivity(error) { offline = true }
            /* 对用户别抛服务器地址出来（那是内部信息，看着也莫名其妙） */
            throw APIError.message("连不上服务器，正在自动换线路…")
        }
        let data = result.0
        let response = result.1

        if let http = response as? HTTPURLResponse,
           let raw = http.value(forHTTPHeaderField: "Set-Cookie"),
           let range = raw.range(of: "chris_chat_session=") {
            let rest = raw[range.upperBound...]
            let value = rest.split(separator: ";").first.map(String.init) ?? ""
            if !value.isEmpty { setToken(value) }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw APIError.message("服务器返回了看不懂的内容")
        }
        guard let dict = obj as? [String: Any] else {
            throw APIError.message("服务器返回了看不懂的内容")
        }
        if (dict["ok"] as? Bool) != true {
            let msg = (dict["error"] as? String) ?? "请求失败"
            /* 428 + details.needSlider：服务端要补一次滑动验证（正常登录不会走到这里）。
               单独抛一个类型出来，让登录页能把滑块「弹出来」而不是弹个错误。 */
            if let det = dict["details"] as? [String: Any], (det["needSlider"] as? Bool) == true {
                throw APIError.needSlider
            }
            /* 未实名动了钱：和微信一样弹个对话框，带「去实名认证」入口（聊天不受影响） */
            if let det = dict["details"] as? [String: Any], (det["needRealName"] as? Bool) == true {
                RealNameGate.shared.prompt()
                throw APIError.needRealName
            }
            throw APIError.message(msg)
        }
        return dict["data"] ?? [String: Any]()
    }

    private func decode<T: Decodable>(_ any: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.message("数据解析失败")
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        do {
            let any = try await request("GET", path)
            API.saveOffline(path, any)          // 成功了就留一份，断网时回放
            return try decode(any, as: T.self)
        } catch {
            /* 断网 = 直接回放上一次的数据，别让页面对着一片空白报错。
               （只在"连不上"的时候兜，服务器真的返回错误照样往上抛） */
            if offline, let cached = API.cachedOffline(path) {
                return try decode(cached, as: T.self)
            }
            throw error
        }
    }

    /* ============================================================
       离线兜底缓存（学微信的逻辑）：
       这几个「列表类」接口上一次成功拿到的数据存一份在本机（内存 + 磁盘），
       断网时直接回放 —— 会话列表、通讯录、我的资料、朋友圈照常显示，
       只是收不到新的，顶上挂一条「当前网络不可用」。

       以前：断网时每个页面都报错，冷启动更是会话页/通讯录全空
       （用户反馈的"离线的时候全部画面都掉了"就是这个）。
       只缓存这几个白名单里的接口，别的接口照旧抛错，不会掩盖真实故障。
       ============================================================ */
    private static let offlinePrefixes = ["/api/chats", "/api/contacts", "/api/me",
                                          "/api/moments", "/api/me-page", "/api/plus"]
    private static var offlineMemo: [String: Any] = [:]
    private static let offlineLock = NSLock()

    private static func offlineCacheable(_ path: String) -> Bool {
        offlinePrefixes.contains { path.hasPrefix($0) }
    }

    /// 缓存文件：Application Support/chris-offline/<接口名>.json
    /// （文件名里只留字母数字，路径里的 / 和 ? 一律换成 _）
    private static func offlineFile(_ path: String) -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil, create: true) else { return nil }
        let folder = dir.appendingPathComponent("chris-offline", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let safe = String(path.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return folder.appendingPathComponent(safe + ".json")
    }

    /// 存一份（内存 + 磁盘）；不是白名单里的接口直接跳过
    static func saveOffline(_ path: String, _ data: Any) {
        guard offlineCacheable(path), JSONSerialization.isValidJSONObject(data) else { return }
        offlineLock.lock()
        offlineMemo[path] = data
        offlineLock.unlock()
        guard let url = offlineFile(path),
              let raw = try? JSONSerialization.data(withJSONObject: data) else { return }
        try? raw.write(to: url, options: .atomic)
    }

    /// 取一份（内存 → 磁盘）
    static func cachedOffline(_ path: String) -> Any? {
        guard offlineCacheable(path) else { return nil }
        offlineLock.lock()
        let hit = offlineMemo[path]
        offlineLock.unlock()
        if let hit = hit { return hit }
        guard let url = offlineFile(path),
              let raw = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: raw) else { return nil }
        offlineLock.lock()
        offlineMemo[path] = obj
        offlineLock.unlock()
        return obj
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: Any], as type: T.Type) async throws -> T {
        let any = try await request("POST", path, body: body)
        return try decode(any, as: T.self)
    }

    private func patch<T: Decodable>(_ path: String, _ body: [String: Any], as type: T.Type) async throws -> T {
        let any = try await request("PATCH", path, body: body)
        return try decode(any, as: T.self)
    }

    /* ---------------------------------------------------------- 业务接口 */

    /* ---------------------------------------------------------- 小游戏排行（网页游戏那层 JS 桥用） */

    /// 报分：只涨不跌。失败就算了 —— 不能因为报分失败把游戏也卡住。
    func gameScore(_ game: String, _ score: Int) async {
        _ = try? await request("POST", "/api/games/score", body: ["game": game, "score": score])
    }

    /// 好友榜单：**直接把服务器那段 JSON 原样交给网页那层画**
    /// （原生这边不再解析一遍，省得两套模型对不齐）
    func gameRankJSON(_ game: String) async -> String {
        let q = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
        guard let any = try? await request("GET", "/api/games/rank?game=" + q),
              let d = try? JSONSerialization.data(withJSONObject: any, options: []),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    /// 和上面一样，但**把好友头像先下成本机、转成 data: 图片**再交给网页。
    /// 为什么必须这样：榜单是在 WKWebView 里画的，而我们的服务器是 IP + 自签证书，
    /// WebView 直接 `<img src="https://43.242...">` 一律加载不出来（头像全空白）。
    /// 走 App 自己的网络层拿到字节再内联，WebView 就能显示了。
    func gameRankJSONWithAvatars(_ game: String) async -> String {
        let q = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
        guard let any = try? await request("GET", "/api/games/rank?game=" + q),
              var d = any as? [String: Any] else { return "" }
        if var list = d["list"] as? [[String: Any]] {
            for i in list.indices {
                guard let a = list[i]["avatar"] as? String, !a.isEmpty, let u = assetURL(a) else {
                    list[i]["avatar"] = ""
                    continue
                }
                if let data = try? await assetData(u), data.count < 700_000 {
                    list[i]["avatar"] = "data:image/jpeg;base64," + data.base64EncodedString()
                } else {
                    list[i]["avatar"] = ""
                }
            }
            d["list"] = list
        }
        guard let out = try? JSONSerialization.data(withJSONObject: d, options: []),
              let s = String(data: out, encoding: .utf8) else { return "" }
        return s
    }

    /* ---------------------------------------------------------- 音乐：我正在听 / 好友在听 */

    /* ---------------------------------------------------------- App 内的「管理」（ops 用户） */

    /// 管理页要的数据：曲库 + 小游戏/小程序清单
    func manageData() async -> ManageData? {
        try? await get("/api/manage", as: ManageData.self)
    }

    /// 上新音乐 / 改一首歌（id 传空 = 新增）
    func manageSaveMusic(id: String, title: String, artist: String,
                         cover: String, url: String, lyrics: String) async throws {
        var b: [String: Any] = ["title": title, "artist": artist,
                                "cover": cover, "url": url, "lyrics": lyrics]
        if !id.isEmpty { b["id"] = id }
        _ = try await request("POST", "/api/manage/music", body: b)
    }

    /// 换图标（kind = music / miniapp）
    func manageSetIcon(kind: String, id: String, cover: String) async throws {
        _ = try await request("POST", "/api/manage/icon",
                              body: ["kind": kind, "id": id, "cover": cover])
    }

    /// 改小程序/小游戏：名字、说明、图标（emoji）、入口地址
    func manageSaveMiniApp(id: String, name: String, desc: String,
                           icon: String, group: String, url: String) async throws {
        _ = try await request("POST", "/api/manage/miniapp",
                              body: ["id": id, "name": name, "desc": desc,
                                     "icon": icon, "group": group, "url": url])
    }

    /// 批量删歌（管理页多选以后点删除）
    func manageRemoveMusic(ids: [String]) async throws {
        _ = try await request("POST", "/api/manage/music/remove", body: ["ids": ids])
    }

    /* ---------------------------------------------------------- 系统通知开关（App 管理页） */

    func sysNoticeCfg() async -> (enabled: Bool, types: [String: Bool]) {
        struct R: Decodable { var enabled: Int?; var types: [String: Int]? }
        guard let r: R = try? await get("/api/manage/sysnotice", as: R.self) else {
            return (true, ["login": true, "security": true, "pay": true, "notice": true])
        }
        var t: [String: Bool] = [:]
        (r.types ?? [:]).forEach { t[$0.key] = $0.value != 0 }
        return ((r.enabled ?? 1) != 0, t)
    }

    func saveSysNotice(enabled: Bool, types: [String: Bool]) async throws {
        var t: [String: Int] = [:]
        types.forEach { t[$0.key] = $0.value ? 1 : 0 }
        _ = try await request("POST", "/api/manage/sysnotice", body: ["enabled": enabled ? 1 : 0, "types": t])
    }

    /* ---------------------------------------------------------- 官方号（名字 / 头像） */

    /// 官方号 = 「星言团队」（系统通知号）+ 几个机器人（星联世界 / AI 助手 / 小星 / 在线客服）。
    /// 管理页里像换头像一样换：点一下选张图 → 上传 → 保存。
    struct OfficialAccount: Decodable, Identifiable {
        var key: String
        var name: String
        var avatar: String?
        var desc: String?
        var sys: Bool?
        var id: String { key }
    }

    func officialAccounts() async throws -> [OfficialAccount] {
        struct R: Decodable { var items: [OfficialAccount]? }
        let r: R = try await get("/api/manage/official", as: R.self)
        return r.items ?? []
    }

    /// 改官方号的名字 / 头像（只传要改的那个；两个都不传就等于什么也不改）
    @discardableResult
    func saveOfficial(key: String, name: String? = nil, avatar: String? = nil) async throws -> [OfficialAccount] {
        struct R: Decodable { var items: [OfficialAccount]? }
        var body: [String: Any] = ["key": key]
        if let name = name { body["name"] = name }
        if let avatar = avatar { body["avatar"] = avatar }
        let r: R = try await post("/api/manage/official", body, as: R.self)
        return r.items ?? []
    }

    /// 报一下"我正在听这首"（好友「听一听 → 朋友推荐」那一栏看的就是它）。失败就算了。
    func musicNow(_ t: MusicTrack) async {
        _ = try? await request("POST", "/api/music/now", body: [
            "id": t.id, "title": t.title, "artist": t.artist ?? "",
            "cover": t.cover ?? "", "url": t.url
        ])
    }

    /// 我好友最近在听什么（服务器只回 2 小时内的）
    func friendsNowPlaying() async -> [FriendNowPlaying] {
        guard let p: NowPlayingPayload = try? await get("/api/music/friends", as: NowPlayingPayload.self) else { return [] }
        return p.list ?? []
    }

    /// 给好友的「状态」点赞 / 取消（朋友的状态那一页）
    func statusLike(_ userId: String) async -> (liked: Bool, count: Int)? {
        struct R: Decodable { var liked: Bool?; var count: Int? }
        guard let r: R = try? await post("/api/status/like", ["id": userId], as: R.self) else { return nil }
        return (r.liked ?? false, r.count ?? 0)
    }

    /// 给一首歌点赞 / 取消
    func musicLike(_ id: String) async -> (liked: Bool, count: Int)? {
        struct R: Decodable { var liked: Bool?; var count: Int? }
        guard let r: R = try? await post("/api/music/like", ["id": id], as: R.self) else { return nil }
        return (r.liked ?? false, r.count ?? 0)
    }

    /// 记一次转发（转发音乐卡片时调）
    func musicShareCount(_ id: String) async {
        _ = try? await request("POST", "/api/music/share", body: ["id": id])
    }

    /* ---------------------------------------------------------- 棋牌大厅（桌子） */

    /// 大厅里摆着的桌子
    func gameTables(_ game: String) async -> [GameTable] {
        struct R: Decodable { var tables: [GameTable]? }
        guard let r: R = try? await get("/api/games/tables?game=" + game, as: R.self) else { return [] }
        return r.tables ?? []
    }

    /// 自己开一桌 → (桌号, 我的座位)
    func gameTableCreate(_ game: String) async -> (code: String, seat: Int)? {
        struct T: Decodable { var code: String?; var seats: [GameTableSeat?]? }
        struct R: Decodable { var table: T?; var seat: Int? }
        guard let r: R = try? await post("/api/games/tables/create", ["game": game], as: R.self),
              let code = r.table?.code else { return nil }
        return (code, r.seat ?? 0)
    }

    /// 坐下 → (桌号, 座位, 桌上的人, 开没开)
    func gameTableSit(_ code: String) async -> (seat: Int, players: [String?], started: Bool)? {
        struct T: Decodable { var code: String?; var started: Bool?; var seats: [GameTableSeat?]? }
        struct R: Decodable { var table: T?; var seat: Int?; var started: Bool? }
        guard let r: R = try? await post("/api/games/tables/sit", ["code": code], as: R.self),
              let t = r.table else { return nil }
        let names = (t.seats ?? []).map { $0?.name }
        return (r.seat ?? 0, names, (r.started ?? t.started) ?? false)
    }

    func gameTableLeave(_ code: String) async {
        _ = try? await request("POST", "/api/games/tables/leave", body: ["code": code])
    }

    func gameTableStart(_ code: String) async {
        _ = try? await request("POST", "/api/games/tables/start", body: ["code": code])
    }

    func gameTableMove(_ code: String, _ move: [String: Any]) async {
        _ = try? await request("POST", "/api/games/tables/move", body: ["code": code, "move": move])
    }

    /// 拉别人走的步（轮询）
    func gameTableMoves(_ code: String, since: Int) async -> (n: Int, list: [Any]) {
        struct R: Decodable {
            struct M: Decodable {
                var n: Int?; var seat: Int?
                struct MV: Decodable { var from: Int?; var to: Int? }
                var move: MV?
            }
            var n: Int?; var moves: [M]?
        }
        guard let r: R = try? await get("/api/games/tables/moves?code=\(code)&since=\(since)", as: R.self) else {
            return (since, [])
        }
        let list: [Any] = (r.moves ?? []).map { m in
            ["n": m.n ?? 0, "seat": m.seat ?? 0,
             "move": ["from": m.move?.from ?? 0, "to": m.move?.to ?? 0]]
        }
        return (r.n ?? since, list)
    }

    func branding() async -> BrandInfo? {
        guard let payload: BrandingPayload = try? await get("/api/branding", as: BrandingPayload.self) else { return nil }
        return payload.branding
    }

    /// 便宜的一次探活（离线提示用）：只打 /api/health，不带任何业务数据
    func ping() async {
        _ = try? await request("GET", "/api/health")
    }

    /* 服务器版本（「设置 → 版本更新」用）：拿不到就返回 nil */
    func serverVersion() async -> String? {
        struct VersionPayload: Decodable { var version: String? }
        guard let p: VersionPayload = try? await get("/api/version", as: VersionPayload.self) else { return nil }
        return p.version ?? ""
    }

    /// App 安装包的限时签名链接（要登录才给）：
    /// 安装包直链收口（data/download.json 的 mode=gated）以后，App 内更新就靠这条链接。
    /// 拿不到就返回 nil，调用方退回原来的公开地址（过渡期用）。
    func appDownloadTicket() async -> String? {
        struct P: Decodable { var url: String? }
        guard let p: P = try? await get("/api/app/download", as: P.self) else { return nil }
        let u = (p.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? nil : u
    }

    /// 后台配的「红点提醒」：某个位置 auto（按真实数据）/ on（一直亮）/ off（不显示）
    func badgeConfig() async -> [String: String] {
        guard let payload: BadgesPayload = try? await get("/api/badges", as: BadgesPayload.self) else { return [:] }
        return payload.badges ?? [:]
    }

    /// 服务器上的界面配置（data/ui.json）+ 换过的 UI 图标（data/icons.json）
    func uiConfig() async -> (ui: [String: Any], icons: [String: String]) {
        guard let any = try? await request("GET", "/api/ui"),
              let dict = any as? [String: Any] else { return ([:], [:]) }
        let ui = dict["ui"] as? [String: Any] ?? [:]
        var icons: [String: String] = [:]
        if let raw = dict["icons"] as? [String: Any] {
            for (k, v) in raw where !k.hasPrefix("_") {
                if let s = v as? String, !s.isEmpty { icons[k] = s }
            }
        }
        return (ui, icons)
    }

    /// 把真实量到的尺寸报回服务器（只用来对着参考图校准，不影响使用）
    func reportMeasure(_ items: [[String: Any]]) async {
        _ = try? await request("POST", "/api/measure", body: [
            "screen": Double(L.width),
            "safeTop": Double(L.safeTop),
            "safeBottom": Double(L.safeBottom),
            "menuH": Double(L.menuH),
            "chatRowH": Double(L.rowH),
            "ctRowH": Double(L.ctRowH),
            "items": items
        ])
    }

    func login(username: String, password: String) async throws -> User {
        try await login(username: username, password: password, sliderTicket: "")
    }

    /// 登录。服务器开了「登录滑动验证」时必须带上滑块换来的一次性通行证。
    func login(username: String, password: String, sliderTicket: String) async throws -> User {
        var body: [String: Any] = ["username": username, "password": password]
        if !sliderTicket.isEmpty { body["sliderTicket"] = sliderTicket }
        let payload: LoginPayload = try await post("/api/login", body, as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("登录失败") }
        return user
    }

    /* ---------------- 登录滑动验证（拖滑块拼图） ---------------- */

    /* ---------------- 腾讯云 TRTC（音视频通话） ---------------- */

    /// 进房参数：sdkAppId / userId / userSig / roomId（密钥只在服务端）
    struct TRTCSig: Decodable {
        var sdkAppId: Int
        var userId: String
        var userSig: String
        var roomId: Int
        var roomStr: String?
        var expire: Int?
    }

    /// 取一张 TRTC 进房票。room 用「这次通话的 callId」，两边算出来的房间号一致。
    /// media 只是给服务端看的开关：服务端把 data/trtc.json 的 voiceEnabled 设成 false，
    /// 语音这条就会拿到失败、自动继续用自建转发通道（不用重装 App 就能一键退回）。
    func trtcSig(room: String, media: String = "video") async throws -> TRTCSig {
        try await get("/api/trtc/sig?room=" + (room.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? room)
                      + "&media=" + media,
                      as: TRTCSig.self)
    }

    /// 服务端出的一道题：缺口在哪、坐标系多大、背景用什么种子画
    struct SliderChallenge: Decodable {
        var id: String
        var width: Double
        var height: Double
        var piece: Double
        var targetX: Double
        var targetY: Double
        var tolerance: Double?
        var seed: Int?
        var expiresIn: Int?
    }

    private struct SliderTicketPayload: Decodable { var ticket: String?; var expiresIn: Int? }

    /// 领题（同一个 IP 10 分钟最多 40 次）
    func sliderChallenge() async throws -> SliderChallenge {
        try await get("/api/slider", as: SliderChallenge.self)
    }

    /// 交卷：位置对了，服务端给一张一次性通行证（3 分钟有效、用掉即废）
    func verifySlider(id: String, x: Double, y: Double) async throws -> String {
        let payload: SliderTicketPayload = try await post("/api/slider/verify",
                                                          ["id": id, "x": x, "y": y],
                                                          as: SliderTicketPayload.self)
        guard let t = payload.ticket, !t.isEmpty else { throw APIError.message("滑动验证失败") }
        return t
    }

    /// 账号被禁用后的「身份证自助解封」：服务器校验 18 位身份证（含校验位），
    /// 通过就解封并把登录态直接发下来，所以调完这个就等于登录成功了。
    @discardableResult
    func unban(username: String, password: String, idCard: String) async throws -> User {
        let payload: LoginPayload = try await post("/api/unban",
                                                   ["username": username, "password": password, "idCard": idCard],
                                                   as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("解封失败") }
        return user
    }

    /// 本地没接短信通道，服务器会直接把验证码给回来
    func phoneCode(phone: String) async throws -> String? {
        let payload: PhoneCodePayload = try await post("/api/login/phone-code",
                                                       ["phone": phone],
                                                       as: PhoneCodePayload.self)
        return payload.devCode
    }

    /// 注册用的图形验证码（服务器给的是 SVG，App 里用 CaptchaView 画出来）
    func captcha() async throws -> (id: String, svg: String) {
        let payload: CaptchaPayload = try await get("/api/captcha", as: CaptchaPayload.self)
        return (payload.id ?? "", payload.svg ?? "")
    }

    /// 注册新账号（注册完成后由调用方再去登录一次）
    func register(username: String, nickname: String, password: String, captchaId: String, captcha: String) async throws -> User {
        let payload: LoginPayload = try await post("/api/register", [
            "username": username,
            "nickname": nickname,
            "password": password,
            "captchaId": captchaId,
            "captcha": captcha
        ], as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("注册失败") }
        return user
    }

    /* ---------------- 设备确认登录（就是「微信登录」那个核心按钮）----------------
       这台设备出一个 6 位数字，在已经登录的设备上确认，这台就登上了。 */
    func pairStart(device: String = "") async throws -> (code: String, expiresIn: Int) {
        var body: [String: Any] = [:]
        if !device.isEmpty { body["device"] = device }
        /* 带上「这台手机上次登录的账号」：服务端就能直接给那台**已登录的手机**推一条
           「登录确认」（不用手输数字）。没登录过就没有这个提示，靠对方扫二维码确认。 */
        if let last = AccountStore.load().first?.username, !last.isEmpty {
            body["username"] = last
        }
        let p: PairStartPayload = try await post("/api/pair/start", body, as: PairStartPayload.self)
        return (p.code ?? "", p.expiresIn ?? 180)
    }

    /// 确认方先看一眼：这是哪台设备在请求登录（微信的确认页会写清楚设备名和时间）
    func pairInfo(code: String) async -> (device: String, at: String)? {
        struct Payload: Decodable { var status: String?; var device: String?; var at: String? }
        guard let p: Payload = try? await get("/api/pair/info?code=\(code)", as: Payload.self),
              (p.status ?? "") == "pending" else { return nil }
        return (p.device ?? "", p.at ?? "")
    }

    /// 轮询：pending（还没确认）/ approved（确认了，带回登录令牌）/ expired
    func pairStatus(code: String) async throws -> (status: String, user: User?, token: String?) {
        let p: PairStatusPayload = try await get("/api/pair/status?code=\(code)", as: PairStatusPayload.self)
        return (p.status ?? "pending", p.user, p.token)
    }

    /// 已登录的这台设备去确认别人（网页版点「微信授权登录」出的那个数字）
    @discardableResult
    func pairApprove(code: String) async -> String? {
        do {
            struct ApprovePayload: Decodable { var approved: Bool? }
            let _: ApprovePayload = try await post("/api/pair/approve", ["code": code], as: ApprovePayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "确认失败" }
    }

    func loginPhone(phone: String, code: String) async throws -> User {
        let payload: LoginPayload = try await post("/api/login/phone",
                                                   ["phone": phone, "code": code],
                                                   as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("登录失败") }
        return user
    }

    func session() async throws -> (ok: Bool, user: User?) {
        let payload: SessionPayload = try await get("/api/session", as: SessionPayload.self)
        return (payload.authenticated ?? false, payload.user)
    }

    func logout() async {
        _ = try? await request("POST", "/api/logout", body: [:])
        clearToken()
    }

    func me() async throws -> User? {
        let payload: MePayload = try await get("/api/me", as: MePayload.self)
        return payload.user
    }

    /// 个人名片要的完整资料（带 relation / online / phone / momentCount）
    func user(id: String) async throws -> User {
        let payload: UserPayload = try await get("/api/users/\(id)", as: UserPayload.self)
        guard let user = payload.user else { throw APIError.message("用户不存在") }
        return user
    }

    /* ---------------------------------------------------------- 附近的人 */

    /// 上报自己的位置（进「附近的人」页时调一次）；visible=false 就是隐身，不上榜
    func nearbyReport(lat: Double, lng: Double, visible: Bool = true) async throws {
        _ = try await request("POST", "/api/nearby", body: [
            "lat": lat, "lng": lng, "visible": visible
        ])
    }

    /// 附近的人名单（按距离排）
    func nearby(lat: Double?, lng: Double?, gender: String = "all", maxKm: Double = 5)
        async throws -> (people: [NearbyPerson], wider: Int, maxKm: Double) {
        var path = "/api/nearby?gender=\(gender)&maxKm=\(maxKm)"
        if let lat = lat, let lng = lng { path += "&lat=\(lat)&lng=\(lng)" }
        let payload: NearbyPayload = try await get(path, as: NearbyPayload.self)
        return (payload.people, payload.wider ?? 0, payload.maxKm ?? maxKm)
    }

    /// 打招呼：给对方发一条消息（会话就出来了）
    func nearbyHello(userId: String, text: String) async throws -> String {
        let payload: NearbyHelloPayload = try await post("/api/nearby/hello",
                                                         ["userId": userId, "text": text],
                                                         as: NearbyHelloPayload.self)
        return payload.chatId ?? ""
    }

    /// 清除自己的位置（从附近的人里消失，和微信的「清除位置信息并退出」一样）
    func nearbyClear() async throws {
        _ = try await request("DELETE", "/api/nearby")
    }

    /* ---------------------------------------------------------- 直播专场 */

    func liveRooms() async throws -> [LiveRoom] {
        let p: LivePayload = try await get("/api/live", as: LivePayload.self)
        return p.rooms
    }
    func liveJoin(_ id: String) async throws -> Int {
        let p: LiveJoinPayload = try await post("/api/live/\(id)/join", [:], as: LiveJoinPayload.self)
        return p.watching ?? 0
    }
    func liveLeave(_ id: String) async {
        _ = try? await request("POST", "/api/live/\(id)/leave", body: [:])
    }
    func liveDanmaku(_ id: String, text: String) async throws {
        _ = try await request("POST", "/api/live/\(id)/danmaku", body: ["text": text])
    }
    func liveLike(_ id: String) async throws -> Int {
        let p: LiveLikePayload = try await post("/api/live/\(id)/like", [:], as: LiveLikePayload.self)
        return p.likes ?? 0
    }

    /* ---------------------------------------------------------- 游戏页 */

    func games() async throws -> [MiniGame] {
        let p: GamesPayload = try await get("/api/games", as: GamesPayload.self)
        return p.items
    }

    /* ---------------------------------------------------------- 视频号 */

    func feedItems() async throws -> [FeedItem] {
        let p: FeedPayload = try await get("/api/feed", as: FeedPayload.self)
        return p.items
    }
    /// 只看自己发布的作品（「我 → 作品」那一页用）
    func myFeedItems() async throws -> [FeedItem] {
        let p: FeedPayload = try await get("/api/feed?mine=1", as: FeedPayload.self)
        return p.items
    }
    /// 列表 + 后台配的样式和开关
    /// tab: recommend 推荐（抖音那套）/ follow 关注 / friends 朋友
    func feed(tab: String = "recommend") async throws -> (items: [FeedItem], style: FeedStyle, flags: FeedFlags) {
        let p: FeedPayload = try await get("/api/feed?tab=\(tab)", as: FeedPayload.self)
        return (p.items, p.style ?? FeedStyle(), p.flags ?? FeedFlags())
    }

    /* ---------------- 位置搜索（走高德） ----------------
       后台配了高德 Key 就用高德的 POI（国内比苹果地图准很多），没配时服务端返回 503，
       调用方自己退回系统地图搜索。 */
    struct GeoPlace: Decodable {
        var name: String?
        var addr: String?
        var lat: Double?
        var lng: Double?
    }
    private struct GeoSearchPayload: Decodable {
        var source: String?
        var places: [GeoPlace]?
    }
    func geoSearch(q: String, lat: Double, lng: Double) async throws -> [GeoPlace] {
        let q2 = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let p: GeoSearchPayload = try await get("/api/geo/search?q=\(q2)&lat=\(lat)&lng=\(lng)",
                                                as: GeoSearchPayload.self)
        return p.places ?? []
    }
    func feedLike(_ id: String) async throws -> (liked: Bool, likes: Int) {
        /* 注意：服务器这条是 POST /api/feed/like，body 里带 id（不是路径参数） */
        let p: FeedLikePayload = try await post("/api/feed/like", ["id": id], as: FeedLikePayload.self)
        return (p.liked ?? false, p.likes ?? 0)
    }

    /// 视频号「关注 / 取消关注」（和好友关系分开，微信视频号就是这个逻辑）
    func feedFollow(userId: String, follow: Bool) async -> Bool {
        struct P: Decodable { var following: Bool?; var count: Int? }
        let p: P? = try? await post("/api/feed/follow", ["userId": userId, "follow": follow], as: P.self)
        return p?.following ?? false
    }
    func feedComment(_ id: String, text: String) async throws -> Int {
        let p: FeedCommentPayload = try await post("/api/feed/comment", ["id": id, "text": text],
                                                   as: FeedCommentPayload.self)
        return p.comments ?? 0
    }
    /// 读某条视频的评论列表
    func feedComments(_ id: String) async throws -> [FeedCommentItem] {
        let p: FeedCommentsPayload = try await get("/api/feed/comments?id=\(id)", as: FeedCommentsPayload.self)
        return p.comments ?? []
    }
    /// 取一整套短剧的全部集数（「选集」面板用）
    func feedSeries(_ id: String) async throws -> (name: String, items: [FeedItem]) {
        let p: FeedSeriesPayload = try await get("/api/feed/series?id=\(id)", as: FeedSeriesPayload.self)
        return (p.name ?? "", p.items ?? [])
    }
    /// 收藏 / 取消收藏一条视频
    func feedFavorite(_ id: String) async throws -> (favorited: Bool, favorites: Int) {
        let p: FeedFavoritePayload = try await post("/api/feed/favorite", ["id": id], as: FeedFavoritePayload.self)
        return (p.favorited ?? false, p.favorites ?? 0)
    }
    func feedPublish(video: String, desc: String, music: String) async throws -> String {
        let p: FeedPublishPayload = try await post("/api/feed/publish",
                                                   ["video": video, "desc": desc, "music": music],
                                                   as: FeedPublishPayload.self)
        return p.id ?? ""
    }
    func feedDelete(_ id: String) async {
        _ = try? await request("DELETE", "/api/feed/\(id)")
    }
    /// 剪水印：把带水印的那条边裁掉，返回新视频地址（服务端 ffmpeg 处理）
    func feedTrim(_ url: String, top: Double, bottom: Double, left: Double, right: Double) async throws -> String {
        let p: FeedTrimPayload = try await post("/api/feed/trim",
                                                ["url": url, "top": top, "bottom": bottom,
                                                 "left": left, "right": right, "fill": true],
                                                as: FeedTrimPayload.self)
        return p.url ?? url
    }

    /* ---------------------------------------------------------- 摇一摇 */

    /// 摇一下：把自己「正在摇」报上去，服务器把同时摇的人配给我
    func shake(lat: Double?, lng: Double?) async throws -> ShakeResult {
        var body: [String: Any] = [:]
        if let lat = lat, let lng = lng { body["lat"] = lat; body["lng"] = lng }
        return try await post("/api/shake", body, as: ShakeResult.self)
    }

    /// 通话诊断：连不上时把 ICE 状态报回服务器（写进 call-trace.log）
    func callDiag(_ text: String) async {
        _ = try? await request("POST", "/api/call-diag", body: ["text": text])
    }

    func chats() async throws -> [Chat] {
        let payload: ChatsPayload = try await get("/api/chats", as: ChatsPayload.self)
        return payload.chats
    }

    /* ---------------- 登录后同步最近的聊天记录（微信那句「登录后同步最近的聊天记录」） ----------------
       服务端支持一次把最近 N 个会话 + 每个会话最近 M 条消息带回来（/api/chats?withMessages=1），
       同步下来的消息先铺在界面上（进会话不用等网络），随后再拉最新的。 */
    struct SyncChat: Decodable {
        var id: String
        var title: String?
        var messages: [Message]?
    }
    private struct SyncChatsPayload: Decodable {
        var chats: [Chat]
        var sync: Sync?
        struct Sync: Decodable {
            var chats: [SyncChat]?
            var syncedAt: String?
        }
    }

    func chatsWithRecentMessages(chats: Int = 10, limit: Int = 30) async throws -> (chats: [Chat], synced: [SyncChat], syncedAt: String) {
        let n = max(1, min(30, chats))
        let m = max(5, min(100, limit))
        let p: SyncChatsPayload = try await get("/api/chats?withMessages=1&syncChats=\(n)&syncLimit=\(m)",
                                                as: SyncChatsPayload.self)
        return (p.chats, p.sync?.chats ?? [], p.sync?.syncedAt ?? "")
    }

    /// 按「微信号 / 手机号」精确找人（转账页填收款账号用）
    func findUserByAccount(_ q: String) async throws -> User? {
        let payload: UsersPayload = try await get("/api/users?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)", as: UsersPayload.self)
        return payload.users.first
    }

    /// 搜人（微信「添加朋友」那种）：返回列表，带 relation 字段（friend / requested / incoming / none）
    func searchUsers(_ q: String) async throws -> [User] {
        let payload: UsersPayload = try await get("/api/users?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)", as: UsersPayload.self)
        return payload.users
    }

    /// 发好友申请时可以带一句验证消息
    func addFriend(username: String, note: String) async throws {
        var body: [String: Any] = ["username": username]
        if !note.isEmpty { body["message"] = note }
        _ = try await request("POST", "/api/friends/request", body: body)
    }

    /// 搜到的人没有星言号时用 userId 发申请（同样能带验证消息）
    func addFriend(userId: String, note: String = "") async throws {
        var body: [String: Any] = ["userId": userId]
        if !note.isEmpty { body["message"] = note }
        _ = try await request("POST", "/api/friends/request", body: body)
    }

    /* ---------------------------------------------------------- 朋友资料（微信「设置备注和标签」） */

    struct FriendMeta: Decodable {
        var remark: String?
        var tags: [String]?
        var star: Bool?
        var block: Bool?
        /// 我不看他（她）的朋友圈
        var noMoments: Bool?
        /// 他不能看我的朋友圈
        var hideMyMoments: Bool?
        var chatOnly: Bool?
        /// 好友添加时间 / 来源（我加的 / 他加的我）/ 他有没有拉黑我
        var addedAt: String?
        var source: String?
        var blockedMe: Bool?
    }

    private struct FriendMetaPayload: Decodable {
        var meta: FriendMeta?
        var addedAt: String?
        var source: String?
        var blockedMe: Bool?
    }

    func friendMeta(userId: String) async throws -> FriendMeta {
        let p: FriendMetaPayload = try await get("/api/friends/meta?userId=\(userId)", as: FriendMetaPayload.self)
        var m = p.meta ?? FriendMeta()
        if m.addedAt == nil { m.addedAt = p.addedAt }
        if m.source == nil { m.source = p.source }
        if m.blockedMe == nil { m.blockedMe = p.blockedMe }
        return m
    }

    /// 改备注名 / 标签 / 星标 / 朋友权限 / 拉黑 —— 只传要改的那几项
    @discardableResult
    func setFriendMeta(userId: String, remark: String? = nil, tags: [String]? = nil,
                       star: Bool? = nil, block: Bool? = nil,
                       noMoments: Bool? = nil, hideMyMoments: Bool? = nil) async -> Bool {
        var body: [String: Any] = ["userId": userId]
        if let v = remark { body["remark"] = v }
        if let v = tags { body["tags"] = v }
        if let v = star { body["star"] = v }
        if let v = block { body["block"] = v }
        if let v = noMoments { body["noMoments"] = v }
        if let v = hideMyMoments { body["hideMyMoments"] = v }
        do { _ = try await request("POST", "/api/friends/meta", body: body); return true }
        catch { return false }
    }

    /// 删除好友（只动我这边，对方通讯录不受影响 —— 微信就是这样）
    func removeFriend(userId: String) async -> String? {
        do {
            _ = try await request("POST", "/api/friends/remove", body: ["userId": userId])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    /* ---------------------------------------------------------- 账号与安全（微信那套） */

    /* ---------------------------------------------------------- 共享实时位置 */

    /* ---------------------------------------------------------- 零钱：银行卡 / 充值 / 提现 */

    struct WalletBankCard: Decodable, Identifiable, Hashable {
        var id: String
        var bank: String?
        var tail: String?
        var holder: String?
        var isDefault: Bool?
        var addedAt: String?
        var label: String { (bank ?? "银行卡") + "（" + (tail ?? "****") + "）" }
    }
    private struct BanksPayload: Decodable { var banks: [WalletBankCard]? }
    private struct BankPayload: Decodable { var bank: WalletBankCard?; var banks: [WalletBankCard]? }

    func walletBanks() async throws -> [WalletBankCard] {
        let p: BanksPayload = try await get("/api/wallet/banks", as: BanksPayload.self)
        return p.banks ?? []
    }

    func addBank(bank: String, cardNo: String, holder: String) async throws -> [WalletBankCard] {
        let p: BankPayload = try await post("/api/wallet/banks",
                                            ["bank": bank, "cardNo": cardNo, "holder": holder],
                                            as: BankPayload.self)
        return p.banks ?? []
    }

    func removeBank(id: String) async {
        _ = try? await request("POST", "/api/wallet/banks/remove", body: ["id": id])
    }

    struct MoneyResult: Decodable {
        var balance: Double?
        var fee: Double?
        var bankText: String?
        var expect: String?
        var status: String?
    }

    /// 充值：银行卡 → 零钱
    func walletRecharge(amount: Double, bankId: String) async throws -> MoneyResult {
        try await post("/api/wallet/recharge", ["amount": amount, "bankId": bankId], as: MoneyResult.self)
    }

    /// 提现：零钱 → 银行卡（要支付密码，或已通过面容）
    func walletWithdraw(amount: Double, bankId: String, password: String, face: Bool) async throws -> MoneyResult {
        try await post("/api/wallet/withdraw",
                       ["amount": amount, "bankId": bankId, "password": password, "face": face],
                       as: MoneyResult.self)
    }

    struct WalletOp: Decodable, Identifiable, Hashable {
        var id: String
        var kind: String?
        var amount: Double?
        var fee: Double?
        var bankText: String?
        var status: String?
        var createdAt: String?
    }
    private struct OpsPayload: Decodable { var ops: [WalletOp]? }

    func walletOps() async throws -> [WalletOp] {
        let p: OpsPayload = try await get("/api/wallet/withdraws", as: OpsPayload.self)
        return p.ops ?? []
    }

    /* ---------------------------------------------------------- 存储空间 */
    struct StorageChat: Decodable, Identifiable {
        var chatId: String
        var title: String
        var avatar: String?
        var messages: Int
        var bytes: Int
        var id: String { chatId }
    }
    struct StorageInfo: Decodable {
        struct Kinds: Decodable {
            var image: Int
            var video: Int
            var file: Int
            var audio: Int
        }
        var total: Int
        var chats: [StorageChat]
        var kinds: Kinds
        var uploads: Int
    }
    func storage() async throws -> StorageInfo {
        try await get("/api/storage", as: StorageInfo.self)
    }

    /* ------------------------------------------------ 红包（微信那套） ----------------------------------
       拼手气 / 普通、群红包、每人限领一次、24 小时没抢完退回发红包的人。
       卡片上要的信息、拆红包、详情、红包记录都在下面这几个调用里。 */
    struct RedPacketRaw: Decodable {
        var id: String
        var total: Double?
        var count: Int?
        var claimedCount: Int?
        var claimedIds: [String]?
        var type: String?
        var note: String?
        var status: String?
        var expired: Bool?
        var fromId: String?
        var fromName: String?
        var expiresAt: Double?
        var refundAmount: Double?
        /* 封面（发红包时挑的那张，卡片和拆红包页按它画） */
        var coverId: String?
        var coverName: String?
        var cover: String?
        var coverThumb: String?
        var coverColor: String?
        /* 详情接口额外给的 */
        var fromAvatar: String?
        var claimedTotal: Double?
        var leftAmount: Double?
        var leftCount: Int?
        var bestUserId: String?
        var bestAmount: Double?
        var claims: [RedPacketClaimRaw]?
    }
    struct RedPacketClaimRaw: Decodable {
        var userId: String
        var name: String?
        var avatar: String?
        var amount: Double
        var at: String?
        var fromId: String?
        var fromName: String?
    }
    struct RedPacketSendResult: Decodable {
        var balance: Double
        var amount: Double?
        var count: Int?
        var type: String?
        var redpacket: RedPacketRaw
    }
    struct RedPacketClaimResult: Decodable {
        var balance: Double
        var amount: Double
        var redpacket: RedPacketRaw
        var leftCount: Int?
    }
    struct RedPacketDetailResult: Decodable {
        var redpacket: RedPacketRaw
    }
    struct RedPacketRecord: Decodable, Identifiable {
        var id: String
        var chatId: String?
        var direction: String?
        var total: Double?
        var count: Int?
        var type: String?
        var note: String?
        var status: String?
        var expired: Bool?
        var claimedCount: Int?
        var fromName: String?
        var fromAvatar: String?
        var mineAmount: Double?
        var createdAt: String?
        var expiresAt: Double?
    }
    struct RedPacketMineResult: Decodable {
        var redpackets: [RedPacketRecord]?
    }
    /* 红包封面（后台配的封面库） */
    struct RedPacketCoverRaw: Decodable, Identifiable {
        var id: String
        var name: String?
        var image: String?
        var thumb: String?
        var color: String?
    }
    struct RedPacketCoversResult: Decodable {
        var covers: [RedPacketCoverRaw]?
        var defaultId: String?
        var mine: String?
    }
    struct RedPacketCoverPick: Decodable {
        var coverId: String?
        var name: String?
    }
    /* 常见问题（内容来自后台客服中心里配的问答） */
    struct FAQPayload: Decodable {
        var title: String?
        var searchHint: String?
        var categories: [SupportCategory]?
        var hot: [SupportItem]?
    }
    /* 账户升级服务：等级 / 额度 / 还差哪一步 */
    struct WalletLevelStep: Decodable {
        var key: String?
        var name: String?
        var done: Bool?
        var hint: String?
    }
    struct WalletLevelRow: Decodable {
        var level: Int?
        var name: String?
        var single: Double?
        var day: Double?
        var current: Bool?
        var done: Bool?
    }
    struct WalletLevel: Decodable {
        var level: Int?
        var levelName: String?
        var tip: String?
        var single: Double?
        var day: Double?
        var receive: Double?
        var usedToday: Double?
        var leftToday: Double?
        var realName: Bool?
        var bankCount: Int?
        var upgradedAt: String?
        var levels: [WalletLevelRow]?
        var steps: [WalletLevelStep]?
    }
    struct WalletUpgradeResult: Decodable {
        var level: Int?
        var levelName: String?
        var single: Double?
        var day: Double?
    }
    /* 经营账户（收款记录 / 经营设置 / 提现到零钱 / 开票信息） */
    struct BizRecordRaw: Decodable, Identifiable {
        var id: String
        var kind: String?
        var amount: Double?
        var fromName: String?
        var fromId: String?
        var method: String?
        var note: String?
        var orderNo: String?
        var status: String?
        var settled: Bool?
        var createdAt: String?
    }
    struct BizInvoiceRaw: Decodable, Identifiable {
        var id: String
        var amount: Double?
        var status: String?
        var title: String?
        var taxNo: String?
        var kind: String?
        var note: String?
        var createdAt: String?
        var handledAt: String?
    }
    struct BizSettingsRaw: Decodable {
        var arrival: String?
        var notify: Bool?
        var autoWithdraw: Bool?
        var settle: String?
        var feeRate: Double?
        var shopName: String?
        var remark: String?
    }
    struct BizInvoiceInfoRaw: Decodable {
        var title: String?
        var taxNo: String?
        var address: String?
        var phone: String?
        var bankName: String?
        var bankAccount: String?
    }
    struct BizTotals: Decodable {
        var today: Double?
        var month: Double?
        var all: Double?
        var count: Int?
        var withdrawn: Double?
    }
    struct BizPayload: Decodable {
        var enabled: Bool?
        var balance: Double?
        var settings: BizSettingsRaw?
        var invoice: BizInvoiceInfoRaw?
        var records: [BizRecordRaw]?
        var invoices: [BizInvoiceRaw]?
        var totals: BizTotals?
        var invoiceReady: Bool?
    }
    struct BizWithdrawResult: Decodable {
        var balance: Double?
        var bizBalance: Double?
        var amount: Double?
    }
    /* 身份信息（钱包 → 身份信息） */
    struct IdentityInfo: Decodable {
        var verified: Bool?
        var realName: String?
        var idMask: String?
        var verifiedAt: String?
        var idValid: String?
        var occupation: String?
        var address: String?
        var level: Int?
        var levelName: String?
        var bankCount: Int?
    }
    /* 支付设置（钱包 → 支付设置） */
    struct AutoDebit: Decodable, Identifiable {
        var id: String
        var name: String?
        var amount: Double?
        var cycle: String?
        var createdAt: String?
    }
    struct PaySettings: Decodable {
        var hasPayPassword: Bool?
        var noPin: Bool?
        var noPinLimit: Double?
        var payMethod: String?
        var autoDebits: [AutoDebit]?
        var payPasswordUpdatedAt: String?
    }
    struct SimpleOK: Decodable { var saved: Bool? }

    func identity() async throws -> IdentityInfo {
        try await get("/api/me/identity", as: IdentityInfo.self)
    }
    func saveIdentity(idValid: String, occupation: String, address: String) async {
        let _: SimpleOK? = try? await post("/api/me/identity",
            ["idValid": idValid, "occupation": occupation, "address": address], as: SimpleOK.self)
    }
    func paySettings() async throws -> PaySettings {
        try await get("/api/me/paysettings", as: PaySettings.self)
    }

    /* 支付分（钱包 → 支付分）：分数 + 三个维度 + 免押服务 + 分值变化 */
    struct PayScoreDim: Decodable, Identifiable {
        var key: String
        var name: String
        var value: Double
        var desc: String?
        var tip: String?
        var id: String { key }
    }
    struct PayScoreService: Decodable, Identifiable {
        var id: String
        var name: String
        var desc: String?
        var need: Double?
        var ok: Bool?
        var gap: Double?
    }
    struct PayScoreHistory: Decodable, Identifiable {
        var at: String
        var text: String
        var delta: Double
        var id: String { at + text + String(delta) }
    }
    struct PayScore: Decodable {
        var score: Double
        var level: String
        var min: Double
        var max: Double
        var dims: [PayScoreDim]?
        var services: [PayScoreService]?
        var history: [PayScoreHistory]?
        var note: String?
    }
    func payScore() async throws -> PayScore {
        try await get("/api/me/payscore", as: PayScore.self)
    }

    /* 青少年模式（设置 → 青少年模式）：开关要 4 位密码，开了按勾选限制功能 */
    struct TeenStatus: Decodable {
        var enabled: Bool?
        var hasPin: Bool?
        var scopes: [String: Int]?
        var guardianPhone: String?
        var setAt: String?
    }
    private struct TeenPayload: Decodable { var teen: TeenStatus? }

    func teen() async throws -> TeenStatus {
        let p: TeenPayload = try await get("/api/me/teen", as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func teenSetup(pin: String) async throws -> TeenStatus {
        let p: TeenPayload = try await post("/api/me/teen/setup", ["pin": pin], as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func teenSet(pin: String, enabled: Bool?, scopes: [String: Int]?, guardianPhone: String?) async throws -> TeenStatus {
        var body: [String: Any] = ["pin": pin]
        if let e = enabled { body["enabled"] = e }
        if let s = scopes { body["scopes"] = s }
        if let g = guardianPhone { body["guardianPhone"] = g }
        let p: TeenPayload = try await post("/api/me/teen/set", body, as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func savePaySettings(noPin: Bool, noPinLimit: Double, payMethod: String) async {
        let _: SimpleOK? = try? await post("/api/me/paysettings",
            ["noPin": noPin, "noPinLimit": noPinLimit, "payMethod": payMethod], as: SimpleOK.self)
    }
    func cancelAutoDebit(_ id: String) async {
        let _: SimpleOK? = try? await post("/api/me/paysettings", ["cancelAutoDebit": id], as: SimpleOK.self)
    }

    /* 我的收藏（微信「我 → 收藏」那一页） */
    struct FavoriteItem: Decodable, Identifiable {
        var id: String
        var kind: String?
        var content: String?
        var createdAt: String?
        var chatId: String?
        var fromName: String?
    }
    private struct FavoritesPayload: Decodable { var favorites: [FavoriteItem]? }

    func favorites() async -> [FavoriteItem] {
        let p: FavoritesPayload? = try? await get("/api/favorites", as: FavoritesPayload.self)
        return p?.favorites ?? []
    }

    func deleteFavorite(_ id: String) async {
        _ = try? await request("DELETE", "/api/favorites/" + id)
    }
    struct BizInvoiceResult: Decodable {
        var invoice: BizInvoiceRaw?
        var invoices: [BizInvoiceRaw]?
    }

    func biz() async throws -> BizPayload {
        try await get("/api/biz", as: BizPayload.self)
    }
    func bizSave(enabled: Bool, arrival: String, notify: Bool, autoWithdraw: Bool,
                 shopName: String, remark: String) async throws {
        let _: BizSettingsRaw = try await post("/api/biz/settings", [
            "enabled": enabled, "arrival": arrival, "notify": notify,
            "autoWithdraw": autoWithdraw, "shopName": shopName, "remark": remark
        ], as: BizSettingsRaw.self)
    }
    func bizSaveInvoice(title: String, taxNo: String, address: String, phone: String,
                        bankName: String, bankAccount: String) async throws {
        let _: BizInvoiceInfoRaw = try await post("/api/biz/invoice", [
            "title": title, "taxNo": taxNo, "address": address, "phone": phone,
            "bankName": bankName, "bankAccount": bankAccount
        ], as: BizInvoiceInfoRaw.self)
    }
    func bizApplyInvoice(amount: Double, kind: String, note: String) async throws -> [BizInvoiceRaw] {
        let r: BizInvoiceResult = try await post("/api/biz/invoice/apply",
            ["amount": amount, "kind": kind, "note": note], as: BizInvoiceResult.self)
        return r.invoices ?? []
    }
    func bizWithdraw(amount: Double, all: Bool, password: String, face: Bool) async throws -> BizWithdrawResult {
        try await post("/api/biz/withdraw",
            ["amount": amount, "all": all, "password": password, "face": face], as: BizWithdrawResult.self)
    }

    /// 常见问题（独立页面用）
    func faq() async throws -> FAQPayload {
        try await get("/api/faq", as: FAQPayload.self)
    }

    /// 我的账户等级 + 额度 + 还差哪几步
    func walletLevel() async throws -> WalletLevel {
        try await get("/api/me/wallet", as: WalletLevel.self)
    }

    /// 升级账户（服务器会检查实名 + 绑卡）
    func walletUpgrade() async throws -> WalletUpgradeResult {
        try await post("/api/me/wallet-upgrade", [:], as: WalletUpgradeResult.self)
    }

    /// 发红包：单聊只能 1 个；群聊传 count(1~100) 和 type（lucky 拼手气 / normal 普通）
    func sendRedPacket(chatId: String, amount: Double, count: Int, type: String,
                       note: String, password: String = "", face: Bool = false,
                       coverId: String = "") async throws -> RedPacketSendResult {
        try await post("/api/pay/redpacket", [
            "chatId": chatId, "amount": amount, "count": count, "type": type,
            "note": note, "password": password, "face": face, "coverId": coverId,
            /* 幂等键：超时重发 / 连点，服务端只扣一次钱 */
            "requestId": UUID().uuidString
        ], as: RedPacketSendResult.self)
    }

    /// 红包封面列表 + 我自己选的那张
    func redPacketCovers() async throws -> (covers: [RedPacketCoverRaw], defaultId: String, mine: String) {
        let r: RedPacketCoversResult = try await get("/api/redpacket/covers", as: RedPacketCoversResult.self)
        return (r.covers ?? [], r.defaultId ?? "", r.mine ?? "")
    }

    /// 选一张我自己的红包封面
    func chooseRedPacketCover(id: String) async throws {
        let _: RedPacketCoverPick = try await post("/api/redpacket/cover", ["id": id], as: RedPacketCoverPick.self)
    }

    /// 拆红包：返回这次抢到多少、余额、红包最新状态
    func claimRedPacket(id: String) async throws -> RedPacketClaimResult {
        try await post("/api/redpackets/\(id)/claim", [:], as: RedPacketClaimResult.self)
    }

    /// 红包详情：谁抢了多少、手气最佳
    func redPacketDetail(id: String) async throws -> RedPacketRaw {
        let payload: RedPacketDetailResult = try await get("/api/redpackets/\(id)", as: RedPacketDetailResult.self)
        return payload.redpacket
    }

    /// 我收到 / 我发出的红包记录
    func myRedPackets() async throws -> [RedPacketRecord] {
        let payload: RedPacketMineResult = try await get("/api/redpackets/mine", as: RedPacketMineResult.self)
        return payload.redpackets ?? []
    }

    /* ------------------------------------------------ 客服中心（腾讯/微信那套） ---------------
       常见问题（后台配）+ 在线客服（转人工 = 和「在线客服」开一个会话）+ 我的工单
       配置全在后台「客服中心」页，改完 App 里立刻生效，不用装包。 */
    struct SupportItem: Decodable, Identifiable {
        var q: String
        var a: String
        var id: String { q }
    }
    struct SupportCategory: Decodable, Identifiable {
        var id: String
        var title: String
        var icon: String?
        var items: [SupportItem]?
    }
    struct SupportAgent: Decodable {
        var id: String
        var nickname: String?
        var avatar: String?
    }
    struct SupportTicket: Decodable, Identifiable {
        var id: String
        var category: String?
        var title: String?
        var content: String?
        var status: String?
        var reply: String?
        var createdAt: String?
        var repliedAt: String?
        var doneAt: String?
    }
    struct SupportPayload: Decodable {
        var title: String?
        var searchHint: String?
        var human: Int?              // 服务器下发 1/0
        var ticketOn: Int?
        var phone: String?
        var email: String?
        var workTime: String?
        var greet: String?
        var ticketHint: String?
        var categories: [SupportCategory]?
        var agent: SupportAgent?
        var tickets: [SupportTicket]?
    }
    struct SupportHuman: Decodable {
        var chatId: String
        var agent: SupportAgent?
    }
    struct SupportTicketResult: Decodable {
        var ticket: SupportTicket?
        var tickets: [SupportTicket]?
    }

    func support() async throws -> SupportPayload {
        try await get("/api/support", as: SupportPayload.self)
    }

    /// 转人工：和「在线客服」开一个会话（已有就用原来那个），返回会话 id
    func supportHuman() async throws -> SupportHuman {
        try await post("/api/support/human", [:], as: SupportHuman.self)
    }

    /// 提交问题 → 生成一张工单（后台「客服中心 → 工单」里能看到）
    func supportTicket(category: String, content: String, contact: String = "") async throws -> [SupportTicket] {
        let payload: SupportTicketResult = try await post("/api/support/ticket",
            ["category": category, "content": content, "contact": contact],
            as: SupportTicketResult.self)
        return payload.tickets ?? []
    }

    struct LiveStart: Decodable { var sessionId: String; var joined: Bool? }
    struct LiveMember: Decodable {
        var userId: String
        var name: String?
        var avatar: String?
        var lat: Double?
        var lng: Double?
        var at: Double?
    }
    struct LiveStatePayload: Decodable {
        var sessionId: String
        var chatId: String?
        var fromId: String?
        var members: [LiveMember]
    }

    func liveStart(chatId: String, lat: Double? = nil, lng: Double? = nil) async -> (sessionId: String, joined: Bool)? {
        var body: [String: Any] = ["chatId": chatId]
        if let lat = lat, let lng = lng { body["lat"] = lat; body["lng"] = lng }
        guard let r: LiveStart = try? await post("/api/live/start", body, as: LiveStart.self) else { return nil }
        return (r.sessionId, r.joined ?? false)
    }

    func livePos(sessionId: String, lat: Double, lng: Double) async {
        _ = try? await request("POST", "/api/live/pos",
                               body: ["sessionId": sessionId, "lat": lat, "lng": lng])
    }

    func liveState(sessionId: String) async -> LiveStatePayload? {
        try? await get("/api/live/\(sessionId)/state", as: LiveStatePayload.self)
    }

    func liveStop(sessionId: String) async {
        _ = try? await request("POST", "/api/live/stop", body: ["sessionId": sessionId])
    }

    /// 修改登录密码：要验当前密码，成功后服务器把其他设备踢下线
    func changePassword(current: String, new: String) async throws {
        _ = try await request("POST", "/api/me/password",
                              body: ["currentPassword": current, "newPassword": new])
    }

    /// 退出其他设备（微信「账号与安全 → 登录设备管理 → 退出其他设备」）
    func logoutOtherDevices() async -> String? {
        do {
            _ = try await request("POST", "/api/me/logout-others", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "操作失败"
        }
    }

    /* ---------------- 登录设备管理 ---------------- */

    /// 一台登录过的设备（服务端 /api/devices 下发）
    struct LoginDevice: Decodable, Identifiable, Hashable {
        var id: String
        /// 设备名（「张三的 iPhone」）——是百分号编码过的，显示前用 removingPercentEncoding 解
        var name: String?
        /// 老记录留下的那行 UA 描述（「Safari · iOS」）
        var device: String?
        /// 机型标识：iPhone17,1
        var model: String?
        /// 系统：iOS 19.1 / HarmonyOS 5.0
        var os: String?
        var ip: String?
        /// 最后登录时间（毫秒时间戳）。
        /// ⚠ 服务端老版本给的是 ISO 字符串（"2026-10-10T07:52:56.526Z"），
        /// 以前这里只有 Double，字符串解不出来 → **整个 /api/devices 响应解不出来**
        /// → 页面显示「还没有设备记录」（用户反馈「设备那三条一条都没落地」就是这个）。
        var at: Double?
        /// 是不是当前这台
        var current: Bool?

        private enum CodingKeys: String, CodingKey { case id, name, device, model, os, ip, at, current }

        /// 容错解码：数字 / ISO 字符串都收（少一条字段也不会把整页带崩）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            device = try? c.decodeIfPresent(String.self, forKey: .device)
            model = try? c.decodeIfPresent(String.self, forKey: .model)
            os = try? c.decodeIfPresent(String.self, forKey: .os)
            ip = try? c.decodeIfPresent(String.self, forKey: .ip)
            current = try? c.decodeIfPresent(Bool.self, forKey: .current)
            if let n = try? c.decodeIfPresent(Double.self, forKey: .at) {
                at = n
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .at) {
                at = LoginDevice.msOf(s)
            } else {
                at = nil
            }
        }

        /// 「2026-10-10T07:52:56.526Z」→ 毫秒时间戳；解不出来给 0
        static func msOf(_ s: String) -> Double {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
            return 0
        }
    }

    /// 登录设备管理：我登录过的设备（设备名 + 系统 + 最后登录时间 + 本机标记）
    func devices() async -> [LoginDevice] {
        struct Payload: Decodable { var devices: [LoginDevice]? }
        guard let p: Payload = try? await get("/api/devices", as: Payload.self) else { return [] }
        return p.devices ?? []
    }

    /// 音乐曲库（后台「音乐（听一听）」里传上去的歌；App 的「听一听」那一页 + 发音乐卡片都用它）
    func musicTracks() async -> [MusicTrack] {
        struct Payload: Decodable { var tracks: [MusicTrack]? }
        guard let p: Payload = try? await get("/api/music", as: Payload.self) else { return [] }
        return p.tracks ?? []
    }

    /// 小程序 / 小游戏（后台「小程序 / 小游戏」页里加的那些）
    /// kind 传 "game" 就只要小游戏（游戏页用）
    func miniApps(kind: String = "") async -> [MiniApp] {
        struct Payload: Decodable { var items: [MiniApp]? }
        let path = kind.isEmpty ? "/api/miniapps" : "/api/miniapps?kind=\(kind)"
        guard let p: Payload = try? await get(path, as: Payload.self) else { return [] }
        return p.items ?? []
    }

    /// 删掉某台登录设备（登录设备管理 → 编辑 → 删除；当前这台服务器不给删）
    func removeDevice(id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/devices/remove", body: ["id": id])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    /* ---------------------------------------------------------- 推送通知（苹果 APNs） */

    /// 把苹果给的 device token 交给服务器：手机没连实时通道时它就用这个推通知
    func registerPushToken(_ token: String, sandbox: Bool) async {
        _ = try? await request("POST", "/api/push/register", body: [
            "token": token,
            "platform": "ios",
            "env": sandbox ? "sandbox" : "prod",
            "bundleId": Bundle.main.bundleIdentifier ?? ""
        ])
    }

    /// 退出登录：这台手机别再收这个账号的推送
    func unregisterPushToken(_ token: String) async {
        guard !token.isEmpty else { return }
        _ = try? await request("POST", "/api/push/unregister", body: ["token": token])
    }

    /// 把手机上的通知设置报给服务器（允许通知没、标记有没有开）——桌面图标没数字时用来定位
    func reportPushSettings(status: String, badge: Bool, alert: Bool, sound: Bool,
                            token: String, sandbox: Bool) async {
        _ = try? await request("POST", "/api/push/settings", body: [
            "status": status, "badge": badge, "alert": alert, "sound": sound,
            "token": token, "env": sandbox ? "sandbox" : "prod"
        ])
    }

    struct PushStatus: Decodable {
        var configured: Bool?
        var enabled: Bool?
        var sandbox: Bool?
        var devices: Int?
    }

    /// 自检：服务器那边推送配好了没、这台手机登记过没（「关于」页显示用）
    func pushStatus() async -> PushStatus? {
        try? await get("/api/push/status", as: PushStatus.self)
    }

    /// 拿一对一会话（转账需要 chatId）；不是好友会报错
    func directChat(userId: String) async throws -> Chat {
        let payload: ChatPayload = try await post("/api/chats/direct", ["userId": userId], as: ChatPayload.self)
        guard let chat = payload.chat else { throw APIError.message("会话创建失败") }
        return chat
    }

    func messages(chatId: String, limit: Int = 40, before: Int? = nil) async throws -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        var path = "/api/chats/\(chatId)/messages?limit=\(limit)"
        if let before = before { path += "&before=\(before)" }
        let payload: MessagesPayload = try await get(path, as: MessagesPayload.self)
        return (payload.chat, payload.messages, payload.hasMore ?? false)
    }

    func send(chatId: String, text: String) async throws -> Message? {
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     ["kind": "text", "content": text],
                                                     as: MessagePayload.self)
        return payload.message
    }

    /* 群聊信息页：群成员资料（顺序和九宫格群头像一致，群主排第一） */
    func chatMembers(chatId: String) async throws -> (members: [User], ownerId: String, createdAt: String) {
        let p: ChatMembersPayload = try await get("/api/chats/\(chatId)/members", as: ChatMembersPayload.self)
        return (p.members ?? [], p.ownerId ?? "", p.createdAt ?? "")
    }

    /// 群昵称（微信「设置群昵称」/「我在本群的昵称」）。
    /// userId 传空 = 改自己的；改别人的只有群主能成。alias 传空 = 取消群昵称。
    @discardableResult
    func setGroupAlias(chatId: String, userId: String = "", alias: String) async -> Bool {
        struct P: Decodable { var alias: String? }
        var body: [String: Any] = ["alias": alias]
        if !userId.isEmpty { body["userId"] = userId }
        return (try? await post("/api/chats/\(chatId)/alias", body, as: P.self)) != nil
    }

    /* ---------------- 成长（QQ 等级那套：活跃天 / 等级） ---------------- */

    func growthMe() async throws -> GrowthMe {
        struct P: Decodable { var growth: GrowthMe }
        let p: P = try await get("/api/growth/me", as: P.self)
        return p.growth
    }

    /// 上报「这段用了我多久」（秒）——服务端按天结算活跃天
    func growthPing(seconds: Int) async throws -> GrowthMe {
        struct P: Decodable { var growth: GrowthMe }
        let p: P = try await post("/api/growth/ping", ["seconds": seconds], as: P.self)
        return p.growth
    }

    func growthRank() async throws -> (rows: [GrowthRankRow], me: GrowthRankRow?) {
        struct P: Decodable { var rank: [GrowthRankRow]?; var me: GrowthRankRow? }
        let p: P = try await get("/api/growth/rank", as: P.self)
        return (p.rank ?? [], p.me)
    }

    /* ---------------------------------------------------------- 会员（我们的） */

    /// 会员中心要的全部东西：档位 + 价格 + 权益文案 + 我的状态 + 开通记录
    func memberInfo() async throws -> MemberInfo {
        struct P: Decodable { var membership: MemberInfo? }
        let p: P = try await get("/api/membership", as: P.self)
        return p.membership ?? MemberInfo()
    }

    /// 开通 / 续费：走零钱扣款，要支付密码（没设密码就传空）
    func memberOpen(tierId: String, months: Int, payPassword: String) async -> (MemberMe?, Double?, String?) {
        struct P: Decodable { var membership: MemberMe?; var balance: Double?; var paid: Double? }
        do {
            let p: P = try await post("/api/membership/open",
                                      ["tierId": tierId, "months": months, "payPassword": payPassword],
                                      as: P.self)
            return (p.membership, p.balance, nil)
        } catch {
            return (nil, nil, (error as? APIError)?.errorDescription ?? "开通失败，再试一次")
        }
    }

    /// 自动续费开关
    func memberAuto(_ on: Bool) async {
        struct P: Decodable { var membership: MemberMe? }
        _ = try? await post("/api/membership/auto", ["on": on], as: P.self)
    }

    /// 兑换码
    func memberRedeem(_ code: String) async -> (String?, String) {
        struct P: Decodable { var membership: MemberMe?; var tier: String?; var days: Int? }
        do {
            let p: P = try await post("/api/membership/redeem", ["code": code], as: P.self)
            return (p.tier, "兑换成功：" + (p.tier ?? "会员") + " " + String(p.days ?? 0) + " 天")
        } catch {
            return (nil, (error as? APIError)?.errorDescription ?? "兑换失败")
        }
    }

    /// 扫一扫 → 翻译：把识别到的文字发给服务器，用后台配的大模型翻
    func scanTranslate(_ text: String, to: String = "中文") async -> String? {
        struct P: Decodable { var text: String? }
        guard let p: P = try? await post("/api/scan/translate", ["text": text, "to": to], as: P.self) else {
            return nil
        }
        return p.text
    }

    /* 置顶聊天 / 取消置顶（群聊信息页那一行） */
    @discardableResult
    func setPinned(chatId: String, pinned: Bool) async -> Bool {
        let p: PinPayload? = try? await post("/api/chats/\(chatId)/pin",
                                             ["pinned": pinned], as: PinPayload.self)
        return p?.pinned ?? pinned
    }

    /* ---------------- 群管理（对应功能清单里的群名称/群公告/群屏蔽/踢人/解散）---------------- */

    /// 改群名称 / 群公告（只有群主）。返回错误文案，nil = 成功
    @discardableResult
    func updateChatInfo(chatId: String, name: String, announce: String) async -> String? {
        do {
            let _: ChatInfoPayload = try await patch("/api/chats/\(chatId)/info",
                                                     ["name": name, "announce": announce], as: ChatInfoPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "保存失败" }
    }

    /// 消息免打扰（群屏蔽）：每个人自己设
    @discardableResult
    func setMuted(chatId: String, muted: Bool) async -> Bool {
        let p: MutePayload? = try? await post("/api/chats/\(chatId)/mute", ["muted": muted], as: MutePayload.self)
        return p?.muted ?? muted
    }

    /// 群主把某个成员移出群聊
    @discardableResult
    func kickMember(chatId: String, userId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/kick",
                                                       ["userId": userId], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "移出失败" }
    }

    /// 群二维码：拿到邀请码和二维码 SVG
    /// 群加人：把选中的好友拉进群（群里任何成员都能拉，群上限 500）
    func addGroupMembers(chatId: String, userIds: [String]) async -> (added: [String], memberCount: Int, error: String?) {
        struct Payload: Decodable {
            var memberCount: Int?
            var added: [Row]?
            struct Row: Decodable { var id: String?; var name: String? }
        }
        do {
            let p: Payload = try await post("/api/chats/\(chatId)/add-members",
                                            ["userIds": userIds], as: Payload.self)
            let names = (p.added ?? []).compactMap { $0.name }
            return (names, p.memberCount ?? 0, nil)
        } catch {
            return ([], 0, (error as? APIError)?.errorDescription ?? "加人失败")
        }
    }

    /// 我的二维码（每个人一张，扫了能加好友）
    /* ---------------- 隐私 / 消息通知 ---------------- */
    func privacy() async -> PrivacySettings {
        struct Payload: Decodable {
            var privacy: Raw?; var notify: Raw?
            struct Raw: Decodable {
                var needVerify: Bool?; var strangerMoments: Bool?
                var addByWx: Bool?; var addByPhone: Bool?; var addByGroup: Bool?; var addByQR: Bool?
                /// 朋友圈可见范围：3d / 6m / all
                var momentsRange: String?
            }
        }
        guard let p: Payload = try? await get("/api/me/privacy", as: Payload.self), let r = p.privacy
        else { return PrivacySettings() }
        var s = PrivacySettings()
        s.needVerify = r.needVerify ?? true
        s.strangerMoments = r.strangerMoments ?? false
        s.addByWx = r.addByWx ?? true
        s.addByPhone = r.addByPhone ?? true
        s.addByGroup = r.addByGroup ?? true
        s.addByQR = r.addByQR ?? true
        s.momentsRange = (r.momentsRange == "3d" || r.momentsRange == "6m") ? r.momentsRange! : "all"
        return s
    }

    func setPrivacy(_ key: String, _ value: Bool) async {
        _ = try? await request("PATCH", "/api/me/privacy", body: [key: value])
    }

    /// 隐私设置里那种**不是开关**的项（比如朋友圈可见范围 3d / 6m / all）
    func setPrivacyText(_ key: String, _ value: String) async {
        _ = try? await request("PATCH", "/api/me/privacy", body: [key: value])
    }

    func notifySettings() async -> NotifySettings {
        struct Payload: Decodable {
            var notify: Raw?
            struct Raw: Decodable {
                var on: Bool?; var sound: Bool?; var vibrate: Bool?; var showDetail: Bool?
                var muteStart: String?; var muteEnd: String?
            }
        }
        guard let p: Payload = try? await get("/api/me/privacy", as: Payload.self), let r = p.notify
        else { return NotifySettings() }
        var s = NotifySettings()
        s.on = r.on ?? true
        s.sound = r.sound ?? true
        s.vibrate = r.vibrate ?? true
        s.showDetail = r.showDetail ?? true
        s.muteStart = r.muteStart ?? ""
        s.muteEnd = r.muteEnd ?? ""
        return s
    }

    func setNotify(_ fields: [String: Any]) async {
        _ = try? await request("PATCH", "/api/me/notify", body: fields)
    }

    func myQRCode() async -> (code: String, url: String, rows: [String], user: User?) {
        struct MyQRPayload: Decodable {
            var code: String?; var url: String?; var rows: [String]?; var user: User?
        }
        guard let p: MyQRPayload = try? await get("/api/me/qrcode", as: MyQRPayload.self)
        else { return ("", "", [], nil) }
        return (p.code ?? "", p.url ?? "", p.rows ?? [], p.user)
    }

    /// 扫到别人的个人二维码：**只解析出这是谁**（不直接加好友）——微信是跳资料页再点「添加到通讯录」
    func userByCode(_ code: String) async -> (user: User?, relation: String, message: String) {
        struct ByCodePayload: Decodable { var user: User?; var relation: String? }
        do {
            let p: ByCodePayload = try await post("/api/user-by-code", ["code": code], as: ByCodePayload.self)
            return (p.user, p.relation ?? "none", "")
        } catch {
            return (nil, "", (error as? APIError)?.errorDescription ?? "这个二维码无效或者过期了")
        }
    }

    /// 扫到别人的个人二维码：加好友。返回 (提示文案, 对方)
    func addByCode(_ code: String) async -> (message: String, user: User?) {
        struct AddPayload: Decodable {
            var sent: Bool?; var already: Bool?; var pending: Bool?; var accepted: Bool?; var user: User?
        }
        do {
            let p: AddPayload = try await post("/api/add-by-code", ["code": code], as: AddPayload.self)
            let msg = p.already == true ? "你们已经是好友了"
                : (p.pending == true ? "已经发过申请了，等对方通过"
                   : (p.accepted == true ? "对方之前加过你，现在已经是好友" : "好友申请已发出"))
            return (msg, p.user)
        } catch {
            return ((error as? APIError)?.errorDescription ?? "加好友失败", nil)
        }
    }

    func groupInvite(chatId: String) async -> (code: String, url: String, rows: [String]) {
        struct InvitePayload: Decodable { var code: String?; var url: String?; var svg: String?; var rows: [String]? }
        guard let p: InvitePayload = try? await post("/api/chats/\(chatId)/invite", [:], as: InvitePayload.self)
        else { return ("", "", []) }
        return (p.code ?? "", p.url ?? "", p.rows ?? [])
    }

    /// 扫码进群：成功返回这个会话（调用方拿到就能直接跳进群聊），失败返回错误文案
    func joinByInvite(code: String) async -> (chat: Chat?, error: String?) {
        struct JoinPayload: Decodable {
            var joined: Bool?
            var already: Bool?
            var chat: Chat?
        }
        do {
            let p: JoinPayload = try await post("/api/join", ["code": code], as: JoinPayload.self)
            return (p.chat, nil)
        } catch {
            return (nil, (error as? APIError)?.errorDescription ?? "进群失败")
        }
    }

    /// 全员禁言（群主）
    @discardableResult
    func setMuteAll(chatId: String, on: Bool) async -> String? {
        do {
            struct MuteAllPayload: Decodable { var muteAll: Bool? }
            let _: MuteAllPayload = try await post("/api/chats/\(chatId)/muteall", ["on": on], as: MuteAllPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "设置失败" }
    }

    /// 禁言 / 取消禁言某个群成员（群主）
    @discardableResult
    func setMemberMuted(chatId: String, userId: String, muted: Bool) async -> String? {
        do {
            _ = try await post("/api/chats/\(chatId)/mutemember",
                               ["userId": userId, "muted": muted], as: SendPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "设置失败" }
    }

    /// 退出群聊（群主退群会自动把群主交给下一个人）
    @discardableResult
    func leaveGroup(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/leave", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "退群失败" }
    }

    /// 解散群聊（只有群主）
    @discardableResult
    func dismissGroup(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/dismiss", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "解散失败" }
    }

    /// 清空聊天记录（只清自己这边）
    @discardableResult
    func clearChat(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/clear", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "清空失败" }
    }

    /// 查找聊天记录：在服务器上翻整个会话的历史
    func searchMessages(chatId: String, query: String) async -> [FoundMessage] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let p: SearchPayload = try? await get("/api/chats/\(chatId)/search?q=\(q)", as: SearchPayload.self)
        else { return [] }
        return p.messages
    }

    /* ---------------- 银行卡 ---------------- */

    func bankCards() async -> [BankCard] {
        let p: BankCardsPayload? = try? await get("/api/me/bankcards", as: BankCardsPayload.self)
        return p?.cards ?? []
    }

    struct BankInfo: Decodable, Identifiable, Hashable {
        var name: String
        var color: String?
        var short: String?
        var id: String { name }
    }
    private struct BankListPayload: Decodable { var banks: [BankInfo]? }

    /// 绑卡时能选的银行（名字 + 品牌色）
    func banks() async -> [BankInfo] {
        let p: BankListPayload? = try? await get("/api/banks", as: BankListPayload.self)
        return p?.banks ?? []
    }

    /// 改一张卡的「免密支付」开关
    func setBankCardNoPin(id: String, noPin: Bool) async {
        _ = try? await patch("/api/me/bankcards/" + id, ["noPin": noPin], as: [String: String].self)
    }

    @discardableResult
    func addBankCard(bank: String, number: String, holder: String,
                     idCard: String = "", phone: String = "", type: String = "") async -> String? {
        do {
            let _: BankCardsPayload = try await post("/api/me/bankcards",
                                                     ["bank": bank, "number": number, "holder": holder,
                                                      "idCard": idCard, "phone": phone, "type": type],
                                                     as: BankCardsPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "绑定失败" }
    }

    @discardableResult
    func deleteBankCard(id: String) async -> String? {
        do {
            _ = try await request("DELETE", "/api/me/bankcards/\(id)")
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "解绑失败" }
    }

    /* ---------------- 意见反馈 / 密码找回 ---------------- */

    @discardableResult
    func sendFeedback(content: String, contact: String,
                      category: String = "功能异常", images: [String] = []) async -> String? {
        do {
            let _: SendPayload = try await post("/api/feedback",
                                                ["content": content, "contact": contact,
                                                 "category": category, "images": images,
                                                 "platform": "iOS"],
                                                as: SendPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "提交失败" }
    }

    /// 我的反馈（微信「意见反馈」下面能看到自己提过的 + 官方回复）
    struct MyFeedback: Decodable, Identifiable, Hashable {
        var id: String
        var category: String?
        var content: String?
        var images: [String]?
        var createdAt: String?
        var status: String?
        var reply: String?
        var repliedAt: String?
    }
    private struct MyFeedbackPayload: Decodable { var rows: [MyFeedback]? }
    func myFeedback() async -> [MyFeedback] {
        guard let p: MyFeedbackPayload = try? await get("/api/feedback/mine", as: MyFeedbackPayload.self) else { return [] }
        return p.rows ?? []
    }

    /// 密码找回：手机号 + 验证码 + 新密码。
    /// 成功后返回这个账号的用户名（App 用用户名+新密码再登一次，就进 App 了）
    func resetPassword(phone: String, code: String, newPassword: String) async -> (username: String, error: String?) {
        do {
            let p: LoginPayload = try await post("/api/login/reset",
                                                 ["phone": phone, "code": code, "newPassword": newPassword],
                                                 as: LoginPayload.self)
            return (p.user?.username ?? "", nil)
        } catch { return ("", (error as? APIError)?.errorDescription ?? "重置失败") }
    }

    func markRead(chatId: String) async {
        _ = try? await request("POST", "/api/chats/\(chatId)/read", body: [:])
    }

    /* ---------------- 聊天记录导出 / 导入 ---------------- */

    /// 导出结果：文件名 + 格式 + 内容。
    /// json 是「可以再导入」的备份（payload），txt 是给人看的（text）。
    struct ChatDump {
        var fileName = "luchat-chat.json"
        var format = "json"
        var total = 0
        var chats = 0
        var text = ""
        /// json 格式时的原始对象，直接拿去导入
        var payload: Any? = nil
    }

    /// 导出聊天记录：chatId 传空就是全部
    func exportChats(chatId: String = "", format: String = "json") async throws -> ChatDump {
        var path = "/api/chats/export?format=" + format
        if !chatId.isEmpty { path += "&chatId=" + chatId }
        let any = try await request("GET", path)
        guard let dict = any as? [String: Any] else { throw APIError.message("导出失败") }
        var out = ChatDump()
        out.fileName = (dict["fileName"] as? String) ?? out.fileName
        out.format = (dict["format"] as? String) ?? format
        out.total = (dict["total"] as? Int) ?? 0
        out.chats = (dict["chats"] as? Int) ?? 0
        if out.format == "txt" {
            out.text = (dict["data"] as? String) ?? ""
        } else {
            out.payload = dict["data"]
        }
        return out
    }

    /// 把导出的 JSON 合回来（按消息 id 去重）
    func importChats(payload: Any) async throws -> (imported: Int, skipped: Int, chats: Int) {
        struct Out: Decodable { var imported: Int?; var skipped: Int?; var chats: Int? }
        let out: Out = try await post("/api/chats/import", ["payload": payload], as: Out.self)
        return (out.imported ?? 0, out.skipped ?? 0, out.chats ?? 0)
    }

    func markUnread(chatId: String) async {
        _ = try? await request("POST", "/api/chats/\(chatId)/unread", body: [:])
    }

    /// 清空聊天记录 + 从列表里移除（微信的「删除」）。返回错误文案，nil = 成功
    @discardableResult
    func deleteChat(chatId: String) async -> String? {
        await deleteChat(path: "/api/chats/\(chatId)?clear=1")
    }

    /// 不显示该聊天：只从自己的列表里移除，对方不受影响。返回错误文案，nil = 成功
    @discardableResult
    func hideChat(chatId: String) async -> String? {
        await deleteChat(path: "/api/chats/\(chatId)")
    }

    private func deleteChat(path: String) async -> String? {
        do {
            _ = try await request("DELETE", path)
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "操作失败"
        }
    }

    func openDirect(userId: String) async throws -> Chat? {
        let payload: ChatPayload = try await post("/api/chats/direct", ["userId": userId], as: ChatPayload.self)
        return payload.chat
    }

    func contacts() async throws -> [User] {
        let payload: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return payload.friends
    }

    func contactsFull() async throws -> (friends: [User], incoming: [User]) {
        let payload: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return (payload.friends, payload.incoming ?? [])
    }

    /// 「新的朋友」页要的全部东西：好友 / 别人加我的 / 我加别人的 / 刚通过的（显示「已添加」）
    func friendRequests() async throws -> (friends: [User], incoming: [User], outgoing: [User], added: [User]) {
        let p: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return (p.friends, p.incoming ?? [], p.outgoing ?? [], p.added ?? [])
    }

    private struct BadgeCountsPayload: Decodable { var friendRequests: Int?; var momentUnread: Int? }
    /// 红点数字（很轻的接口）：回到前台 / 定时兜底查一下，防止漏推送
    func badgeCounts() async -> (friendRequests: Int, momentUnread: Int)? {
        guard let p = try? await get("/api/badge-counts", as: BadgeCountsPayload.self) else { return nil }
        return (p.friendRequests ?? 0, p.momentUnread ?? 0)
    }

    /// 同意 / 拒绝好友申请。
    /// 传 requestId（「新的朋友」列表里本来就带着），或者 userId（对方名片上直接点同意 ——
    /// 以前得先拉一遍整份通讯录去找 requestId，点一下要等两次网络来回，所以才显得慢）。
    /// 返回 ok = 服务端认了；pending = 还剩几个待处理（老服务端不给这个字段，就保持客户端自己算的）。
    @discardableResult
    func respondFriend(requestId: String = "", userId: String = "",
                       accept: Bool) async -> (ok: Bool, pending: Int?) {
        struct RespondPayload: Decodable { var pending: Int? }
        var body: [String: Any] = ["accept": accept]
        if !requestId.isEmpty { body["requestId"] = requestId }
        if !userId.isEmpty { body["userId"] = userId }
        guard let p = try? await post("/api/friends/respond", body, as: RespondPayload.self) else {
            return (false, nil)
        }
        return (true, p.pending)
    }

    func createGroup(name: String, memberIds: [String]) async throws -> Chat? {
        let payload: ChatPayload = try await post("/api/chats/group",
                                                  ["name": name, "memberIds": memberIds],
                                                  as: ChatPayload.self)
        return payload.chat
    }

    /// 面对面建群（微信那套）：大家输入**同一个 4 位数字**就进同一个群，
    /// 数字 3 分钟内有效，每次有人进来重新计时。返回进/建好的那个群。
    func faceGroup(code: String) async throws -> Chat? {
        struct FacePayload: Decodable {
            var chat: Chat?
            var created: Bool?
            var joined: Bool?
            var memberCount: Int?
            var expiresIn: Int?
        }
        let payload: FacePayload = try await post("/api/chats/face", ["code": code], as: FacePayload.self)
        return payload.chat
    }

    func recharge(_ amount: Double) async throws -> Double {
        struct RechargePayload: Decodable { var balance: Double? }
        let payload: RechargePayload = try await post("/api/me/recharge",
                                                      ["amount": amount,
                                                       "requestId": UUID().uuidString],
                                                      as: RechargePayload.self)
        return payload.balance ?? 0
    }

    /// 收款：成功返回 nil，失败**返回原因**。
    /// ⚠ 以前这里是静默 `try?` —— 服务端说「已过期 / 不是给你的 / 已经收过了」时
    /// 客户端一个字都不提示，用户看到的就是「点了没反应」。现在把原因带回去。
    @discardableResult
    func claimTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/claim", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "收款失败，稍后再试"
        }
    }

    /// 付款方提醒对方收款（服务端真的会把提醒推给对方，1 分钟只能提醒一次）
    @discardableResult
    func remindTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/remind", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "提醒失败"
        }
    }

    /// 收款方「退还」：把钱原路退给付款方（微信转账详情里收款方那颗按钮）
    @discardableResult
    func refundTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/refund", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "退还失败"
        }
    }

    func favorites() async -> [[String: Any]] {
        guard let any = try? await request("GET", "/api/favorites"),
              let dict = any as? [String: Any],
              let list = dict["favorites"] as? [[String: Any]] else { return [] }
        return list
    }

    /// 收藏一条聊天内容（长按消息 → 收藏）
    @discardableResult
    func addFavorite(kind: String, content: String, title: String = "", from: String = "") async -> Bool {
        let ok = try? await request("POST", "/api/favorites", body: [
            "kind": kind, "content": content, "title": title, "from": from
        ])
        return ok != nil
    }

    /* ---------------- 实名认证 ---------------- */

    struct RealNameInfo: Hashable {
        var verified: Bool
        var realName: String
        var idMask: String
        var at: String
    }

    func realNameStatus() async -> RealNameInfo {
        guard let any = try? await request("GET", "/api/me/realname"),
              let d = any as? [String: Any] else {
            return RealNameInfo(verified: false, realName: "", idMask: "", at: "")
        }
        return RealNameInfo(verified: (d["verified"] as? Bool) ?? false,
                            realName: (d["realName"] as? String) ?? "",
                            idMask: (d["idMask"] as? String) ?? "",
                            at: (d["at"] as? String) ?? "")
    }

    /// 提交实名认证（服务端校验身份证号 + 一人一证）
    func submitRealName(name: String, idCard: String) async throws -> RealNameInfo {
        let any = try await request("POST", "/api/me/realname", body: ["realName": name, "idCard": idCard])
        let d = (any as? [String: Any]) ?? [:]
        return RealNameInfo(verified: (d["verified"] as? Bool) ?? true,
                            realName: (d["realName"] as? String) ?? name,
                            idMask: (d["idMask"] as? String) ?? "",
                            at: (d["at"] as? String) ?? "")
    }

    /* ---------------- 地区（省 / 市）· 换手机号 ---------------- */

    struct RegionRow: Decodable, Hashable {
        var p: String            // 省 / 直辖市
        var c: [String]          // 市
    }

    /// 省 / 市列表（地区选择用：和微信一样两个滚轮）。服务端内置，一次拉回。
    func regions() async -> [RegionRow] {
        guard let any = try? await request("GET", "/api/regions") else { return [] }
        let d = (any as? [String: Any]) ?? [:]
        return (try? decode(d["regions"] ?? [], as: [RegionRow].self)) ?? []
    }

    /// 换手机号第一步：给新号发验证码。没配短信通道时服务端回 devCode（本机/局域网直接显示）
    func phoneChangeCode(phone: String) async throws -> String? {
        let any = try await request("POST", "/api/me/phone/code", body: ["phone": phone])
        return (any as? [String: Any])?["devCode"] as? String
    }

    /// 换手机号第二步：提交新号 + 验证码（没配短信通道时改用登录密码验证）
    @discardableResult
    func changePhone(phone: String, code: String, password: String) async throws -> String {
        var body: [String: Any] = ["phone": phone, "code": code]
        if !password.isEmpty { body["password"] = password }
        let any = try await request("POST", "/api/me/phone", body: body)
        return ((any as? [String: Any])?["phone"] as? String) ?? ""
    }

    func changeBackground(_ path: String) async {
        await updateMe(["chatBackground": path])
    }

    func moments(limit: Int = 20, userId: String? = nil) async throws -> [Moment] {
        var path = "/api/moments?limit=\(limit)"
        if let userId = userId, !userId.isEmpty { path += "&userId=\(userId)" }
        let payload: MomentsPayload = try await get(path, as: MomentsPayload.self)
        return payload.moments
    }

    /// 朋友圈首页要的完整信息：列表 + 有没有新的（「发现」上的小红点）+ 还有没有更多
    ///（before = 上一页最后一条的时间，用来往下翻页）
    func momentsFeed(limit: Int = 20, before: String? = nil, beforeId: String? = nil, userId: String? = nil)
        async throws -> (moments: [Moment], unread: Int, total: Int, hasMore: Bool, range: String) {
        var path = "/api/moments?limit=\(limit)"
        if let before = before, !before.isEmpty { path += "&before=\(before)" }
        if let beforeId = beforeId, !beforeId.isEmpty { path += "&beforeId=\(beforeId)" }
        if let userId = userId, !userId.isEmpty { path += "&userId=\(userId)" }
        let payload: MomentsPayload = try await get(path, as: MomentsPayload.self)
        return (payload.moments, payload.unread ?? 0, payload.total ?? payload.moments.count,
                payload.hasMore ?? false, payload.range ?? "all")
    }

    /* ---------------------------------------------------------- 更多接口 */

    func plusPanel() async throws -> [PlusItem] {
        let payload: PlusPayload = try await get("/api/plus-panel", as: PlusPayload.self)
        return (payload.items ?? []).filter { $0.enabled != false }
    }

    func gifts() async throws -> [Gift] {
        let payload: GiftsPayload = try await get("/api/gifts", as: GiftsPayload.self)
        return payload.gifts ?? []
    }

    func stickerPacks() async throws -> [StickerPack] {
        let payload: StickersPayload = try await get("/api/stickers", as: StickersPayload.self)
        return payload.packs ?? []
    }

    /* ---------------------------------------------------------- 表情（微信「我 → 表情」） */

    /// 表情商店 + 我的表情一次拿全
    func stickerShop() async throws -> (shop: [StickerPack], mine: StickerMine) {
        let p: StickerShopPayload = try await get("/api/stickers", as: StickerShopPayload.self)
        return (p.packs ?? [], p.mine ?? StickerMine())
    }

    /// 添加表情包（商店里点「添加」）
    func addStickerPack(_ packId: String) async {
        _ = try? await request("POST", "/api/stickers/add", body: ["packId": packId])
    }

    /// 移除表情包（我的表情里点「移除」）
    func removeStickerPack(_ packId: String) async {
        _ = try? await request("POST", "/api/stickers/remove", body: ["packId": packId])
    }

    /// 添加单个表情（从相册选一张图上传后加进「我添加的表情」）
    func addSingleSticker(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/add", body: ["sticker": sticker])
    }

    func removeSingleSticker(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/remove", body: ["sticker": sticker])
    }

    /// 用过的表情记一笔（表情面板第一格「最近使用」）
    func markStickerUsed(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/recent", body: ["sticker": sticker])
    }

    func statusCategories() async throws -> [StatusCategory] {
        let payload: StatusesPayload = try await get("/api/statuses", as: StatusesPayload.self)
        return payload.categories ?? []
    }

    /// 发现页那几行（后台配的，网页版和 App 共用一份）
    func discover() async throws -> [DiscoverItem] {
        let payload: DiscoverPayload = try await get("/api/discover", as: DiscoverPayload.self)
        return payload.items.filter { $0.enabled != false }
    }

    /// 新闻（发现 → 星联世界）：source = qq / toutiao / sina / weibo / baidu
    /// 服务端多源聚合 + 5 分钟缓存；返回里还带一份频道列表（后台能加源，不用发版）
    func news(source: String, limit: Int = 40, offset: Int = 0) async throws -> NewsFeed {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
        return try await get("/api/news?source=" + s + "&limit=\(limit)&offset=\(offset)", as: NewsFeed.self)
    }

    /* ---------------- 公众号（我们自己的） ---------------- */

    /// 通讯录 → 公众号：所有号 + 我关注没有
    func oaList() async throws -> [OAAccount] {
        struct P: Decodable { var accounts: [OAAccount]? }
        let p: P = try await get("/api/oa/list", as: P.self)
        return p.accounts ?? []
    }

    /// 某个号的主页：资料 + 历史文章
    func oaAccount(id: String) async throws -> OAAccountPage {
        let s = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await get("/api/oa/account?id=" + s, as: OAAccountPage.self)
    }

    /// 文章详情（顺便让服务器把阅读数 +1）
    func oaArticle(id: String) async throws -> OAArticlePage {
        let s = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await get("/api/oa/article?id=" + s, as: OAArticlePage.self)
    }

    /// 订阅 / 取消订阅（订阅以后会话列表里就有这个号了）
    @discardableResult
    func oaFollow(accountId: String, follow: Bool) async throws -> Bool {
        struct P: Decodable { var following: Bool? }
        let p: P = try await post("/api/oa/follow", ["accountId": accountId, "follow": follow], as: P.self)
        return p.following ?? follow
    }

    /// 我页下面那几行（同样是后台配的）
    func mePage() async throws -> [DiscoverItem] {
        let payload: DiscoverPayload = try await get("/api/me-page", as: DiscoverPayload.self)
        return payload.items.filter { $0.enabled != false }
    }

    /// 服务页整页配置（后台「服务页」模块配的，网页版和 App 共用一份）
    func serviceConfig() async throws -> ServiceConfig {
        try await get("/api/service", as: ServiceConfig.self)
    }

    /// 钱包页整页配置（后台「钱包页」模块配的；零钱那一行的数值是现算的余额）
    func walletConfig() async throws -> WalletConfig {
        try await get("/api/wallet", as: WalletConfig.self)
    }

    /// 安全分（微信「支付分」那套：550~850 · 身份特质 / 支付行为 / 守约历史）
    func securityScore() async throws -> CreditScore {
        try await get("/api/me/score", as: CreditScorePayload.self).score
    }

    /// 账单：这个人所有的转账（wallet 页右上角「账单」用），可按月筛
    func bills(month: String? = nil) async throws -> BillsPayload {
        var path = "/api/bills"
        if let m = month, !m.isEmpty {
            path += "?month=" + m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        }
        return try await get(path, as: BillsPayload.self)
    }

    /// 零钱页（钱包页点「零钱」进来）
    func balancePage() async throws -> BalancePageConfig {
        try await get("/api/balance-page", as: BalancePageConfig.self)
    }

    /// 设置/清除「状态」（对应后台配的那些状态）
    /// 「说点什么」那句可选文案（≤30 字）一起带上，和微信一样分两层存
    func setMood(_ item: StatusItem?, caption: String = "", fallbackColor: String = "") async {
        if let item = item {
            let label = (item.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
            let own = MoodColor.clean(item.color)
            var c1 = own
            if c1.isEmpty { c1 = MoodColor.clean(fallbackColor) }
            var c2 = MoodColor.clean(item.color2)
            if c2.isEmpty { c2 = MoodColor.shift(c1, to: true) }
            await updateMe([
                "moodLabel": label,
                "moodCaption": note,
                "moodText": note.isEmpty ? label : note,
                "moodIcon": item.icon ?? "",
                "moodColor": c1,
                "moodColor2": c2
            ])
        } else {
            await updateMe(["moodText": "", "moodLabel": "", "moodCaption": "",
                            "moodIcon": "", "moodColor": "", "moodColor2": ""])
        }
    }

    /// 我的状态详情：还剩几个小时、谁看过（微信里点自己的状态看到的就是这些）
    func myStatus() async throws -> MyStatus {
        try await get("/api/me/status", as: MyStatus.self)
    }

    /// 结束（清除）我的状态
    func endMyStatus() async {
        _ = try? await request("POST", "/api/me/status", body: ["ended": true])
    }

    /// 图片压完再传：返回服务器上的 /uploads/xxx.jpg
    func upload(image: UIImage) async throws -> String {
        /* 长边 1280 / 画质 0.75：手机上看着和 1600@0.82 没差，体积只有三分之一左右。
           聊天气泡、朋友圈列表都是一屏好几张图，压小了翻起来才跟手。 */
        let data = image.resizedJPEG(maxSide: 1280, quality: 0.75)
        return try await uploadData(data)
    }

    /// 发图专用：和 upload / uploadOriginal 一样，但把**真正上传的那份字节**也返回出来。
    /// 调用方拿它按「下载过一次的图」的待遇写本地缓存（内存 + 磁盘 + 长期留底），
    /// 这样发出去的图自己也**秒出**、重开 App 也不用再下一遍。
    func uploadImageForSend(_ image: UIImage, original: Bool) async throws -> (url: String, data: Data) {
        let data = image.resizedJPEG(maxSide: original ? 1920 : 1280,
                                     quality: original ? 0.88 : 0.75)
        guard let data = data else { throw APIError.message("图片处理失败") }
        let url = try await uploadData(data)
        return (url, data)
    }

    /// 聊天背景：比头像清楚得多（长边 2048、画质 0.95）。
    /// 视频/大文件走二进制直传（不再 base64，少传 25%，手机上快一截）
    /// 给播放器的资源：带上鉴权头，让 AVPlayer 自己边下边播（服务器已支持 Range 分片）
    func streamingAsset(_ path: String) -> AVURLAsset? {
        guard let u = assetURL(path) else { return nil }
        let headers: [String: String] = token.isEmpty ? [:] : ["Authorization": "Bearer \(token)"]
        return AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    func uploadBinary(_ data: Data, mime: String) async throws -> String {
        guard let url = URL(string: base + "/api/upload/raw") else { throw APIError.message("服务器地址不正确") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (d, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.message("上传失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        return try Self.rawUploadURL(from: d)
    }

    /// 视频这种大文件：**从磁盘流式上传**（不整段读进内存，几十 MB 的视频也不会顶内存），
    /// 并且把真实上传进度回调出来 —— 聊天页那个「发送中」的转圈进度条就是靠它。
    func uploadBinaryFile(_ file: URL, mime: String,
                          skipTranscode: Bool = false,
                          onProgress: @escaping (Double) -> Void) async throws -> String {
        guard let url = URL(string: base + "/api/upload/raw") else { throw APIError.message("服务器地址不正确") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        /* 大视频 + 移动网络：给足时间，别传到一半自己超时 */
        req.timeoutInterval = 600
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        /* 告诉服务器「这条已经在手机上压好了，别再压一遍」——
           服务端跟着再压一遍要十几秒，用户感觉就是"发视频很慢"。 */
        if skipTranscode { req.setValue("1", forHTTPHeaderField: "x-chris-compressed") }
        let delegate = UploadProgressDelegate(onProgress)
        let (d, resp) = try await session.upload(for: req, fromFile: file, delegate: delegate)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.message("上传失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        return try Self.rawUploadURL(from: d)
    }

    /// /api/upload/raw 的返回值：可能直接是 {url}，也可能裹一层 {ok,data:{url}}
    private static func rawUploadURL(from d: Data) throws -> String {
        struct RawUpload: Decodable { var url: String? }
        if let parsed = try? JSONDecoder().decode(RawUpload.self, from: d),
           let u = parsed.url, !u.isEmpty { return u }
        struct Wrapper: Decodable { struct D: Decodable { var url: String? }; var data: D? }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: d), let u = w.data?.url, !u.isEmpty { return u }
        throw APIError.message("上传返回异常")
    }

    /// 注意别设太大：一张 4800 万的相册原图直接按 4096 重绘会把内存打爆闪退。
    func uploadOriginal(image: UIImage) async throws -> String {
        // 「原图」也别给太大：1920 / 0.88 在手机上看不出区别，体积小一半以上
        let data = image.resizedJPEG(maxSide: 1920, quality: 0.88)
        return try await uploadData(data)
    }

    /// 朋友圈封面：比聊天背景还要大一点（长边 2560、画质 0.95）。
    /// 封面要能缩放拖动裁切，2048 放大后还是会糊，所以单独给一档。
    func uploadCover(image: UIImage) async throws -> String {
        let data = image.resizedJPEG(maxSide: 1920, quality: 0.88)
        return try await uploadData(data)
    }

    private func uploadData(_ data: Data?) async throws -> String {
        guard let data = data else {
            throw APIError.message("图片处理失败")
        }
        let b64 = data.base64EncodedString()
        let payload: UploadPayload = try await post("/api/upload",
                                                    ["dataUrl": "data:image/jpeg;base64," + b64,
                                                     "filename": "photo.jpg"],
                                                    as: UploadPayload.self)
        guard let url = payload.url else { throw APIError.message("上传失败") }
        return url
    }

    /// mentions：群里这条消息 @ 了谁（userId 列表）—— 服务端存下来，
    /// 被 @ 的人会话列表出「[有人@我]」、通知里也带这行字
    func send(chatId: String, kind: String, content: String, mentions: [String] = [],
              imgW: Int = 0, imgH: Int = 0) async throws -> Message? {
        var body: [String: Any] = ["kind": kind, "content": content]
        if !mentions.isEmpty { body["mentions"] = mentions }
        /* 图片宽高随消息一起带上：对面第一帧就按真实比例把气泡画好（骨架落位） */
        if imgW > 1, imgH > 1 { body["imgW"] = imgW; body["imgH"] = imgH }
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     body,
                                                     as: MessagePayload.self)
        return payload.message
    }

    /// 带 clientId 的发送：离线重发时服务器按它去重（同一个 clientId 只落一条消息）
    func send(chatId: String, kind: String, content: String, mentions: [String] = [],
              clientId: String, imgW: Int = 0, imgH: Int = 0) async throws -> Message? {
        var body: [String: Any] = ["kind": kind, "content": content, "clientId": clientId]
        if !mentions.isEmpty { body["mentions"] = mentions }
        if imgW > 1, imgH > 1 { body["imgW"] = imgW; body["imgH"] = imgH }
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     body,
                                                     as: MessagePayload.self)
        return payload.message
    }

    func recall(chatId: String, messageId: String) async {
        _ = try? await request("POST", "/api/messages/\(messageId)/recall", body: ["chatId": chatId])
    }

    func likeMoment(id: String) async {
        _ = try? await request("POST", "/api/moments/\(id)/like", body: [:])
    }

    /// 打开朋友圈 = 看过了，「发现」上的红点清掉
    func markMomentsSeen() async {
        _ = try? await request("POST", "/api/moments/seen", body: [:])
    }

    func commentMoment(id: String, text: String) async {
        _ = try? await request("POST", "/api/moments/\(id)/comments", body: ["content": text])
    }

    func deleteMoment(id: String) async {
        _ = try? await request("DELETE", "/api/moments/\(id)")
    }

    /// 置顶 / 取消置顶自己发的动态（置顶的固定排在朋友圈最上面，只能置顶一条）
    func pinMoment(id: String, pinned: Bool) async {
        _ = try? await request("POST", "/api/moments/\(id)/pin", body: ["pinned": pinned])
    }

    /// 删朋友圈评论（微信：点自己的评论 → 删除）
    func deleteMomentComment(momentId: String, commentId: String) async -> String? {
        do {
            _ = try await request("DELETE", "/api/moments/\(momentId)/comments/\(commentId)")
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    /// 发朋友圈：谁可以看（public 公开 / private 仅自己 / partial 部分可见 / exclude 不给谁看）
    func postMoment(content: String, images: [String],
                    imageSizes: [String: [Int]] = [:],
                    video: String = "", videoCover: String = "",
                    videoSeconds: Int = 0, videoW: Int = 0, videoH: Int = 0,
                    visibility: String = "public",
                    visibleTo: [String] = [], hiddenFrom: [String] = [],
                    location: String = "") async throws {
        var body: [String: Any] = [
            "content": content, "images": images,
            "visibility": visibility, "visibleTo": visibleTo, "hiddenFrom": hiddenFrom,
            "location": location
        ]
        /* 每张图的宽高一起带上：列表那边就能按真实比例先画好框，
           不会再"先 4:3、加载完跳一下"（用户反馈的尺寸跳变） */
        if !imageSizes.isEmpty { body["imageSizes"] = imageSizes }
        if !video.isEmpty {
            body["video"] = video
            body["videoCover"] = videoCover
            body["videoSeconds"] = videoSeconds
            body["videoW"] = videoW
            body["videoH"] = videoH
        }
        _ = try await request("POST", "/api/moments", body: body)
    }

    func updateMe(_ fields: [String: Any]) async {
        _ = try? await request("PATCH", "/api/me", body: fields)
    }

    /// 和 updateMe 一样，但**把服务器那句话带回来**。
    /// 以前 updateMe 是 try?，服务器说"昵称不合格 / 手机号一年只能改一次"这种
    /// 整条 PATCH 会被拒，界面却照样提示"已保存" —— 用户看到的
    /// 「设置了地区/生日都没生效」十有八九就是它。
    func updateMeChecked(_ fields: [String: Any]) async throws {
        _ = try await request("PATCH", "/api/me", body: fields)
    }

    func addFriend(username: String, from: String = "") async throws {
        var body: [String: Any] = ["username": username]
        if !from.isEmpty { body["from"] = from }
        _ = try await request("POST", "/api/friends/request", body: body)
    }

    func rawUpload(_ body: [String: Any]) async throws -> (url: String, name: String, bytes: Int) {
        let payload: UploadPayload = try await post("/api/upload", body, as: UploadPayload.self)
        guard let url = payload.url else { throw APIError.message("上传失败") }
        return (url, payload.name ?? "", payload.bytes ?? 0)
    }

    func transfer(chatId: String, amount: Double, note: String,
                  method: String, password: String, face: Bool = false) async throws {
        _ = try await request("POST", "/api/pay/transfer", body: [
            "chatId": chatId,
            "amount": amount,
            "note": note,
            "method": method,
            "password": password,
            "face": face,
            /* 幂等键：这一笔的唯一编号。网络超时重发 / 用户连点，
               服务端看到同一个编号只会扣一次钱（接真钱必须的） */
            "requestId": UUID().uuidString
        ])
    }

    /* ---------------- 收付款（付款码 / 收款码，微信那套） ---------------- */

    /// 出一张付款码（18 位数字，60 秒有效；同一分钟内重复拉还是同一张）
    func payCode() async throws -> PayCodeInfo {
        try await post("/api/pay/code", [:], as: PayCodeInfo.self)
    }

    /// 我的收款码；amount > 0 就是「设置金额」那张（金额被服务器签名，改不了）
    func receiveCode(amount: Double) async throws -> PayCodeInfo {
        try await post("/api/pay/receive-code", ["amount": amount], as: PayCodeInfo.self)
    }

    /// 扫到的字符串先问一下服务器：这是谁的收付款码、金额多少
    func payResolve(text: String) async throws -> PayScanInfo {
        try await post("/api/pay/resolve", ["text": text], as: PayScanInfo.self)
    }

    /// 付款：钱当时到对方账上（商家收款即时到账）
    func payCollect(text: String, amount: Double, password: String, face: Bool = false) async throws -> PayCollectResult {
        try await post("/api/pay/collect", [
            "text": text, "amount": amount, "password": password, "face": face,
            "requestId": UUID().uuidString
        ], as: PayCollectResult.self)
    }

    func hasPayPassword() async -> Bool {
        guard let any = try? await request("GET", "/api/me/paypassword"),
              let dict = any as? [String: Any],
              let has = dict["has"] as? Bool else { return false }
        return has
    }

    /// 校验支付密码（转账确认用）
    func verifyPayPassword(_ password: String) async throws {
        _ = try await request("POST", "/api/me/paypassword/verify", body: ["password": password])
    }

    /// 设置 / 修改支付密码（6 位数字；已经设过的要带上原密码）
    func setPayPassword(_ password: String, current: String = "") async throws {
        var body: [String: Any] = ["password": password]
        if !current.isEmpty { body["current"] = current }
        _ = try await request("POST", "/api/me/paypassword", body: body)
    }

    /// 举报某人（后台「举报处理」里能看到）
    func report(userId: String, chatId: String, reason: String, content: String) async {
        _ = try? await request("POST", "/api/reports", body: [
            "targetUserId": userId,
            "chatId": chatId,
            "reason": reason,
            "content": content
        ])
    }
}

extension UIImage {
    /// 随图片消息一起带上服务器的「原始宽高」（只要比例对就行；上传时会按同一比例缩放）
    var sendPixelSize: (w: Int, h: Int) {
        (max(1, Int(size.width.rounded())), max(1, Int(size.height.rounded())))
    }

    /// 上传前压一下：长边最多 maxSide，JPEG 质量 quality
    func resizedJPEG(maxSide: CGFloat, quality: CGFloat) -> Data? {
        let long = max(size.width, size.height)
        var target = size
        if long > maxSide {
            let k = maxSide / long
            target = CGSize(width: size.width * k, height: size.height * k)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let out = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return out.jpegData(compressionQuality: quality)
    }
}
