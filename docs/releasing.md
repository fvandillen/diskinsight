# Releases and Homebrew

DiskInsight is distributed as an Apple Silicon `.app` in a ZIP archive.
The Homebrew cask lives in
[fvandillen/homebrew-tap](https://github.com/fvandillen/homebrew-tap).
The application repository and tap are both public and MIT licensed.

## Publish a release

Run the **Release** workflow from GitHub Actions on the intended branch or commit:

```bash
gh workflow run release.yml --repo fvandillen/diskinsight \
  --ref main -f version=1.0.1
```

The workflow validates the version, builds the app, embeds the MIT license,
ad-hoc signs it, runs headless smoke tests, and creates a `v1.0.1` tag and release
at the checked-out commit. It uploads `DiskInsight-1.0.1-arm64.zip` and its SHA-256
checksum. Existing releases are not overwritten.

For a local build of the same archive:

```bash
./Scripts/package_release.sh 1.0.1
./Scripts/smoke_test.sh
```

The first release was packaged locally using this script. Build outputs stay in
the ignored `build/` directory, not in Git.

## Update the tap

After the release is public, download its archive and compute the checksum:

```bash
gh release download v1.0.1 --repo fvandillen/diskinsight \
  --pattern 'DiskInsight-1.0.1-arm64.zip' --dir /tmp/diskinsight-release
shasum -a 256 /tmp/diskinsight-release/DiskInsight-1.0.1-arm64.zip
```

Update `version` and `sha256` in the tap's `Casks/diskinsight.rb`, then commit and
push. Verify the checksum against the actual downloaded asset, not a separate
local rebuild. The cask's URL derives from its version.

```bash
brew update
brew audit --cask fvandillen/tap/diskinsight
brew install --cask fvandillen/tap/diskinsight
```

Tap updates are intentionally manual: the application workflow needs no
cross-repository personal access token. Do not replace an asset after publishing
its checksum; ship a new version instead.

## Signing

Current releases are ad-hoc signed, **not Developer ID signed or notarized**.
Homebrew preserves quarantine and Gatekeeper checks. Users may need to approve
the first launch in System Settings > Privacy & Security > Open Anyway.
Do not instruct users to disable Gatekeeper or strip quarantine.

A future notarized release needs an Apple Developer ID certificate, secure
signing credentials, notarization, and stapling before packaging. Never put
certificates or credentials in either repository.
