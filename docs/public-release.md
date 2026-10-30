# 一般公開の手順

最終確認日: 2026-10-31

利用者がSlack Appを作成したり、トークンをコピーしたりせずにTimes Shotを使えるようにするための公開手順です。本書は今後の対応計画であり、OAuth接続・Slack審査・Appleの公証は完了していません。申請時にはリンク先の最新要件を確認してください。

## 公開する構成

- 開発者が管理するSlack AppをOAuthで各利用者のワークスペースへ接続する。
- 利用者は「Slackに接続」からブラウザで権限を許可し、アプリへ戻る。
- 本人名義で、本人が入力した文章と選択した画像を登録チャンネルへ送る。会話履歴の取得・閲覧は行わない。
- macOSアプリはDeveloper IDで署名・公証し、HTTPSの配布ページからZIPで直接配布する方法を基本案とする。

Slackとの接続には投稿権限を取得するOAuthを使います。本人確認用の「Sign in with Slack」だけでは投稿できません。独立したサービスアカウントを必要としない限り、別のログイン機能は設けません。[Slack OAuth](https://docs.slack.dev/authentication/installing-with-oauth/)

Slack Marketplaceへの掲載と、macOSアプリの配布先は別です。直接配布でもSlack側の配布条件を満たす必要があります。Mac App Storeを選ぶ場合は、別途App Sandboxへの対応とAppleのApp Reviewを計画します。

## 現状との差分

| 項目 | 現状 | 公開前に必要な対応 |
| --- | --- | --- |
| Slack接続 | 利用者がUser OAuth Tokenを手動入力 | 開発者所有のSlack AppによるOAuth接続 |
| 認証情報 | Keychainにアクセストークン1件を保存 | 有効期限・refresh token・接続したworkspace/user IDも管理 |
| トークンの検証 | `xoxp-`接頭辞を要求 | ローテーションされるユーザートークンにも対応 |
| 送信キュー | 受付時のトークンと投稿先を保持 | 接続先を固定したまま、送信時に有効なトークンを取得 |
| チャンネル登録 | 名前・IDを手動入力 | 現方式を利用可能。一覧選択を追加する場合だけ権限を追加 |
| アプリ署名 | 既定はアドホック署名 | Developer ID・Hardened Runtime・タイムスタンプ・公証 |
| 公開情報 | README | 配布ページ、接続手順、プライバシーポリシー、問い合わせ先 |

主な変更対象は[SlackClient.swift](../Sources/TimesShotCore/SlackClient.swift)、[Post.swift](../Sources/TimesShotCore/Post.swift)、[AppModel.swift](../Sources/TimesShot/AppModel.swift)、[SettingsModel.swift](../Sources/TimesShot/SettingsModel.swift)、[Storage.swift](../Sources/TimesShot/Storage.swift)、[Info.plist](../Resources/Info.plist)、[build-app.sh](../scripts/build-app.sh)です。

## 1. Slackへの掲載可否を確認する

Slackは「Slackクライアント機能の再現」「第三者製Slackクライアント」をMarketplaceの掲載対象外としています。Times Shotの投稿専用という機能範囲が対象になるかは未確認です。会話履歴を取得しないことだけで掲載が保証されるわけではありません。[掲載条件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/)

参考にできる先例は次のとおりです。

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

## 2. OAuth接続を実装する

### Slack Appと権限

開発者所有の配布用Slack Appを用意し、開発・検証用のものとは分けます。本人名義で投稿するため、Bot Token ScopesではなくUser Token Scopesを設定します。

| 権限 | 用途 |
| --- | --- |
| [`chat:write`](https://docs.slack.dev/reference/scopes/chat.write/) | 本人名義のテキスト投稿 |
| [`files:write`](https://docs.slack.dev/reference/scopes/files.write/) | 本人が選択した画像のアップロード・共有 |
| `channels:read` / `groups:read` | 公開／参加済みプライベートチャンネルの一覧選択を実装する場合のみ追加 |

投稿に会話履歴の権限は不要です。`*:history`、`search:read`、`files:read`などを追加しません。ただし、`chat:write`や`files:write`は投稿以外の編集・削除APIにも使える権限なので、許可画面や説明文で「送信以外の権限は一切ない」とは説明しません。

### macOSアプリからの接続

サーバーにトークンを保管しない構成として、Slackのネイティブアプリ向けPKCEを基本案にします。認証専用の常設サーバーは必須ではありません。Slack AppでPKCEを有効化し、アプリへ戻すURI（例: `timesshot://oauth/callback`。採用時に確定）を登録します。PKCEの有効化は、Slackサポートへの連絡なしでは元に戻せません。[PKCEの仕様](https://docs.slack.dev/authentication/using-pkce/)

1. 接続操作ごとにランダムな`state`と`code_verifier`を作り、`S256`の`code_challenge`を生成する。
2. `/oauth/v2/authorize`へ`client_id`、`user_scope`、`redirect_uri`、`state`とPKCEの引数を付け、ブラウザで許可を求める。
3. アプリでコールバックを受け、戻り先と`state`を検証する。キャンセル・拒否も処理する。
4. `oauth.v2.access`へ認可コード・同じ`redirect_uri`・`code_verifier`を渡す。PKCEでは`client_secret`をアプリへ埋め込まない。
5. 応答のユーザートークン・権限・workspace/user IDを確認し、認証情報をKeychainへ保存する。接続先はOAuth応答から確定する。

カスタムURIへの復帰にはPKCEが必須で、Bot権限は要求できません。今回の本人名義の投稿はユーザートークンで実装します。Webの戻り先を採用する場合はHTTPSを使い、その方式に合わせて設計し直します。[PKCE](https://docs.slack.dev/authentication/using-pkce/)、[OAuth](https://docs.slack.dev/authentication/installing-with-oauth/)

### トークン更新と接続解除

カスタムURIを使うPKCE接続では、Slack側の通常の設定にかかわらずローテーション対象のトークンが発行されます。アクセストークンは12時間、PKCEで発行されるrefresh tokenは30日で失効するため、長期間使わなかった場合の再接続も必要です。更新応答では新しいrefresh tokenを保存し、同じ接続の更新を並行実行しません。[ローテーション](https://docs.slack.dev/authentication/using-token-rotation/)、[PKCE](https://docs.slack.dev/authentication/using-pkce/)

- `expires_in`に従って投稿前に更新し、スリープ復帰・期限切れ・権限取り消しを処理する。
- キューに記録した投稿先・接続IDを変えず、その接続の最新トークンで送る。再認証で別のワークスペースやユーザーになった場合に、待機中の投稿を移し替えない。
- 更新に失敗した場合は再接続へ案内する。投稿結果が不明なものを自動再送しない。
- 接続解除では端末の認証情報を削除する。Slack側の認可取り消し方法も案内し、ワークスペース全体のアンインストールとは区別する。
- トークン、認可コード、refresh token、PKCEの秘密値、アップロードURLをログへ出さない。

## 3. 公開情報を用意して試験配布する

ログイン不要のHTTPSページに、製品説明、対応macOS・CPU、ダウンロード、接続手順、プライバシーポリシー、問い合わせ先を用意します。Marketplace用の製品ページはREADMEやリポジトリのURLだけでは代用できません。サポートは別サービスへの登録なしで問い合わせできるようにします。[公開ページの要件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/#pages-associated-with-your-app)

プライバシーポリシーには、Keychainの認証情報、端末内の下書き・画像・チャンネル設定、Slackへ送るデータ、エラー通知に表示する本文冒頭・画像名、診断ログ、保持期間と削除方法を実装に合わせて記載します。「会話履歴を取得しない」と「入力内容を端末に保存しない」は別です。

OAuth対応版と署名・公証済みの試験版を用意した後、Slack Appの「Manage Distribution」でチェック項目を満たし、「Activate Public Distribution」を有効にします。開発用とは別のワークスペースで、初回接続から利用・解除まで確認します。

未掲載での配布は初期利用者との試験に使えます。商用配布はMarketplaceへの提出・承認を前提に計画し、未掲載のままの本格配布や、利用者ごとにSlack Appを作らせる方法を審査の代わりにしません。利用先が管理者承認やMarketplace掲載を必須としている場合は、その制限に従います。[配布方法と管理者承認](https://docs.slack.dev/app-management/distribution/)

## 4. Slack Marketplaceへ申請する

1. 10以上のアクティブワークスペースで利用・検証する。審査ガイド上のアクティブは過去28日以内に使われたワークスペース。週次利用者数の条件も掲載ガイドラインにあるため、提出時の要件を確認する。
2. 製品ページ、アイコン、画面、料金、権限の説明、セキュリティ情報を登録する。
3. レビュー担当者が自分のワークスペースへインストールできる導線を用意する。接続・投稿・解除を示す短い動画も準備する。自分のSlackワークスペースのログイン情報は渡さない。
4. アプリ設定の「Submit to the Slack Marketplace」で自動検査の問題を解消し、提出する。
5. 指摘へ対応し、承認後に掲載する。公開後のスコープ・構成変更も再審査を前提にする。

確認時点の目安は、初期審査が最大10営業日、新規アプリの機能審査が最大10週間です。確約ではないため、公開日は申請画面の見積もりと指摘対応を考慮して決めます。[審査手順](https://docs.slack.dev/slack-marketplace/slack-marketplace-review-guide/)、[掲載条件](https://docs.slack.dev/slack-marketplace/slack-marketplace-app-guidelines-and-requirements/)

## 5. macOSアプリを署名・公証して配布する

直接配布にはApple Developer ProgramのDeveloper ID Application証明書を用意します。Appleの公証はマルウェア等の自動検査であり、Mac App StoreのApp ReviewやSlackの審査とは別です。[Appleの公証手順](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

現在のSwift Packageとビルドスクリプトを使う場合の手動実行例です。公開前に`Info.plist`のバージョン・ビルド番号を更新し、配布対象のCPUでビルドします。現在のスクリプトはUniversal Binaryの作成を指定していないため、Apple Silicon・Intelの両対応を自動的に保証しません。

### ビルドと署名

証明書名の例を実際の名前へ置き換え、リポジトリのルートで実行します。現行の`build-app.sh`はHardened Runtimeとタイムスタンプを指定していないため、公開用には後段の署名が必要です。

```sh
bash scripts/test.sh
SIGNING_IDENTITY='Developer ID Application: NAME (TEAM_ID)' bash scripts/build-app.sh
codesign --force --options runtime --timestamp \
  --sign 'Developer ID Application: NAME (TEAM_ID)' 'dist/Times Shot.app'
codesign --verify --deep --strict 'dist/Times Shot.app'
codesign --display --verbose=4 'dist/Times Shot.app'
```

証明書がDeveloper ID Applicationで、Hardened Runtimeとタイムスタンプが付いていることを確認します。今後ヘルパーやフレームワークを同梱する場合は、それらを内側から署名する手順も必要です。

### 公証と配布ZIPの作成

初回だけ、`notarytool store-credentials`の対話入力で公証用の認証情報をKeychainへ保存します。パスワードをスクリプトやGitへ記録しません。

```sh
xcrun notarytool store-credentials 'TimesShot-notary'
```

```sh
ditto -c -k --keepParent 'dist/Times Shot.app' /private/tmp/TimesShot-notarization.zip
xcrun notarytool submit /private/tmp/TimesShot-notarization.zip \
  --keychain-profile 'TimesShot-notary' --wait
```

結果が`Accepted`の場合だけ次へ進みます。失敗時は返されたsubmission IDで`notarytool log`を取得し、原因を修正して再提出します。

```sh
xcrun stapler staple 'dist/Times Shot.app'
xcrun stapler validate 'dist/Times Shot.app'
codesign --verify --deep --strict 'dist/Times Shot.app'
spctl --assess --type execute --verbose=4 'dist/Times Shot.app'
ditto -c -k --keepParent 'dist/Times Shot.app' 'dist/TimesShot.zip'
```

公証チケットはZIPではなく`.app`へ付け、その後で配布ZIPを作り直します。署名後のアプリ内容は変更しません。[Appleのカスタム公証手順](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 公開前の確認と公開後の運用

- [ ] 開発者とは別の利用者・ワークスペースで、Slack App作成やトークン入力なしに接続できる。
- [ ] 許可の拒否・管理者承認待ち・取り消し・期限切れ・スリープ復帰・再接続を処理できる。
- [ ] 本人名義の文章・画像付き投稿とチャンネル切り替えが正しく動く。非参加・アーカイブ済みチャンネル等のエラーを確認した。
- [ ] キュー待機中のトークン更新・接続解除でも誤った接続先へ送らず、結果不明時に重複投稿しない。
- [ ] 下書き・添付・Keychainの保存と削除が公開した説明に一致し、ログに秘密情報や投稿本文を残さない。
- [ ] 配布URLから取得したZIPを別のMac・新しいユーザー環境で開き、Gatekeeper、OAuth復帰、Keychain、通知、ログイン時起動、IME、ショートカットを確認した。
- [ ] 対応macOS・CPU、公開版番号、Slackの掲載可否・審査状況を配布ページに正しく表示した。

公開時は、最終ZIP、ソースのコミット、バージョン、対応CPU、公証submission ID、検証結果をリリース記録に残します。初期の更新方法は最新版ZIPの手動ダウンロードでよく、自動更新機構は別の実装として扱います。新しい版ごとに署名・公証を行い、Slackの仕様変更と問い合わせへ対応します。
