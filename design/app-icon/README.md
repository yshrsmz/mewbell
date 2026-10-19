# アプリアイコンの素材

`Mewbell/AppIcon.icon`（Icon Composer の形式）の元になる層の SVG。猫の顔をした神社の鈴を、1024×1024 の角丸の無い画面に描いている。角丸・ガラスの質感・ハイライト・影は Icon Composer とシステムが付けるので、層には平らな色だけを入れる。

| ファイル | 中身 |
| --- | --- |
| `1-cord.svg` | 上から垂れる紐と、鈴を吊る輪 |
| `2-suzu.svg` | 鈴の本体と猫の耳 |
| `3-face.svg` | 閉じた目、鼻、口に見立てた鈴の切れ込み |

背景は層にせず、Icon Composer の塗り（Fill）で上から下への線形グラデーション `#C9424A` → `#84212D` を指定する。

## 直し方

1. この SVG を直す
2. Icon Composer で `Mewbell/AppIcon.icon` を開き、直した層を読み込み直して保存する
3. `bash scripts/build.sh` でビルドし、Finder と Dock で見た目を確かめる
