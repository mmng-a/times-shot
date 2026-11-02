# Development

[README](../README.md)

## Build

The interface uses SwiftUI, with AppKit and Carbon for windows, input and shortcuts. There are no external library dependencies.

Select Xcode 27 or later, then run:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

Copy `dist/Times Shot.app` to your Applications folder and open it. The default build uses an ad-hoc signature for local use. If you have a signing certificate, you can select it with the `SIGNING_IDENTITY` environment variable.

## Validation

`bash scripts/test.sh` runs the app and core test suites. Network tests use mocks; paste tests use a dedicated pasteboard. Tests do not post to Slack or change the normal clipboard.

For a release, also check OAuth, text and image posts, IME input, shortcuts, full-screen behavior, notifications and launch at login on a real Mac.

## Diagnostic logs

Slack communication failures are recorded in macOS's unified log under the `Slack` category. The log includes API names, HTTP status, Slack request IDs and argument error details. The `OAuth` category records connection stages, such as the browser reply, authorization code exchange and credential storage, plus error domains and codes on failure. Logs do not include request bodies, image data, credentials, authorization codes, callback URLs or upload URLs. To inspect the app's logs:

```sh
log show --last 1h --style compact --predicate 'process == "TimesShot" AND subsystem == "jp.sendocorp.TimesShot" AND (category == "Slack" OR category == "OAuth")'
```

## Branches and releases

Work on `dev`, then move verified and reviewed changes to `main`. Pushing a version tag such as `v0.1.0` in the public repository triggers the [Release workflow](../.github/workflows/release.yml) to test, build, package the ZIP and publish a GitHub Release on macOS. Branch pushes and pull requests do not trigger it. The workflow fails if the tag and `Info.plist` version do not match. Update the version and SHA256 in the Homebrew tap after each release. See the [public release guide (Japanese)](../docs/public-release.md#5-macosアプリを配布する) for packaging and tap maintenance.

