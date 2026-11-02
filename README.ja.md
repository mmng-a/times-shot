# Times Shot

[English](README.md) | [日本語](README.ja.md)

**Slackを開かずに、ひとこと投稿。**

Times Shotは、メモや画像をSlackのチャンネルへ投稿するmacOSアプリ。`Shift + Space`で入力画面を開き、`⌘Enter`で送信できる。

自分のtimesに進捗や思いついたことを残したいときに。画像は貼り付けやドラッグ＆ドロップで添付でき、書きかけの内容は入力画面を閉じても下書きとして残る。

## インストール

対応環境はApple Silicon搭載Mac、macOS 27.0以降。

Homebrew 7以降では、初回にtapを追加し、Times ShotのCaskを信頼対象に登録する。

```sh
brew tap mmng-a/tap
brew trust --cask mmng-a/tap/times-shot
brew install --cask mmng-a/tap/times-shot
```

[GitHub Releases](https://github.com/mmng-a/times-shot/releases)のZIPを展開し、`Times Shot.app`をApplicationsフォルダへコピーする方法でも導入できる。

Developer IDによる署名・Appleの公証は行っていない。初回起動がブロックされた場合は、入手元を確認し、システム設定の「プライバシーとセキュリティ」から「このまま開く」を選ぶ。[Appleの案内](https://support.apple.com/ja-jp/102445)

## はじめ方

1. 設定の「一般」から「Slackに接続」を選び、ブラウザで権限を許可する。
2. 設定の「チャンネル」で、参加しているチャンネルを一覧から選んで登録する。
3. `Shift + Space`で入力画面を開き、投稿先を確認して、本文や画像を`⌘Enter`で送信する。

Slack Appの作成や、トークン・チャンネルIDの手入力は不要。ワークスペースによっては管理者の承認が必要となる。

| 操作 | 動作 |
| --- | --- |
| Shift + Space | 入力画面の表示・非表示 |
| ⌘Enter | 送信 |
| ⌘W、閉じるボタン | 下書きを残して閉じる |
| Esc | 本文と画像を破棄して閉じる |

## 利用前に知っておくこと

- 接続できるのは1つのワークスペース・アカウント。投稿先は複数登録できる。
- 認証情報はこのMacのKeychain、下書きと添付画像は端末内に保存する。会話履歴は取得しない。
- 失敗した投稿は破棄され、自動再送や復元は行わない。送信エラーを確認できるよう、macOSの通知を許可しておく。
- 一部のメニュー項目やメッセージは日本語表示。

## ドキュメント

- [操作ガイド](docs/usage.ja.md)：画像・書式、送信待ち、投稿先の管理、Slackの権限
- [開発ガイド（英語）](docs/development.md)：ビルド・テスト・診断ログ・ブランチ運用
- [公開・配布の手順](docs/public-release.md)

## ライセンス

[MIT License](LICENSE)
