# Packaging

`minmacs.rb.in` is the Homebrew cask for the tap, FRIKKern/homebrew-tap. `release.sh` fills it from the zip it built and writes `minmacs.rb` next to the zip. Nothing in this repo writes to the tap.

## Publishing a release

`release.sh` stops before anything leaves this Mac. A person does the rest:

1. Read `RELEASE_NOTES.md` in the release folder that `release.sh` printed.
2. Tag the commit that `release.txt` names, `git tag -a v<version>`, and push the tag.
3. Make the GitHub release for the tag with those notes, and attach `MinMacs-<version>.zip` and `MinMacs-<version>.zip.sha256`.
4. Copy `minmacs.rb` to `Casks/minmacs.rb` in the tap and commit it there.

The tap holds a formula named `minmacs` for 1.x, which builds from source. A cask and a formula with the same name make `brew install frikkern/tap/minmacs` pick the formula. When the cask goes in, the formula comes out of the tap in the same commit, or moves to a name such as `minmacs@1`.

`.github/workflows/release.yml` attaches `MinMacs.app.zip` on a tag push. The cask's URL names `MinMacs-<version>.zip`, the file `release.sh` makes. Upload that file, or change the workflow to make the same name.

## Signing and notarizing, issue #40

`build.sh` signs ad-hoc. A Developer ID signature and notarization need an Apple Developer account, decision 13. `release.sh` calls a hook for both when `MINMACS_SIGN_HOOK` names an executable:

```sh
MINMACS_SIGN_HOOK=packaging/sign.sh ./release.sh
```

The hook is called twice:

- `<hook> sign <path to MinMacs.app>` signs the app in place, with the hardened runtime. It exits 0 on success.
- `<hook> notarize <path to the zip> <path to MinMacs.app>` sends the zip to the notary service, waits for it, and staples the ticket to the app. It exits 0 on success.

After each call `release.sh` checks the app with `codesign --verify --deep --strict`. After `notarize` it zips the stapled app again. The Gatekeeper check, `spctl --assess`, is the hook's, since an ad-hoc build always fails it. A hook that exits non-zero stops the release. Without a hook the notes and the cask say the build is ad-hoc signed and not notarized. `packaging/sign.sh.example` shows the commands #40 is expected to use. It is not run by anything.
