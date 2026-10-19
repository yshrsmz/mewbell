# アプリアイコンの素材

`Mewbell/AppIcon.icon`（Icon Composer の形式）の元になる層の SVG。緑の目の黒猫が首に金の鈴を付けた顔を、1024×1024 の角丸の無い画面に描いている。目の緑はメニューバーの未読の表示と同じ `systemGreen`（`#34C759`）。角丸・ガラスの質感・ハイライト・影は Icon Composer とシステムが付けるので、層には平らな色だけを入れる。

| ファイル | 中身 |
| --- | --- |
| `1-cat.svg` | 猫の頭と耳 |
| `2-eyes.svg` | 緑の目と縦長の瞳 |
| `3-bell.svg` | 首の鈴 |

背景は層にせず、Icon Composer の塗り（Fill）で上から下への線形グラデーション `#F3F5F9` → `#D5DDEA` を指定する。

## 直し方

1. この SVG を直す
2. Icon Composer で `Mewbell/AppIcon.icon` を開き、直した層を読み込み直して保存する
3. `bash scripts/build.sh` でビルドし、Finder と Dock で見た目を確かめる
