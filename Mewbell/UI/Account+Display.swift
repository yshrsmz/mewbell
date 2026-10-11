/// 画面に出すアカウントの名前（モデルは自分を表示する画面を知らないので、UI の側に置く）。
extension Account {
    /// 見出しと設定画面に出すホスト名とホスト種別（`github.com — GitHub.com`）
    var hostLabel: String { "\(host) — \(hostKind.displayName)" }
    /// 開閉のボタンのツールチップと読み上げに出す名前（`alice (github.com)`）
    var accessibilityName: String { "\(user) (\(host))" }
}
