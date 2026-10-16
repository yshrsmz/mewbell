/// UI だけが使うホスト名の表示（モデルは自分を表示する画面を知らないので、UI の側に置く）。
/// ポップオーバーと macOS の通知の両方が使うアカウントの名前は `AccountID.displayName` にある。
extension Account {
    /// 設定画面に出すホスト名とホスト種別（`github.com — GitHub.com`）。ポップオーバーの見出しはホスト名だけを出す
    var hostLabel: String { "\(host) — \(hostKind.displayName)" }
}
