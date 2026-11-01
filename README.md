# Cats in Menubar

Tiny cats living in the empty space of your Mac's menu bar. They walk, nap, loaf, stretch, groom, chase each other, and play while you work.

Free and open source. Native Swift, AppKit and SwiftUI. macOS 14 or later.

![Cats walking, resting and playing in the macOS menu bar](docs/assets/menubar-demo.gif)

*Actual screen recording of Cats in Menubar.*

## Features

- One to three cats, eight coat choices, and kitten / young / adult sizes. Save a favorite lineup or shuffle it.
- Pick cats up, bring out a ball, or let them chase the laser pointer.
- Cats use the available menu bar space, return to their tower, and can travel behind a MacBook notch.
- Choose which display the cats live on; pause them, call them home, or set quiet hours.
- A compact dashboard for CPU, memory, storage, battery and network activity.
- Optional scroll direction controls for individual scrolling sources, off by default.
- Adaptive animation rates for system load, temperature and Low Power Mode; optional launch at login.

## Download and install

Open **[GitHub Releases](https://github.com/jason401/cats-in-menubar/releases)** and download the app ZIP. **The ZIP is all you need to install the app.**

| Download | Use |
| --- | --- |
| `Cats-in-Menubar-<version>-macOS-arm64.zip` | Prebuilt app for Apple silicon (M-series Macs), with installation instructions and license notices. |
| `SHA256SUMS.txt` | Optional download integrity check; not needed to install or run the app. |
| Source code | Inspect the source. To build, use the Git clone instructions below; GitHub's automatic source archives do not include the Git metadata required by the build. |

**The first release is being prepared; until an app ZIP is published, use [Build from source](#build-from-source).** No Intel or universal prebuilt download is currently provided. Building on an Intel Mac requires separate verification.

1. Download `Cats-in-Menubar-<version>-macOS-arm64.zip` for your Apple silicon Mac.
2. Unzip it. Quit any existing copy, then drag **Cats in Menubar.app** to **Applications**. Keep the included license and notice files when redistributing it.
3. Open the app. It runs in the menu bar, rather than opening a regular document window.
4. Grant **Accessibility** in System Settings → Privacy & Security → Accessibility. This lets the cats find available menu bar space. Depending on your macOS version, the permission may appear under Device Control and Data Access.

<details>
<summary>Optional: verify the ZIP download</summary>

`SHA256SUMS.txt` contains the expected SHA-256 checksum of the ZIP. You can skip this file for normal installation. To check that the download is intact, download it from the same release, place it beside the ZIP, and run `shasum -a 256 -c SHA256SUMS.txt` in that folder. A matching checksum does not by itself authenticate the publisher.

</details>

### macOS security warnings

This project is distributed without an Apple Developer Program account. Prebuilt apps are **locally signed, not Developer ID signed or notarized by Apple**. Local signing does not make the developer verified by Apple or prove that the app is safe.

macOS may say that it cannot verify the developer or check the app for malicious software. If you have reviewed the source/release and trust this exact download:

1. Try opening the app once in Finder.
2. Go to **System Settings → Privacy & Security**, find the message about **Cats in Menubar**, and choose **Open Anyway**.
3. Confirm the app name and choose **Open** if you want to proceed.

See [Apple's instructions for opening apps safely](https://support.apple.com/en-us/102445). If macOS reports that the app **will damage your computer**, contains malware, or has been modified/damaged, stop and investigate or download a fresh copy. Do not treat every security alert as the normal unidentified-developer warning. Do not disable Gatekeeper globally or run blanket quarantine-removal commands.

### Updates: prebuilt app versus source build

**Prebuilt ZIP:** use manual updates from Releases. Turn off automatic update checks in Settings → General → Updates. Quit the app and replace it with the next downloaded app. macOS may ask you to grant Accessibility again.

**Source build:** the installed app can check this repository's `stable` branch and build updates locally after you click **Update Now**. Apple's Command Line Tools and the same persistent local signing identity must remain available. Checks are enabled by default and can be disabled in Settings.

These are different paths: the existing updater pins the running app's signing identity. A prebuilt app signed on the publisher's Mac cannot be replaced through that updater by a build signed with a different key on your Mac. This release preparation does not change the updater or weaken that check. A GitHub Release does not automatically change `stable`.

## Build from source

Requires macOS 14+, Apple's Command Line Tools (including Git, Swift and the system developer Python), and an internet connection for the clone/update checks. Full Xcode, API keys and third-party runtime packages are not required.

Install the Command Line Tools if needed, then wait for Apple's installer to finish:

```sh
xcode-select --install
```

Clone the stable channel, create this app's local signing identity, and test/build it:

```sh
git clone --filter=blob:none --branch stable https://github.com/jason401/cats-in-menubar.git
cd cats-in-menubar
zsh tools/setup_signing.sh
zsh tools/test.sh
```

The signing setup creates a dedicated key and certificate in your login keychain and adds user-level trust limited to code signing. It may prompt for keychain access. It does not use an Apple Developer account or change TLS trust. Read `tools/setup_signing.sh` before running it. Do not share your signing private key or export it into the repository.

For a development preview:

```sh
open "build/Cats in Menubar.app"
```

To install your locally built copy (quit any running copy first):

```sh
open "build/Cats in Menubar.app" --args --install-self
```

The installer targets `/Applications/Cats in Menubar.app`. If a prebuilt app with a different signing identity is already installed, the installer intentionally refuses to replace it. Quit and remove that copy before installing your own build, then re-grant Accessibility if prompted. Keep your local signing identity for future builds.

For development work, check out `main`. Build outputs and previews stay in ignored `build/`. To package an existing verified build without publishing it, run `python3 tools/package_release.py --version v0.1.0 --app "build/Cats in Menubar.app" --output build/releases/v0.1.0`. The output includes installation instructions, license notices and SHA-256 checksums.

## Privacy and permissions

- No AI service, API key, advertising or analytics is used by the running app.
- Menu layout detection reads Accessibility roles, positions, sizes, visibility and structure, not menu text. It does not request Screen Recording or capture your screen.
- The dashboard reads local system/process/network statistics. Optional Location permission is requested to display the Wi-Fi network name; the app does not request location coordinates.
- The optional scroll feature observes scrolling events to identify their source and change their direction. It is not a keystroke logger.
- The installed app's update checks contact GitHub and download repository data. Clicking **Update Now** runs the repository's build and test scripts locally. The previous README's claim of no network requests was inaccurate.
- Preferences, diagnostics and update files remain on your Mac. Avoid posting raw dashboard screenshots or logs containing network names, local IPs, process names or local paths.

## Current limitations

This is an experimental personal project. Menu layout detection is sampled, so zero transient overlap cannot be guaranteed. Menu bar managers, automatically hidden bars, multiple displays and future macOS versions can expose compatibility issues. Some system integration uses private macOS APIs. Reduce Motion is not yet implemented, and coat markings/animation transitions may need further polish. The MIT license provides no warranty.

## AI-assisted development

This project was developed with assistance from AI coding tools, including ChatGPT/Codex and Claude. The cat artwork was also created and edited with AI assistance. Product decisions, integration and review are directed by the maintainer; AI assistance is not an Apple endorsement or a guarantee that the code or art is error-free.

## License and acknowledgements

Original project contributions are available under the **[MIT License](LICENSE)**, copyright © 2026 **jason401**.

The scroll direction feature is derived from **Scroll Reverser** by Nicholas Moore and retains the **Apache License 2.0** conditions and attribution. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt). The MIT license does not replace third-party licenses or grant rights to third-party trademarks, Apple frameworks, system fonts or system symbols.
