# Glyph Native

**One install for every Glyph app.** Glyph Native shows the Glyph apps for the Mac in one window,
installs the ones you want, and keeps them up to date.

Part of the [Glyph family](https://glyph.fru.dev) by [fru.dev](https://fru.dev).

## Install

Download [Glyph-Native.dmg](https://github.com/fru-dev3/glyph-native/releases/latest/download/Glyph-Native.dmg)
and drag Glyph Native to Applications. It is signed and notarized by Apple. Needs macOS 26 on
Apple silicon.

## What is new in 0.5.0

- A new window with a sidebar, groups, search and sort.
- Every app in the family is listed. The ones you cannot download yet say Coming.
- Uninstall an app to the Trash, and install it again whenever you like.
- A Vault page with a first-run setup that picks and checks your vault folder.
- Pair an iPhone by QR code. The codes expire.
- Find your vault computer on the same network or over Tailscale.
- Settings and About are a page of the window.
- Light and dark.

## What it installs

| App | What it is for | Its own page |
|---|---|---|
| Glyph Studio | One harness for all your agents | [glyph.fru.dev/studio](https://glyph.fru.dev/studio) |
| Glyph Jot | Personal context: notes, dictation and meetings | [glyph.fru.dev/jot](https://glyph.fru.dev/jot) |
| Glyph Arena | The best AI model and recipe for each task | [glyph.fru.dev/arena](https://glyph.fru.dev/arena) |
| Glyph Cast | Screen videos, cleaned up | [glyph.fru.dev/cast](https://glyph.fru.dev/cast) |
| Glyph Time | Where your hours go | [glyph.fru.dev/time](https://glyph.fru.dev/time) |

Each card says whether the app is on this Mac and which version, and carries one button:
Install, Update or Open. Install All does every missing or older one in turn. Every app also
installs on its own from its page.

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

MIT. See LICENSE.
