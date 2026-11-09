# Contributing to Humble Planning for iOS

Thank you for your interest in Humble Planning! Bug reports, ideas, translations and code are all welcome. This guide explains how to get started and what we check before a change is merged.

By taking part in this project, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug**: open an [issue](https://github.com/Malfhas/HumblePlanning-iOS/issues). Please search existing issues first. A bug of the server or of the web application belongs to the [server repository](https://github.com/Malfhas/HumblePlanning/issues).
- **Suggest an idea** or **ask a question**: use the [Discussions](https://github.com/Malfhas/HumblePlanning/discussions) of the main repository.
- **Translate**: the app is available in English, French, Spanish and German (see [Translations](#translations)).
- **Write code**: pick an issue labelled `good first issue` or `help wanted`, or propose your own change.
- **Report a security vulnerability**: never in a public issue. Follow the [security policy](SECURITY.md).

For anything larger than a small fix, please open an issue or a discussion first, so that we can agree on the approach before you spend time on it.

## Development setup

Requirements: a Mac with Xcode 26 or later and the iOS platform, Node.js (texts and icon) and Git.

```bash
git clone https://github.com/<your-account>/HumblePlanning-iOS.git
cd HumblePlanning-iOS
open HumblePlanning.xcodeproj
```

A debug build needs no Apple Developer account on the simulator. The app needs a Humble Planning server with the mobile API; debug builds may reach one in clear text on the Mac (`http://localhost:…`) or on the local network.

## Project conventions

- **Language**: code, comments, identifiers, log messages and test names are in English.
- **User-facing text** never lives in the code: every message is a row of `tools/textes.mjs`, in **all four languages** (English, French, Spanish and German), and `node tools/textes.mjs` generates the String Catalogs. Never edit the `.xcstrings` files in Xcode. Screens use the generated symbols (`Text(.tabPlanning)`, `String(localized: .nTasks(3))`).
- **Logic in the package**: anything that can be tested without drawing goes to `Packages/HumbleCore`, with tests.
- **Permissions**: the server decides. The app hides what the account may not do (`Access.swift`), but never relies on that alone.
- **Security**: no secrets, credentials or personal data in the code, the tests or the fixtures.
- **Scope**: one topic per pull request.

## Checks before opening a pull request

```bash
node tools/textes.mjs && git diff --exit-code HumblePlanning/Resources   # texts generated from tools/textes.mjs
(cd Packages/HumbleCore && swift test)                                  # unit tests
xcodebuild -project HumblePlanning.xcodeproj -scheme HumblePlanning \
  -destination 'platform=iOS Simulator,name=iPhone 17' build            # the app builds without warnings
```

The interface tests (`HumblePlanningUITests`) drive the app against a real, disposable server: the test server of the
Android repository (Docker, `http://localhost:3100`, with stand-ins for the AI provider and push), filled with a
fictitious company. `tools/ui-tests.sh` starts it, fills it and runs them; without it they are skipped:

```bash
HP_SERVER_SRC=../HumblePlanning HP_ANDROID_REPO=../HumblePlanning-Android tools/ui-tests.sh "iPhone 17"
```

Each test starts the app as just installed and signs in with a test account; what a test creates is titled
"[iOS test] …" and deleted by the test. Screenshots of every step go to `build/ui-shots/`.

## Pull requests

1. Fork the repository and create a branch from `main` (for example `fix/grid-scroll-on-ipad`).
2. Make your change, with tests when it changes behaviour.
3. Sign off every commit (see [Developer Certificate of Origin](#developer-certificate-of-origin-dco)).
4. Open a pull request against `main`: what changes, why, how you tested it, and screenshots for interface changes (iPhone, and iPad when the layout differs).

Pull requests are squash-merged: the title of the pull request becomes the commit message on `main`. The maintainer may ask for changes, and keeps the final decision on what is merged. `CHANGELOG.md` is updated by the maintainer when a release is prepared.

## Developer Certificate of Origin (DCO)

Humble Planning uses the [Developer Certificate of Origin](DCO) instead of a contributor license agreement. You keep the copyright of your contribution, which is distributed under the project license: AGPL-3.0-or-later with the [additional permission](LICENSE-EXCEPTION.md) for app stores. By signing off a commit, you certify that you wrote it or otherwise have the right to submit it under that license.

```bash
git commit -s -m "Fix the week number on the grid header"
```

Use your real name or a consistent public identity, and an e-mail address you can be contacted at; anonymous contributions cannot be accepted.

## AI-assisted contributions

AI coding assistants are welcome here: the maintainer uses them to develop Humble Planning too. The same rules apply to every contribution, however it was written: you remain responsible for what you submit, so make sure you understand every line, that it is tested and passes the checks, and that you have the right to submit it under the project license, as certified by your DCO sign-off. Mentioning the tools you used in the pull request is appreciated, not required.

## Translations

Translations live in `tools/textes.mjs`, one row per text with its English, French, Spanish and German versions; most of them are shared with the Android app. To improve a translation, edit the values (never the keys), run `node tools/textes.mjs` and commit both the script and the generated catalogs.

## License

By contributing, you agree that your contributions are licensed under the [GNU Affero General Public License v3.0 or later](LICENSE), with the [additional permission](LICENSE-EXCEPTION.md) for app stores.
