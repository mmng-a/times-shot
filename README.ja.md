# Times Shot

[English](README.md) | [日本語](README.ja.md)

Times Shotは、メモや画像をSlackのチャンネルへ投稿するmacOSのメニューバーアプリです。自分のtimesへの進捗メモや、画像の共有に使えます。

入力画面を開くショートカットは`Shift + Space`、送信は`⌘Enter`です。下書きは画面を閉じても残るため、書きかけのまま作業に戻っても、最初から書き直す必要はありません。

## インストール

Apple Silicon搭載Mac、macOS 27.0以降に対応しています。

Homebrew 7以降では、次のコマンドでtapを追加し、Times ShotのCaskを信頼対象に登録してからインストールしてください。

```sh
brew tap mmng-a/tap
brew trust --cask mmng-a/tap/times-shot
brew install --cask mmng-a/tap/times-shot
```

[GitHub Releases](https://github.com/mmng-a/times-shot/releases)からZIPをダウンロードして展開し、`Times Shot.app`をApplicationsフォルダにコピーする方法でもインストールできます。

Appleの開発者証明書による署名と公証は行っていません。初回起動がmacOSにブロックされるため、システム設定の「プライバシーとセキュリティ」で「このまま開く」を選んでアプリを開いてください。[Appleの手順](https://support.apple.com/ja-jp/102445)

## 使い方

1. 設定の「一般」で「Slackに接続」を選択し、ブラウザで接続先のワークスペースと権限を確認して許可してください。
2. 設定の「チャンネル」で、参加しているチャンネルの一覧から投稿先を登録してください。
3. `Shift + Space`で入力画面を開き、投稿先を確認して本文を入力します。画像は貼り付けやドラッグ＆ドロップで添付し、`⌘Enter`で送信してください。

Slack Appを自分で作成したり、トークンやチャンネルIDを入力したりする必要はありません。ワークスペースによっては、管理者によるアプリの承認が必要です。

| 操作 | 動作 |
| --- | --- |
| Shift + Space | 入力画面の表示・非表示 |
| ⌘Enter | 送信 |
| ⌘W、閉じるボタン | 下書きを残して閉じる |
| Esc | 本文と画像を破棄して閉じる |

## 注意点

- 接続できるのは1つのワークスペースとアカウントですが、投稿先のチャンネルは複数登録できます。
- 認証情報の保存先はこのMacのKeychainです。下書きと添付画像も端末内に保存し、Slackの会話履歴は取得しません。
- 送信に失敗した投稿は破棄され、自動再送や復元はできません。エラーを確認できるよう、macOSの通知を許可してください。
- 一部のメニュー項目やメッセージは日本語のみの表示です。

## ドキュメント

- [操作ガイド](docs/usage.ja.md)：画像・書式、送信待ち、投稿先の管理、Slackの権限
- [開発ガイド（英語）](docs/development.md)：ビルド・テスト・診断ログ・ブランチ運用
- [公開・配布の手順](docs/public-release.md)

## ライセンス

[MIT License](LICENSE)
