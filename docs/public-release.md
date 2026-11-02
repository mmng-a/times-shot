# 一般公開の手順

最終確認日: 2026-11-02

Times ShotのSlack接続の設定と、一般公開に向けた準備をまとめます。OAuth接続、認証情報の更新・接続解除、参加済みチャンネルの一覧選択は実装済みです。OAuth接続・チャンネル選択・文章と画像の投稿は既存の利用環境で確認済みですが、別の利用者・ワークスペースへの導入と公開用配布物の検証は別途必要です。Slack Marketplaceの審査とAppleの公証は完了していません。申請時にはリンク先の最新要件を確認してください。

## 公開する構成

- 開発者が管理するSlack AppをOAuthで各利用者のワークスペースへ接続する。
- 利用者は「Slackに接続」からブラウザで権限を許可し、アプリへ戻る。
- 本人が参加している公開・プライベートチャンネルを一覧から検索し、投稿先へ登録する。利用者によるトークン・チャンネルIDの入力は不要。
- 本人名義で、本人が入力した文章と選択した画像を登録チャンネルへ送る。会話履歴の取得・閲覧は行わない。
- macOSアプリはGitHub ReleasesとHomebrew tapで配布する。Apple Silicon・macOS 27.0以降を対象にアドホック署名を付け、Developer ID署名・公証は行わない。

Slackとの接続には投稿権限を取得するOAuthを使います。本人確認用の「Sign in with Slack」だけでは投稿できません。現在は1つのワークスペース・アカウントへの接続に対応し、独立したサービスアカウントやログイン機能は設けていません。[Slack OAuth](https://docs.slack.dev/authentication/installing-with-oauth/)

Slack Marketplaceへの掲載と、macOSアプリの配布先は別です。直接配布でもSlack側の配布条件を満たす必要があります。Mac App Storeを選ぶ場合は、別途App Sandboxへの対応とAppleのApp Reviewを計画します。

未掲載配布でもOAuthで他のワークスペースへ接続できます。Marketplace申請に必要な導入実績は、初期利用者への試験配布で積みます。10以上のアクティブワークスペースという条件はMarketplace申請の条件であり、OAuth接続を始める条件ではありません。[未掲載配布](https://docs.slack.dev/app-management/distribution/#unlisted-distributed-apps)、[審査の前提条件](https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide/#prerequisites)

## 実装状況と残る公開準備

| 項目 | 現状 | 公開前に必要な対応 |
| --- | --- | --- |
| Slack接続 | PKCE OAuthで接続し、接続先を表示 | 別の利用者・ワークスペースで導入を検証 |
| 認証情報 | Keychainにトークン・有効期限・workspace/user IDを保存し、必要時に更新 | 拒否・取り消し・期限切れ・スリープ復帰を実環境で検証 |
| トークンの検証 | OAuth応答のユーザートークン種別・権限と、本人・ワークスペースのIDを検証 | 申請時の権限説明と一致することを確認 |
| 送信キュー | 接続IDと投稿先を固定し、送信時に有効なトークンを取得 | 更新・接続解除・再接続時の実環境での検証 |
| チャンネル登録 | 参加済みチャンネルを一覧から検索・登録 | 参加状況の変更・アーカイブ後のエラーを実環境で検証 |
| アプリ配布 | アドホック署名のApple Silicon版 | GitHub Release、Homebrew Cask、別環境での初回起動の検証 |
| 公開情報 | README | 配布ページ、接続手順、プライバシーポリシー、問い合わせ先 |

接続とトークン更新は[SlackConnection.swift](../Sources/TimesShot/SlackConnection.swift)、PKCEとコールバックの検証は[SlackAuthorization.swift](../Sources/TimesShotCore/SlackAuthorization.swift)、API通信は[SlackClient.swift](../Sources/TimesShotCore/SlackClient.swift)、設定操作は[SettingsModel.swift](../Sources/TimesShot/SettingsModel.swift)を参照してください。Slack Marketplaceへの掲載確認と、別の利用者・ワークスペースでの試験は後続作業です。

## 1. Slackへの掲載可否を確認する

Slackは「Slackクライアント機能の再現」「第三者製Slackクライアント」をMarketplaceの掲載対象外としています。Times Shotの投稿専用という機能範囲が対象になるかは未確認です。会話履歴を取得しないことだけで掲載が保証されるわけではありません。[掲載条件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/)

2026-10-31時点に調査した機能の先例は次のとおりです。現在の掲載状況は問い合わせ前に再確認してください。

| アプリ | 確認できた機能・掲載状況 |
| --- | --- |
| [Snagit](https://slack.com/marketplace/A03PMGRSH7X-snagit) | Marketplace掲載あり。外部アプリからチャンネル・DMへ画像などを直接送信し、投稿先情報も取得 |
| [Message Scheduler](https://slack.com/marketplace/AJ0QX9THD-message-scheduler) | Marketplace掲載あり。本人のプロフィールで予約送信し、複数チャンネルにも対応 |
| [Raycast: Slack Templated Message](https://www.raycast.com/koh-sh/slack-templated-message) | OAuthで接続し、macOSから定型文を送信。Raycast Store掲載を確認。Slack Marketplace掲載は未確認 |
| [Faslack](https://faslack.com/) | 即時メモ投稿・写真アップロードを公式サイトで案内。Slackの承認状況・現在の動作は未確認 |

これらは機能の先例であり、Times Shotの承認実績ではありません。[Slack Marketplaceの窓口](https://slack.dev/marketplace/)へ、以下を添えて掲載対象になるか確認します。

- macOSのメニューバーから、本人が作成した文章・画像を本人名義で送るツールであること。
- 会話履歴の表示、検索、受信通知、バックアップの機能を持たないこと。
- 要求するUser Token Scopesと、それぞれの用途。
- 接続から投稿までの画面、データの保存先、配布方法、無料・有料の予定。

回答は日付・問い合わせ先・説明した機能範囲とともに記録します。名称だけを変えてクライアント制限を回避する方法は採りません。

## 2. OAuth接続の設定と仕様

### Slack Appと権限

配布用Slack Appは開発者が管理します。利用者によるSlack Appの作成は不要です。本人名義で投稿するため、Bot Token Scopesではなく、次の4つのUser Token Scopesを設定します。

| 権限 | 用途 |
| --- | --- |
| [`chat:write`](https://docs.slack.dev/reference/scopes/chat.write/) | 本人名義のテキスト投稿 |
| [`files:write`](https://docs.slack.dev/reference/scopes/files.write/) | 本人が選択した画像のアップロード・共有 |
| [`channels:read`](https://docs.slack.dev/reference/scopes/channels.read/) | 公開チャンネルの基本情報取得 |
| [`groups:read`](https://docs.slack.dev/reference/scopes/groups.read/) | 参加済みプライベートチャンネルの基本情報取得 |

投稿に会話履歴の権限は不要です。`*:history`、`search:read`、`files:read`などを追加しません。ただし、`chat:write`や`files:write`は投稿以外の編集・削除APIにも使える権限なので、許可画面や説明文で「送信以外の権限は一切ない」とは説明しません。

### macOSアプリからの接続

Slackのネイティブアプリ向けPKCEを使用し、認証情報は端末のKeychainに保存します。認証専用の常設サーバーは使用しません。Slack Appの設定は次のとおりです。

1. 「OAuth & Permissions」で、上記4つのUser Token Scopesと戻り先`timesshot://oauth/callback`を設定し、PKCEを有効にする。
2. 「Basic Information」のClient IDを[Info.plist](../Resources/Info.plist)の`SlackClientID`に設定する。開発・検証用に別のSlack Appを使用する場合も、この値と接続先Appの設定を一致させてビルドする。
3. 他のワークスペースへ導入する場合は、「Manage Distribution」の「Share Your App with Other Workspaces」で確認項目を満たし、「Activate Public Distribution」を有効にする。

Client Secretやトークンをソース・配布物へ埋め込みません。PKCEの有効化は、Slackサポートへの連絡なしでは元に戻せません。[PKCEの仕様](https://docs.slack.dev/authentication/using-pkce/)、[未掲載配布の設定](https://docs.slack.dev/app-management/distribution/#enabling-unlisted-distribution)

アプリは次の手順で接続します。

1. 接続操作ごとにランダムな`state`と`code_verifier`を作り、`S256`の`code_challenge`を生成する。
2. `/oauth/v2/authorize`へ`client_id`、`user_scope`、`redirect_uri`、`state`とPKCEの引数を付け、ブラウザで許可を求める。
3. アプリでコールバックを受け、戻り先と`state`を検証する。キャンセル・拒否も処理する。
4. `oauth.v2.access`へ認可コード・同じ`redirect_uri`・`code_verifier`を渡す。PKCEでは`client_secret`をアプリへ埋め込まない。
5. 応答のユーザートークン種別・権限・workspace/user IDを確認し、`auth.test`の本人・ワークスペースのIDと照合してから、認証情報をKeychainへ保存する。

認可画面はmacOSの`ASWebAuthenticationSession`で開きます。認可結果はXPCのバックグラウンドスレッドから届くため、受信ハンドラを`nonisolated`・`@Sendable`とし、状態の変更と処理の再開をMainActor上で行います。

カスタムURIへの復帰にはPKCEが必須で、Bot権限は要求できません。本人名義の投稿にはユーザートークンを使用します。[PKCE](https://docs.slack.dev/authentication/using-pkce/)、[OAuth](https://docs.slack.dev/authentication/installing-with-oauth/)

### チャンネルの選択

`users.conversations`で接続した本人の参加済みチャンネルを取得します。公開・プライベートチャンネルを対象に全ページを取得し、アーカイブ済み・重複したチャンネルを除外して名前順で表示します。DMは取得しません。[一覧取得API](https://docs.slack.dev/reference/methods/users.conversations/)

利用者は「チャンネル」設定で名前を検索し、一覧の行または「＋」から投稿先へ追加します。選択したチャンネルのIDと取得時の名前を保存し、投稿画面では登録した投稿先を切り替えます。一覧の更新には「一覧を再取得」を使用します。

### トークン更新と接続解除

カスタムURIを使うPKCE接続では、Slack側の通常の設定にかかわらずローテーション対象のトークンが発行されます。アクセストークンは12時間、PKCEで発行されるrefresh tokenは30日で失効するため、長期間使わなかった場合の再接続も必要です。更新応答では新しいrefresh tokenを保存し、同じ接続の更新を並行実行しません。[ローテーション](https://docs.slack.dev/authentication/using-token-rotation/)、[PKCE](https://docs.slack.dev/authentication/using-pkce/)

- 一覧取得・送信時に有効期限を確認し、期限まで60秒以下なら更新する。更新用トークンの失効や権限取り消しなどで再認証が必要な場合は、設定の「Slackに再接続」から接続し直す。
- キューに記録した投稿先・接続IDを変えず、その接続の最新トークンで送る。再認証で別のワークスペースやユーザーになった場合に、待機中の投稿を移し替えない。
- 更新時の通信失敗はエラーとして扱い、認証情報が失効した場合は再接続へ案内する。投稿結果が不明なものを自動再送しない。
- 接続解除では、このMacのKeychainから認証情報を削除する。登録した投稿先・下書きは保持する。Slack Appのワークスペースからの削除は、Slack側のアプリ管理で別途行う。
- 送信中・送信待ち、画像の読み込み中は接続先の変更・接続解除を行えない。同じワークスペース・アカウントへの再接続では登録した投稿先を保持し、別の接続先に変更する場合は投稿先を選び直す。下書きがある間は別の接続先へ変更できない。
- トークン、認可コード、refresh token、PKCEの秘密値、アップロードURLをログへ出さない。

接続処理の段階と失敗理由はmacOSの統合ログの`OAuth`カテゴリへ、APIの通信エラーは`Slack`カテゴリへ記録します。ログの確認コマンドは[README](../README.md#診断ログ)を参照してください。

## 3. 公開情報を用意して試験配布する

ログイン不要のHTTPSページに、製品説明、対応macOS・CPU、ダウンロード、接続手順、プライバシーポリシー、問い合わせ先を用意します。Marketplace用の製品ページはREADMEやリポジトリのURLだけでは代用できません。サポートは別サービスへの登録なしで問い合わせできるようにします。[公開ページの要件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/#pages-associated-with-your-app)

プライバシーポリシーには、Keychainの認証情報、端末内の下書き・画像・チャンネル設定、Slackへ送るデータ、エラー通知に表示する本文冒頭・画像名、診断ログ、保持期間と削除方法を実装に合わせて記載します。「会話履歴を取得しない」と「入力内容を端末に保存しない」は別です。

OAuth対応版の配布ZIPを用意します。Slack Appの未掲載配布設定を確認したうえで、開発用とは別のワークスペースで、初回接続からチャンネル選択、文章・画像投稿、接続解除まで確認します。

未掲載での配布は初期利用者との試験に使えます。商用配布はMarketplaceへの提出・承認を前提に計画し、未掲載のままの本格配布や、利用者ごとにSlack Appを作らせる方法を審査の代わりにしません。利用先が管理者承認やMarketplace掲載を必須としている場合は、その制限に従います。[配布方法と管理者承認](https://docs.slack.dev/app-management/distribution/)

## 4. Slack Marketplaceへ申請する

1. 10以上のアクティブワークスペースで利用・検証する。審査ガイド上のアクティブは過去28日以内に使われたワークスペース。掲載ガイドラインには週次アクティブ利用者数の条件もあるため、提出時に確認する。
2. 製品ページ、アイコン、画面、料金、権限の説明、セキュリティ情報を登録する。
3. レビュー担当者が自分のワークスペースへインストールできる導線を用意する。接続・投稿・解除を示す短い動画も準備する。自分のSlackワークスペースのログイン情報は渡さない。
4. アプリ設定の「Submit to the Slack Marketplace」で自動検査の問題を解消し、提出する。
5. 指摘へ対応し、承認後に掲載する。公開後のスコープ・構成変更も再審査を前提にする。

確認時点の目安は、初期審査が最大10営業日、新規アプリの機能審査が最大10週間です。確約ではないため、公開日は申請画面の見積もりと指摘対応を考慮して決めます。[審査手順](https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide/)、[掲載条件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/)

## 5. macOSアプリを配布する

配布対象はApple Silicon・macOS 27.0以降です。アドホック署名を付けますが、Developer IDによる開発元の証明やAppleの公証はありません。初回起動がブロックされた場合は、入手元を確認して、システム設定の「プライバシーとセキュリティ」から「このまま開く」を選びます。[Appleの案内](https://support.apple.com/ja-jp/102445)

### ローカルで配布物を作る

1. `dev`で開発し、テストとレビューを終えてから`main`へ反映する。
2. 公開版の`Resources/Info.plist`で`CFBundleShortVersionString`と`CFBundleVersion`を更新する。初版は`0.1.0`・`1`。
3. 次のコマンドでテストとパッケージ作成を行う。

```sh
bash scripts/test.sh
bash scripts/package-release.sh
```

`dist/TimesShot-0.1.0-macos-arm64.zip`とSHA256ファイルが生成されます。ZIPはアプリ本体とMIT LICENSEを含み、端末の設定・下書き・Keychainのデータは含めません。展開後のアドホック署名、バージョン、CPU、リソースを確認してから公開します。

### GitHub ReleaseとHomebrew tap

リリース対象の`main`のコミットにタグを付けます。`v`に続く版番号が`Info.plist`と一致すると、Releaseワークフローが`xcode-27`のmacOSランナーでテスト・パッケージ作成を行い、ZIPとSHA256ファイルを添付したGitHub Releaseを公開します。ブランチへのpushやPRでは起動せず、非公開リポジトリでは実行しません。初版`v0.1.0`はローカルで作成したZIPを公開しています。

次回リリースの例です。事前に版番号を更新した変更を検証し、`main`へ反映します。

```sh
git tag -a v0.1.1 -m 'Times Shot 0.1.1'
git push origin v0.1.1
```

CIを利用せずローカルで公開する場合は、ワークフローを無効にしたうえでZIPとSHA256ファイルを添付します。次は初版で使用した手順です。

```sh
git tag -a v0.1.0 -m 'Times Shot 0.1.0'
git push origin v0.1.0
gh release create v0.1.0 --verify-tag --title 'Times Shot 0.1.0' \
  --notes-file /path/to/release-notes.md \
  dist/TimesShot-0.1.0-macos-arm64.zip \
  dist/TimesShot-0.1.0-macos-arm64.zip.sha256
```

`mmng-a/homebrew-tap`の`Casks/times-shot.rb`に、版番号、公開ZIPのURL、SHA256、対応macOSとCPUを設定します。更新時も同じ項目を変更し、`brew style`・`brew audit --cask`・ZIP取得を確認してpushします。利用者のインストールと更新のコマンドは次のとおりです。

```sh
brew tap mmng-a/tap
brew trust --cask mmng-a/tap/times-shot
brew install --cask mmng-a/tap/times-shot
brew upgrade --cask mmng-a/tap/times-shot
```

## 公開前の確認と公開後の運用

- [x] 既存の利用環境で、ブラウザの認可画面からOAuth接続が完了する。
- [x] 参加済みチャンネルを一覧から選択して登録し、投稿先を切り替えられる。
- [x] 本人名義の文章・画像付き投稿が既存の利用環境で動作する。
- [ ] 開発者とは別の利用者・ワークスペースで、Slack App作成やトークン入力なしに接続できる。
- [ ] 許可の拒否・管理者承認待ち・取り消し・期限切れ・スリープ復帰・再接続を処理できる。
- [ ] 非参加・アーカイブ済みチャンネル等への投稿エラーを実環境で確認した。
- [ ] キュー待機中のトークン更新・接続解除でも誤った接続先へ送らず、結果不明時に重複投稿しない。
- [ ] 下書き・添付・Keychainの保存と削除が公開した説明に一致し、ログに秘密情報や投稿本文を残さない。
- [ ] 配布URLから取得したZIPを別のMac・新しいユーザー環境で開き、Gatekeeper、OAuth復帰、Keychain、通知、ログイン時起動、IME、ショートカットを確認した。
- [ ] 対応macOS・CPU、公開版番号、Slackの掲載可否・審査状況を配布ページに正しく表示した。

公開時は、最終ZIPとSHA256、ソースのコミット、バージョン、対応CPU、署名・公証の有無、検証結果をリリース記録に残します。更新はGitHub Releasesからのダウンロード、またはHomebrewで行います。アプリ内の自動更新は実装していません。Slackの仕様変更と問い合わせへ対応します。
