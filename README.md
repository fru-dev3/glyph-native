# Glyph Native

**Glyph is a free, local-first family of native Mac apps by [fru.dev](https://fru.dev).**
Glyph Native is the one install: it lists every Glyph app, installs the ones you want and keeps them up to date.

[![Download Glyph Native for Mac](https://img.shields.io/badge/Download-Glyph%20Native%20for%20Mac-008000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/fru-dev3/glyph-studio/releases/download/native/Glyph-Native.dmg)

Open the disk image and drag Glyph Native to Applications. It is signed and notarized by Apple.
Release notes and every earlier version: [the `native` release](https://github.com/fru-dev3/glyph-studio/releases/tag/native).
More at [glyph.fru.dev](https://glyph.fru.dev).

## Requirements

- A Mac with Apple silicon.
- macOS 26 or later for most apps.
- iPhone apps are in testing.

## The apps

| App | What it does | Page |
|---|---|---|
| Glyph Bot | One harness that builds, runs and watches your AI agents, with your vault behind them. Open source. | [glyph.fru.dev/bot](https://glyph.fru.dev/bot) |
| Glyph Jot | Hold Fn to dictate into any app; record and transcribe meetings, on the Mac. | [glyph.fru.dev/jot](https://glyph.fru.dev/jot) |
| Glyph Rig | Names, connects and runs Claude Code, Codex and Gemini sessions across your Macs. Open source. | [glyph.fru.dev/rig](https://glyph.fru.dev/rig) |
| Glyph Time | A count-up on the screen's edge that shows where your hours go. | [glyph.fru.dev/time](https://glyph.fru.dev/time) |
| Glyph Arena | Runs the same job across AI models and recipes and scores the results. | [glyph.fru.dev/arena](https://glyph.fru.dev/arena) |
| Glyph Cast | Screen videos, cleaned up. | [glyph.fru.dev/cast](https://glyph.fru.dev/cast) |
| Glyph Wealth | Accounts, balances and net worth, with no bank login. | [glyph.fru.dev](https://glyph.fru.dev) |
| Glyph Well | A health and fitness log. | [glyph.fru.dev](https://glyph.fru.dev) |
| Glyph Omega | Missions and goals. | [glyph.fru.dev](https://glyph.fru.dev) |
| Glyph CRM | People and accounts. | [glyph.fru.dev](https://glyph.fru.dev) |
| Glyph Connect | Connections for your agents. | [glyph.fru.dev](https://glyph.fru.dev) |
| Glyph Life | Bills and renewals. | [glyph.fru.dev](https://glyph.fru.dev) |

Every app is free. Glyph Native (this repository, MIT), Glyph Bot
([glyph-studio](https://github.com/fru-dev3/glyph-studio)), its engine
([glyph-engine](https://github.com/fru-dev3/glyph-engine)) and Glyph Rig
([glyph](https://github.com/fru-dev3/glyph)) are open source. The other apps are free and their code is private for now.

Each card in Glyph Native says whether the app is on this Mac and which version, with one button:
Install, Update or Open. Every app also installs on its own from its page.

## Privacy

- Your data stays in files you own: on your Mac, or in a vault folder you choose.
- fru.dev runs no server for the apps. There is no account to create.
- Glyph Native reaches GitHub to read releases and download the apps. Pairing an iPhone and finding
  your vault computer happen on your own network.

## How an install works

Glyph Native downloads the app's disk image from that app's latest release on GitHub and copies
the app to Applications (`scripts/install-release.sh`). Before it copies anything it checks that:

- the app's signature is intact, Gatekeeper accepts it, and it is signed by the same developer
  as Glyph Native itself;
- the app is not running. It never quits an app for you: quit it, then try again.

An older copy is replaced only once the new one is fully in place, so a failed download leaves
what you had. Update is offered only when the release is newer than what is installed.

## Build it yourself

```
scripts/build.sh                    # build/Glyph Native.app (SwiftPM, no Xcode project needed)
scripts/test-install-release.sh     # the installer against a made-up app, no network
```

## Feedback

Questions and bugs: [open an issue](https://github.com/fru-dev3/glyph-native/issues).

MIT. See LICENSE.
