# Releasing Islet

Releases are built by the [Release workflow](../.github/workflows/release.yml). Pushing a tag such as `v0.2.0` builds Islet, signs it with a Developer ID certificate, notarizes it, and drafts a GitHub release with:

- `Islet-<version>.dmg`, the download for new users,
- `Islet-<version>.zip`, the archive Sparkle installs for existing users,
- `appcast.xml`, the update feed that installed copies read from the latest release,
- `SHA256SUMS.txt`.

## One-time setup

1. **Apple Developer Program.** Join it at [developer.apple.com/programs](https://developer.apple.com/programs/). Signing and notarization need a paid membership.
2. **Developer ID certificate.** In Xcode › Settings › Accounts, select your team, click Manage Certificates, and add a *Developer ID Application* certificate. Then in Keychain Access › My Certificates, export it together with its private key as a `.p12` file with a password.
3. **Notarization password.** At [account.apple.com](https://account.apple.com), under Sign-In and Security › App-Specific Passwords, create a password for notarization.
4. **Sparkle keys.** Download [Sparkle](https://github.com/sparkle-project/Sparkle/releases) and run `./bin/generate_keys`. It stores a private key in your keychain and prints the public key. Put the public key into `SPARKLE_PUBLIC_KEY` in `project.yml` and commit it. Export the private key with `./bin/generate_keys -x sparkle-private-key` for the next step, then delete the file. Keep the key in your keychain (or another safe place): without it, existing installs can't be updated anymore.
5. **Repository secrets.** Under Settings › Secrets and variables › Actions, add:

   | Secret | Value |
   | --- | --- |
   | `DEVELOPER_ID_CERTIFICATE` | The `.p12` file as base64: `base64 -i DeveloperID.p12 \| pbcopy` |
   | `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password of the `.p12` file |
   | `TEAM_ID` | Your 10-character team ID from [developer.apple.com/account](https://developer.apple.com/account) › Membership details |
   | `NOTARY_APPLE_ID` | The Apple ID email of your developer account |
   | `NOTARY_PASSWORD` | The app-specific password from step 3 |
   | `SPARKLE_PRIVATE_KEY` | The contents of `sparkle-private-key` from step 4 |

   With the GitHub CLI: `gh secret set TEAM_ID` and so on; for files, `gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key`.

6. **Dry run.** Run the workflow from Actions › Release › Run workflow. It builds, signs and notarizes without publishing anything and keeps the files as a workflow artifact for a week. Download the DMG with a browser, open it and launch Islet: macOS should open it without a Gatekeeper warning.

## Each release

1. Set `MARKETING_VERSION` in `project.yml` to the new version and merge that change into `main`. The build number is the number of commits on `main`, so it always increases.
2. Tag the merge commit and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

   The workflow refuses to run when the tag doesn't match `MARKETING_VERSION` or when `SPARKLE_PUBLIC_KEY` is empty.
3. Open the drafted release on GitHub, edit the generated notes, and publish it. Publishing makes its `appcast.xml` the feed that installed copies check, so they offer the update within a day.
4. Update the Homebrew cask (below).

## Homebrew

Until the repository is popular enough for the official [homebrew/cask](https://github.com/Homebrew/homebrew-cask) (it asks for roughly 75 stars), ship the cask from your own tap: create a public repository `MariSchn/homebrew-tap` with `Casks/islet.rb`:

```ruby
cask "islet" do
  version "0.1.0"
  sha256 "<sha256 of Islet-0.1.0.dmg from SHA256SUMS.txt>"

  url "https://github.com/MariSchn/Islet/releases/download/v#{version}/Islet-#{version}.dmg"
  name "Islet"
  desc "Plugin host for the MacBook notch"
  homepage "https://github.com/MariSchn/Islet"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Islet.app"

  uninstall quit: "com.marischn.Islet"

  zap trash: [
    "~/Library/Application Support/Islet",
    "~/Library/Preferences/com.marischn.Islet.plist",
  ]
end
```

Users then install with `brew install --cask marischn/tap/islet`. For each release, update `version` and `sha256`.
