import SwiftUI
import WebKit

/* ============================================================
   小游戏「好友排名」（每个游戏都有，不用改游戏本身）

   运行时往页面里注一层 JS：
   · **自动报分**：盯着 localStorage 里那些 `*_best`（跳一跳 jj_best、2048 g2048_best…），
     一存就把分数报给服务器（POST /api/games/score，只涨不跌）
   · **排名面板**：顶部那颗 🏆 调 window.chrisRank.show()，拉
     GET /api/games/rank?game=xxx（我 + 我的好友，按最高分排）画一张底部弹层
   ============================================================ */

/// 让外面能拿到正在显示的那个 webview（顶栏那颗 🏆 要往里打 JS）
final class WebBox: ObservableObject {
    weak var web: WKWebView?
}

func chrisRankJs(game: String, token: String, base: String) -> String {
    let g = game.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let t = token.replacingOccurrences(of: "\"", with: "\\\"")
    let b = base.replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (function () {
      if (window.chrisRank) return;
      var GAME = "\(g)", TOKEN = "\(t)", BASE = "\(b)";
      function abs(u) { return /^https?:/i.test(u || '') ? u : (BASE + ((u || '').charAt(0) === '/' ? u : '/' + (u || ''))); }
      function report(n) {
        n = Math.floor(Number(n) || 0);
        if (!(n > 0)) return;
        fetch(abs('/api/games/score'), {
          method: 'POST',
          headers: { 'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json' },
          body: JSON.stringify({ game: GAME, score: n })
        }).catch(function () { });
      }
      function hide() { var el = document.getElementById('__chris_rank'); if (el) el.remove(); }
      function show() {
        hide();
        fetch(abs('/api/games/rank?game=' + encodeURIComponent(GAME)), { headers: { 'Authorization': 'Bearer ' + TOKEN } })
          .then(function (r) { return r.json(); })
          .then(function (j) {
            var d = (j && j.data) || {}, list = d.list || [];
            var rows = list.map(function (x) {
              var medal = x.rank === 1 ? '🥇' : (x.rank === 2 ? '🥈' : (x.rank === 3 ? '🥉' : (x.rank + '')));
              return '<div class="__cr_row' + (x.me ? ' me' : '') + '">'
                + '<span class="__cr_rk">' + medal + '</span>'
                + '<img src="' + abs(x.avatar || '') + '" onerror="this.style.visibility=\\'hidden\\'">'
                + '<span class="__cr_nm">' + (x.name || '') + '</span>'
                + '<span class="__cr_sc">' + (x.score || 0) + '</span></div>';
            }).join('');
            var el = document.createElement('div');
            el.id = '__chris_rank';
            el.innerHTML = '<style>'
              + '#__chris_rank{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:999999;display:flex;align-items:flex-end}'
              + '#__chris_rank .box{width:100%;max-height:72%;background:#1C1C1E;border-radius:16px 16px 0 0;padding:14px 0 10px;overflow:auto;font-family:-apple-system,"PingFang SC",sans-serif}'
              + '#__chris_rank h3{color:#fff;font-size:16px;margin:0 0 10px;text-align:center;font-weight:600}'
              + '#__chris_rank .__cr_row{display:flex;align-items:center;gap:10px;padding:9px 18px;color:#fff;font-size:15px}'
              + '#__chris_rank .__cr_row.me{background:rgba(62,211,127,.16)}'
              + '#__chris_rank .__cr_rk{width:26px;text-align:center;font-size:13px;color:#9a9a9a}'
              + '#__chris_rank img{width:30px;height:30px;border-radius:15px;background:#333}'
              + '#__chris_rank .__cr_nm{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}'
              + '#__chris_rank .__cr_sc{color:#3ED37F;font-weight:600}'
              + '#__chris_rank .__cr_my{text-align:center;color:#9a9a9a;font-size:12.5px;padding:8px}'
              + '#__chris_rank .__cr_btn{display:block;margin:10px auto 4px;padding:9px 26px;border-radius:20px;background:#3ED37F;color:#fff;border:0;font-size:15px}'
              + '</style><div class="box"><h3>好友排名</h3>'
              + (rows || '<div class="__cr_my">还没有人玩过，你先来一局</div>')
              + '<div class="__cr_my">我的名次：第 ' + (d.myRank || '-') + ' 名 · 最高 ' + (d.myScore || 0) + ' 分</div>'
              + '<button class="__cr_btn" onclick="chrisRank.hide()">关闭</button></div>';
            el.addEventListener('click', function (e) { if (e.target === el) hide(); });
            document.body.appendChild(el);
          }).catch(function () { });
      }
      /* 自动报分：页面自己往 localStorage 存的最高分（*_best）一存就报上去 */
      try {
        var orig = localStorage.setItem.bind(localStorage);
        localStorage.setItem = function (k, v) {
          orig(k, v);
          try {
            if (/_best$/i.test(k) || /score|high/i.test(k)) {
              var n = parseInt(String(v).replace(/[^0-9]/g, ''), 10);
              if (n > 0) report(n);
            }
          } catch (e) { }
        };
        Object.keys(localStorage).forEach(function (k) {
          if (/_best$/i.test(k)) {
            var n = parseInt(String(localStorage.getItem(k)).replace(/[^0-9]/g, ''), 10);
            if (n > 0) report(n);
          }
        });
      } catch (e) { }
      window.chrisRank = { report: report, show: show, hide: hide, game: GAME };
    })();
    """
}
