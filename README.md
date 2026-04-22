# Fantastic Island

[English](./README.md) | [简体中文](./README.zh-CN.md)

<p align="center">
  <img src="./docs/images/island-codex.png" alt="Fantastic Island Codex module" width="100%" />
</p>

Fantastic Island is an extensible notch app for macOS.

It treats the notch shell as a stable container and plugs different capabilities into one shared island surface: expand it, peek into it, switch modules, and enable only the pieces you actually want.

The repository currently ships with three built-in modules:

- `Codex`
- `Clash`
- `Player`

The `Codex` and `Clash` modules continue from open-source foundations. The spinning `Wind Drive` fan in the middle exists for a much simpler reason: it is fun.

## Core Idea

- This is not just a few floating utilities placed next to each other.
- The shell owns expansion, collapse, peek, notifications, and module navigation.
- Each module focuses on its own state, summaries, and expanded content.
- New capabilities are meant to plug into the existing container instead of forcing a shell rewrite.

## Settings And Modularity

<p align="center">
  <img src="./docs/images/settings-general.png" alt="Fantastic Island general settings" width="48%" />
  <img src="./docs/images/settings-wind-drive.png" alt="Fantastic Island wind drive and module configuration" width="48%" />
</p>

The settings surface keeps app-level behavior, `Wind Drive`, module toggles, and design token debugging in one place. The shell stays stable while the module layer remains easy to extend.

## Built-In Pieces

| Module / Component | Description |
| --- | --- |
| `Codex` | Pulls local Codex workflow state into the island, including sessions, quota, approvals, tool activity, and notifications. |
| `Clash` | Wraps Mihomo / Clash runtime integration and managed controls, with room for traffic, proxy groups, rules, connections, and logs. |
| `Player` | Reads current media playback state and exposes artwork, progress, and basic transport controls. |
| `Wind Drive` | A playful fan component in the center of the island, with configurable logo, sound, and presentation behavior. |

## Module Examples

### Codex

The `Codex` module acts like a local workspace that lives inside the notch. Session state, quota, and recent activity stay visible without forcing you back into the terminal every few seconds.

![Fantastic Island Codex module](./docs/images/island-codex.png)

### Player

The `Player` module keeps now playing information inside the same surface, so media controls can coexist with `Codex` and `Clash` without a separate UI layer.

![Fantastic Island Player module](./docs/images/island-player.png)

### Clash

The `Clash` module brings network runtime state into the same interaction model: you can treat proxy status, traffic, groups, rules, connections, and logs as first-class island content instead of another detached panel.

## Repository Scope

This repository is published as `source-only`.

Included:

- Full app source code
- Xcode project
- Built-in module implementations
- License and third-party notices

Not included:

- DMG packaging
- Code signing or notarization setup
- Personal team identifiers
- Private local metadata
- Prebundled Clash runtime, dashboard, or geodata artifacts

The managed Clash workflow is open on the source side, but this public repository does not redistribute packaged runtime assets. If you want the full workflow, you need to supply compliant runtime assets yourself.

## Build

Build locally with:

```bash
xcodebuild -project 'FantasticIsland/FantasticIsland.xcodeproj' -scheme 'FantasticIsland' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Run the lightweight logic checks with:

```bash
swift test
```

## Upstream And License

The notch shell interaction layer inherits and adapts parts of [open-vibe-island](https://github.com/Octane0411/open-vibe-island). The `Clash` module's source-side integration targets the `mihomo` / `metacubexd` ecosystem, but this repository does not redistribute their packaged runtime releases. See [LICENSE](./LICENSE) and [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for details.
