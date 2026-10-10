import SwiftUI
import UIKit

/// A–Z 索引的粗细：后台「界面文字」里 ctIdxBold = 1（默认）就是加粗，
/// 写 0 回到原来的细体。两处索引（通讯录整页 / 联系人列表右栏）都用它。
func ctIdxWeight() -> Font.Weight { UIConfig.num("ctIdxBold", 1) > 0 ? .bold : .regular }

/// 通讯录右侧的 A–Z 索引：和网页版一样 27 个字母全都在，
/// 点一下或**按着上下拖**都能跳分组，中间还会弹一个黑色大字气泡。
struct ContactIndexBar: View {
    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { String($0) }

    var available: Set<String>
    var onPick: (String) -> Void
    var onSearch: () -> Void

    private let padV: CGFloat = 4.2
    private let searchBox: CGFloat = 15
    private let searchGap: CGFloat = 4

    /// 手指正压在哪个字母上：那一个外面套一个蓝色实心圆（用户要求）
    @State private var active: String? = nil
    /// 每滑过一个字母轻震一下（用户要求「按索引的时候有振动感」）
    private let haptic = UISelectionFeedbackGenerator()

    /* 字号 / 行距 / 颜色都从后台「界面文字」读（ctIdxSize / ctIdxItemH / ctIdxColor），
       以前这里写死 12.5 和 #B2B2B2，所以后台改了手机上没反应 */
    private var fontSize: CGFloat { max(6, L.ctIdxSize) }
    private var rowH: CGFloat { max(fontSize, L.ctIdxItemH) }
    private var pitch: CGFloat { rowH }
    private var listTop: CGFloat { padV + searchBox + searchGap }
    /// 选中那个圆点：颜色后台 ctIdxActiveBg 可调，直径按行高走（保证是正圆）
    private var dotSide: CGFloat { max(15, rowH + 1.5) }
    /// 蓝圈的颜色：后台单独配了 ctIdxActiveBg 就用它；
    /// 没配就**跟着索引字母自己的颜色走**，这样两边永远是一个色。
    private var activeBg: Color { UIConfig.colorIfSet("ctIdxActiveBg") ?? C.ctIdxColor }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSearch) {
                SVGIcon(markup: I.searchBig, size: 13, color: C.ctIdxColor)
                    .frame(width: searchBox, height: searchBox)
            }
            .buttonStyle(.plain)
            .padding(.bottom, searchGap)

            ForEach(Self.letters, id: \.self) { L in
                Text(L)
                    .font(pf(fontSize, ctIdxWeight()))
                    /* 选中的那个字母：白字 + 蓝色实心圆（不选中就还是原来的灰字） */
                    .foregroundColor(active == L ? .white : C.ctIdxColor)
                    .frame(height: rowH)
                    .frame(width: 22)
                    .background {
                        if active == L {
                            Circle()
                                .fill(activeBg)
                                .frame(width: dotSide, height: dotSide)
                        }
                    }
            }
        }
        .padding(.vertical, padV)
        .frame(width: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let y = value.location.y - listTop
                    let i = max(0, min(Self.letters.count - 1, Int(floor(y / pitch))))
                    pick(Self.letters[i])
                }
                .onEnded { _ in active = nil }
        )
    }

    /// 手指移到新字母：轻震一下 + 蓝圈跟过去（同一个字母不重复震）
    private func pick(_ letter: String) {
        if active != letter {
            active = letter
            haptic.selectionChanged()
        }
        onPick(letter)
    }
}

/// 拖动索引时中间弹出来的黑色大字气泡（网页版是 78×78、圆角 14、黑 62%）
struct LetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(pf(36, .semibold))
            .foregroundColor(.white)
            .frame(width: 78, height: 78)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.62))
            )
            .allowsHitTesting(false)
    }
}
