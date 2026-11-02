# Times Shot

[English](README.md) | [日本語](README.ja.md)

**Post a quick note without opening Slack.**

Times Shot is a macOS app for posting notes and images to Slack channels. Open the composer with `Shift + Space` and send with `⌘Enter`.

Use it to leave a progress note or an idea in your times channel. Paste or drag images into the composer, and keep unfinished drafts when you close it.

## Install

Requires an Apple Silicon Mac running macOS 27.0 or later.

With Homebrew 7 or later, add the tap and trust the cask before the first installation:

```sh
brew tap mmng-a/tap
brew trust --cask mmng-a/tap/times-shot
brew install --cask mmng-a/tap/times-shot
```

Alternatively, extract the ZIP from [GitHub Releases](https://github.com/mmng-a/times-shot/releases) and copy `Times Shot.app` to your Applications folder.

Releases are not signed with Developer ID or notarized by Apple. If macOS blocks the first launch, verify the download source, then choose **Open Anyway** in System Settings → Privacy & Security. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Get started

1. In settings, choose **Connect to Slack** under **General**, then grant permissions in the browser.
2. Open **Channels** in settings and save a destination from the list of channels you belong to.
3. Press `Shift + Space`, check the destination, and send your text or images with `⌘Enter`.

You do not need to create a Slack app or enter tokens or channel IDs. Your workspace may require administrator approval.

| Action | Result |
| --- | --- |
| Shift + Space | Show or hide the composer |
| ⌘Enter | Send |
| ⌘W or the close button | Close, keeping the draft |
| Esc | Discard text and images, then close |

## Before you use it

- One workspace and account can be connected at a time, with multiple saved destinations.
- Credentials stay in this Mac's Keychain; drafts and attachments are stored locally. Times Shot does not retrieve conversation history.
- Failed posts are discarded without automatic retry or recovery. Allow macOS notifications so you can see posting errors.
- Some menu items and messages are displayed in Japanese.

## Documentation

- [User guide](docs/usage.md): images, formatting, queued posts, destination management and Slack permissions
- [Development](docs/development.md): building, testing, diagnostic logs and branch workflow
- [Public release guide (Japanese)](docs/public-release.md)

## License

[MIT License](LICENSE)
