# User guide

[日本語](usage.ja.md) | [README](../README.md)

## Connect to Slack and choose channels

You do not need to create a Slack app or enter tokens or channel IDs.

Some menu items and messages are currently displayed in Japanese.

1. Open **General** in settings and click **Connect to Slack**.
2. In the browser, check the workspace and account, then grant the requested permissions. When authorization finishes, the app shows your connected account under **アカウント** (Account). Your workspace may require administrator approval.
3. Open **Channels** in settings. Use **Search channels to add** to filter by name, then click a row or **＋** to save it as a destination. Public and private channels you belong to are available; archived channels and DMs are excluded.
4. Choose a destination from the menu at the top of the composer. You can save multiple channels; saved channels have a checkmark. Use **Refresh channels** to update the list. To remove a destination, select it under **Saved destinations** and click **−**.
5. Allow macOS notifications to receive posting errors. Times Shot attempts to enable launch at login on its first launch; you can change this in settings. If macOS requires approval, grant it in System Settings.

One workspace and account can be connected at a time. Credentials are stored in Keychain on this Mac. Times Shot checks token expiry when listing channels or sending a post and refreshes tokens as needed. Tokens are not written to configuration files or logs. When reconnection is required, click **Reconnect to Slack** in **General**.

**Disconnect** removes the credentials saved on this Mac and keeps your saved destinations and drafts. To remove the Slack app from a workspace, use Slack's app management separately. Reconnection and disconnection are unavailable while posts are sending or queued, or images are being imported.

## Controls

| Action | Result |
| --- | --- |
| Shift + Space | Show or hide the composer, keeping the draft |
| ⌘W or the window's close button | Close the composer, keeping the draft |
| Esc | Discard the text and images and close. During Japanese text conversion, cancel the conversion first |
| Enter | Insert a newline |
| ⌘Enter or the send button | Queue the post and close the composer |
| ⌘V | Paste images or formatted text |
| ⌘⇧A or the toolbar paperclip | Attach images |
| ⌘, or the menu bar's **設定…** (Settings) | Open settings |
| ⌘B or ⌘I | Toggle bold or italic |
| ⌘⇧X or ⌘⇧C | Toggle strikethrough or code |
| ⌘Z or ⌘⇧Z | Undo or redo editing and formatting |
| Drop images or use the attachment button | Attach images |
| Destination menu at the top of the composer | Switch between saved channels, keeping text and attachments |

The selected destination is kept after posting and restarting the app. Reconnecting to the same workspace and account keeps saved destinations. While a draft exists, you cannot remove its selected destination in settings or connect to a different workspace or account. Posting, attachments and destination selection are also available from the **投稿** (Post) menu.

You can write another post while earlier posts are queued. Posts are sent one at a time in the order they were accepted, with spacing to respect Slack's limits. Each queued post keeps its original destination even if you later switch channels or change settings. The menu bar shows the number of pending posts. Successful posts do not trigger notifications.

If a post fails, a notification shows the beginning of its text, image names and the error. That post is discarded and the queue continues. There is no automatic retry, history or recovery, including when the result of a post is unknown. If notifications are disabled, check the menu bar's error indicator. It keeps only the most recent error and clears when the app quits.

Quitting with posts sending or queued requires confirmation. **破棄して終了** (Discard and Quit) discards the remaining posts, but a post already sending may still complete on Slack. Your draft is kept separately. The queue is not restored after an unexpected exit.

## Images and formatting

PNG, JPEG, GIF and WebP images keep their original data. Other still images supported by ImageIO, including HEIC, TIFF and BMP, are converted to PNG. Animated GIFs are not converted to still images. If a multi-frame image requires conversion, attachment fails with an error rather than silently losing frames. Thumbnails are resized; images sent to Slack are not.

The composer uses macOS's native rich text input. Select text and use a shortcut or the context menu's **書式** (Format) submenu to toggle bold, italic, strikethrough or code. Without a selection, formatting applies to subsequent input. There is no formatting toolbar. Code containing a newline is sent as a Slack code block. Pasting formatted text preserves links.

Deleting all text resets formatting to the default. You can choose a format again while the composer is empty to apply it to new text.

You can also apply formatting while typing. Entering the closing marker removes the markers and formats the enclosed text.

| Input | Result |
| --- | --- |
| `*bold*` or `**bold**` | Bold |
| `_italic_` | Italic |
| `~strikethrough~` or `~~strikethrough~~` | Strikethrough |
| `` `code` `` | Code |
| `- ` or `* ` at the start of a line | Bulleted list |

In a bulleted list, Enter creates the next item. Enter on an empty item returns to a normal paragraph; Backspace at the start of an item also removes the list formatting. Automatic formatting can be undone with ⌘Z. It does not run during Japanese text conversion or inside code. Type a backslash immediately before a marker to keep it as text.

Drafts preserve text and formatting across restarts. For quotes and numbered lists, type prefixes such as `> ` or `1. `. Text is converted to Slack-compatible formatting when sent; font family, size, color and underline are not sent. Headings, tables, HTML, inline images and mention suggestions are not supported. Formatting follows [Slack's mrkdwn specification](https://docs.slack.dev/messaging/formatting-message-text/).

Drafts and attached images are stored in `~/Library/Application Support/TimesShot/`. Images are deleted after their post finishes or when discarded.

## Slack permissions and connection

Times Shot requests these four User Token Scopes. It does not request conversation history scopes.

| Scope | Purpose |
| --- | --- |
| `chat:write` | Post text as you |
| `files:write` | Upload and share images |
| `channels:read` | Read basic information about public channels |
| `groups:read` | Read basic information about private channels you belong to |

For the connection and channel listing APIs, see [PKCE](https://docs.slack.dev/authentication/using-pkce/) and [users.conversations](https://docs.slack.dev/reference/methods/users.conversations/). For posting, see [chat.postMessage](https://docs.slack.dev/reference/methods/chat.postMessage/) and [files.completeUploadExternal](https://docs.slack.dev/reference/methods/files.completeUploadExternal/).

