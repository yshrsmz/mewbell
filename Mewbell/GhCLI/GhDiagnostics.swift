import Foundation

/// 最後の読み直しでの gh の検出の結果（Diagnostics 用）。gh の出力の文字列は持たない。
struct GhDiagnostics: Sendable, Equatable {
    /// 使っている gh の実体のパスと見つけ方（見つからなければ nil）
    var executable: GhLocation?
    /// `gh --version` から読んだバージョン（読めなかった、または確かめる前に止まったら nil）
    var version: GhVersion?
    /// 使っている設定ディレクトリと決め方（上書きが使えない、または確かめる前に止まったら nil）
    var configDirectory: GhConfigDirectory.Resolved?
}
