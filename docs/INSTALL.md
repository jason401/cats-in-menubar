# Installing the prebuilt app

Requires macOS 14 or later and an Apple silicon Mac for the arm64 download.

**The app ZIP is all you need. SHA256SUMS.txt is optional and is not needed to install or run the app.**

1. Get the app ZIP from https://github.com/jason401/cats-in-menubar/releases .
2. Unzip it, quit any running copy, and drag Cats in Menubar.app into Applications. Open it.
3. This is a locally signed app, **not Apple Developer ID signed or notarized**. Only if you trust the source and exact download, follow System Settings → Privacy & Security → Open Anyway after the first launch is blocked. Follow Apple's guidance: https://support.apple.com/en-us/102445 . Do not disable Gatekeeper or blanket-remove quarantine. Stop if macOS reports malware, damage or tampering.
4. Grant Accessibility in Privacy & Security (or Device Control and Data Access on some macOS versions).
5. **For prebuilt downloads, turn off update checks in Settings → General → Updates.** Download future ZIPs manually and replace the app while it is quit. The current app's updater builds from source and requires the same local signing key as the installed app; a publisher-signed download does not share your Mac's key. Permission may need to be granted again after replacement.

The app accesses menu layout geometry and local system statistics. Optional Location permission enables the Wi-Fi name; location coordinates are not requested. Update checks contact GitHub. No screen capture or AI API is required.

To use source-built updates, follow the Git clone / local signing instructions in README.md. The automatic GitHub source ZIP is for source inspection; it lacks the Git metadata required by the build script. A prebuilt app with a different signature must be quit and removed before installing a locally built replacement.

This is free software under MIT with an Apache-2.0-derived scroll feature. Keep LICENSE, THIRD_PARTY_NOTICES.md and LICENSES/Apache-2.0.txt when redistributing. No warranty is provided.

Optional integrity check: download SHA256SUMS.txt from the same release, put it beside the ZIP, and run `shasum -a 256 -c SHA256SUMS.txt` there. This checks for a damaged download, not the publisher's identity.
