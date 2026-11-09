## What does this change?

<!-- A short description of the change and why it is needed. -->

Closes #

## How was it tested?

<!-- Steps you followed, automated tests added or updated, devices or simulators used. -->

## Screenshots

<!-- For interface changes: before and after, iPhone and iPad if the layout differs, light and dark if colours change. -->

## Checklist

- [ ] One topic only, branched from `main`.
- [ ] `swift test` (in `Packages/HumbleCore`) passes and the app builds without warnings.
- [ ] User-facing texts are rows of `tools/textes.mjs`, in all four languages, and `node tools/textes.mjs` leaves no change.
- [ ] Changes to screens or to what the app sends were tried on a simulator against the test server (`tools/ui-tests.sh`).
- [ ] Documentation updated when behaviour or configuration changes (`README.md`, `docs/`).
- [ ] No secrets, credentials or personal data.
- [ ] Every commit is signed off (`git commit -s`, see [CONTRIBUTING.md](https://github.com/Malfhas/HumblePlanning-iOS/blob/main/CONTRIBUTING.md#developer-certificate-of-origin-dco)).
