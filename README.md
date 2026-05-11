<img width="2940" height="1672" alt="xhs-fi2" src="https://github.com/user-attachments/assets/33d40fff-f6f0-487c-8b38-e1ced770cfb8" />


# Fantastic Island

[English](./README.md) | [简体中文](./README.zh-CN.md)

Fantastic Island is built on top of the open-source project `open-vibe-island`, and is an open, extensible app for the macOS notch area.

It supports plugging different capabilities in as modules, and the code is open too. In theory, you can use this container and its extensibility to build an island that is actually yours.

The fan component is mostly here because it is fun. You can hide it if you want, or just keep it around as a tiny reminder thing.

The repository currently ships with three built-in modules:

- `Codex`
- `Clash`
- `Player`

The `Codex` and `Clash` modules continue to evolve from open-source foundations.

## Core Idea

More and more products want to live around the island area, but that space is scarce. If you use A, you usually cannot use B without the interactions starting to fight each other.

Fantastic Island started from the open-source project `open-vibe-island`, but the real thing I want to build is a shell architecture with modular extensions, so you can assemble your own island as needed. You could even plug a todo module into it, although I am not totally sure the experience would be good.

## Settings And Modularity

<p align="center">
  <img src="./docs/images/settings-general.png" alt="Fantastic Island general settings" />
</p>
<p align="center">
  <img src="./docs/images/settings-wind-drive.png" alt="Fantastic Island wind drive and module configuration" />
</p>

The settings page keeps app-level behavior, `Wind Drive`, module toggles, and the design token debugging entry in one place. The shell stays stable, while the module layer stays easy to extend.

## Built-In Pieces

| Module / Component | Description |
| --- | --- |
| `Codex` | Pulls local Codex workflow state into the island, including sessions, quota, approvals, tool activity, and notifications. |
| `Clash` | Wraps Mihomo / Clash runtime integration and managed controls, with room for traffic, proxy groups, rules, connections, and logs. |
| `Player` | Reads current media playback state and exposes artwork, progress, and basic transport controls. |
| `Wind Drive` | A playful fan component in the center of the island, with configurable logo, sound, and presentation behavior. |

## Module Examples

### Codex

The `Codex` module is more like a local workspace living inside the notch. Session state, quota, and recent activity stay visible without making you jump back to the terminal every few seconds.

`Claude` is not wired into the agent monitoring path right now because it banned my account. To be fair, I also prefer `Codex`, so...

![Fantastic Island Codex module](./docs/images/island-codex.png)

### Player

The `Player` module is here to show and control current playback, so media controls can live together with `Codex` and `Clash` without needing another separate UI layer.

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

## Releases

- [v0.3.0](./docs/releases/v0.3.0.md) - Player source switching and Codex question flow
- [v0.2.0](./docs/releases/v0.2.0.md) - Island transition and interaction polish
- [v0.1.0](./docs/releases/v0.1.0.md) - First public source release

## Upstream And License

The notch shell interaction layer inherits and adapts parts of [open-vibe-island](https://github.com/Octane0411/open-vibe-island). The `Clash` module's source-side integration targets the `mihomo` / `metacubexd` ecosystem, but this repository does not redistribute their packaged runtime releases. See [LICENSE](./LICENSE) and [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for details.
