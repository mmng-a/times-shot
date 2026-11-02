# Times Shot

[English](README.md) | [日本語](README.ja.md)

Times Shot is a macOS menu bar app for posting notes and images to Slack channels. Use it to share progress in your times channel or send an image.

Open the composer with `Shift + Space` and send with `⌘Enter`. Your draft is kept when you close the composer, so you can return to your work and finish writing later.

## Install

Requires an Apple Silicon Mac running macOS 27.0 or later.

With Homebrew 7 or later, run these commands to add the tap, trust the Times Shot cask and install the app:

```sh
brew tap mmng-a/tap
brew trust --cask mmng-a/tap/times-shot
brew install --cask mmng-a/tap/times-shot
```

Alternatively, download and extract the ZIP from [GitHub Releases](https://github.com/mmng-a/times-shot/releases), then copy `Times Shot.app` to your Applications folder.

The app is not signed with an Apple Developer ID certificate or notarized. macOS blocks its first launch. Open System Settings → Privacy & Security and choose **Open Anyway** to run it. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Usage

1. In settings, choose **Connect to Slack** under **General**. Check the workspace and requested permissions in the browser, then authorize the app.
2. Open **Channels** in settings and save a destination from the list of channels you belong to.
3. Press `Shift + Space`, check the destination and write your post. Paste or drag images into the composer, then press `⌘Enter` to send.

You do not need to create a Slack app or enter tokens or channel IDs. Your workspace may require administrator approval for the app.

| Action | Result |
| --- | --- |
| Shift + Space | Show or hide the composer |
| ⌘Enter | Send |
| ⌘W or the close button | Close, keeping the draft |
| Esc | Discard text and images, then close |

## Notes

- One workspace and account can be connected at a time, with multiple saved destinations.
- Credentials stay in this Mac's Keychain; drafts and attachments are stored locally. Times Shot does not retrieve conversation history.
- Failed posts are discarded without automatic retry or recovery. Allow macOS notifications so you can see posting errors.
- Some menu items and messages are available only in Japanese.

## Documentation

- [User guide](docs/usage.md): images, formatting, queued posts, destination management and Slack permissions
- [Development](docs/development.md): building, testing, diagnostic logs and branch workflow
- [Public release guide (Japanese)](docs/public-release.md)

## License

[MIT License](LICENSE)
