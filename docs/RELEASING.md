# Releasing the app

The app is distributed through the App Store (and TestFlight before it). See `APP_STORE.md` for the App Store Connect
setup, the review information and the listing.

## Version numbers

In the project (target HumblePlanning, Debug and Release), before each release:

- `MARKETING_VERSION`: `major.minor.patch`, for example `1.2.0`. The server compares it with its minimum app version,
  which is the same for the Android and iOS apps: the two apps share their version numbers when a change of the API
  requires them, so raise the major or minor version in step with the Android app when the server raises its minimum.
- `CURRENT_PROJECT_VERSION`: the build number, raised for every upload to App Store Connect (TestFlight included). It
  must always increase.

## Building and uploading

1. From a committed state of `main`: `node tools/textes.mjs` leaves no change, `cd Packages/HumbleCore && swift test`
   passes, the app builds without warnings, and `tools/ui-tests.sh` passes against the test server.
2. In Xcode: Product > Archive, then Distribute App > App Store Connect > Upload.
3. In App Store Connect: test the build with TestFlight, then add it to the version, fill "What's New" from
   `CHANGELOG.md` and submit it for review.

## Publishing

1. Change the version and add its section to `CHANGELOG.md` in a pull request (`main` is protected, commits signed off),
   merge it, then tag the merged commit: `git pull`, `git tag v1.2.0` and `git push origin v1.2.0`.
2. From the tagged commit, `tools/build-ipa.sh` builds the unsigned build for side-loading:
   `build/ipa/humbleplanning-1.2.0-unsigned.ipa` and its `.sha256`.
3. On GitHub: Releases > Draft a new release, tag `v1.2.0`, title `Humble Planning for iOS 1.2.0`, the changes in a few
   lines, the App Store link once the app is published, and the two files of `build/ipa/` (or
   `gh release create v1.2.0 build/ipa/* --title "Humble Planning for iOS 1.2.0" --notes-file <notes>`).

## Updates on the devices

- The App Store updates the app by itself (unless the user turned automatic updates off).
- **Forcing an update**: on each Humble Planning server, Settings > General > Mobile app, set "Minimum app version" to
  the new version. An older app then shows "Update required" and its button opens the App Store page set in "iOS app
  download page" (or the app's own page when it is empty).

## Checks before publishing

- `cd Packages/HumbleCore && swift test`, and the app builds without warnings.
- `tools/ui-tests.sh` against the local test server (see the script), on an iPhone and on an iPad simulator.
- Install the TestFlight build over the previous version: it must update without signing out.
