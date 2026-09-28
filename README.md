# Chinese Input for Omarchy — simplified refactor

A refactored Omarchy 4 Quattro bar plugin for English and Simplified Chinese input with Fcitx5 and Rime Ice.

This repository is a modified version of [gohlihan/omarchy-cn-input-plugin](https://github.com/gohlihan/omarchy-cn-input-plugin). The upstream project is distributed under the MIT License. This refactor keeps the same user-facing behavior while simplifying the frontend state model.

The upstream MIT license and copyright notice are preserved in [`LICENSE`](LICENSE). See [`NOTICE`](NOTICE) for attribution and a summary of the modifications in this repository.

## What changed

The main refactor is architectural rather than functional:

- `BarWidget.qml` is the only frontend owner of backend status.
- `Panel.qml` no longer starts its own `status` process.
- The panel no longer keeps an optimistic copy of `startupLanguage`; after a mutation it re-reads the backend state.
- D-Bus input-method events and Hyprland focus events request a refresh; one-second polling covers missed events and Rime submode changes.
- Safety-critical Bash behavior remains intact: backups, atomic file replacement, idempotent configuration, and refusal to rewrite ambiguous Rime YAML.

The resulting data flow is:

```text
Fcitx5 / Rime
     ^
     |
scripts/cn-inputctl
     |
     | status JSON
     v
BarWidget.qml   <- single frontend status owner
     |
     +----> Panel.qml (read-only consumer)
```

## Install

```bash
omarchy plugin add https://github.com/lazysnail1024/omarchy-cn-input-plugin.git --enable
```

The widget initially shows `--`. Right click it and choose **Install Chinese input**.

The guided setup installs:

- `fcitx5-rime` through `omarchy pkg add`
- `rime-ice-pinyin-git` through `yay`

It then enables the Rime Ice full-pinyin schema and appends Rime to the current Fcitx5 input-method group without replacing existing entries.

## Behavior

- The bar shows `en` or `cn`.
- When available, the Rime D-Bus `IsAsciiMode` API distinguishes Chinese from Rime's internal ASCII mode. Older versions without this API show `Rime` instead of guessing; unavailable contexts show `--`.
- Status display and switching do not require the Rime Ice package when Rime is already available. `ready` describes guided-setup readiness, while `canSwitch` describes the running input-method group.
- Left click, or `Ctrl+Space`, switches the focused app.
- Right click opens startup settings for new input contexts.
- Setup and repair run in a terminal so package confirmation and password prompts remain visible.

## Files changed by setup

The controller deliberately keeps changes narrow:

- `~/.config/fcitx5/config`
- `~/.local/share/fcitx5/rime/default.custom.yaml`
- the current Fcitx5 input-method group through DBus

Existing files are backed up under:

```text
~/.local/state/community.cn-input/backups/
```

## Commands

```bash
scripts/cn-inputctl status
scripts/cn-inputctl toggle
scripts/cn-inputctl set-mode en
scripts/cn-inputctl set-mode cn
scripts/cn-inputctl set-startup en
scripts/cn-inputctl set-startup cn
scripts/cn-inputctl configure
scripts/setup
```

## Development

```bash
bash -n scripts/cn-inputctl scripts/setup tests/cn-inputctl-test.sh
./tests/cn-inputctl-test.sh

# On Omarchy 4:
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
```

## Status refresh

Requires `dbus-monitor` for event-driven refresh. The monitor reconnects after exit; one-second polling remains available if monitoring fails. The bar owns all status queries, coalesces requests during a running query, and refreshes after its panel releases focus. Rime ASCII changes are detected by querying the actual state, not by counting Shift presses. Hotkey configuration is independent of the widget.

Selecting Chinese also clears Rime ASCII mode when the API is available. English explicitly selects `keyboard-us`. Input-method IDs determine the mode: Fcitx activation alone is insufficient when Rime is the first group entry. Startup settings still control Fcitx activation, not Rime's internal ASCII default or a guaranteed language for arbitrary group order.

The event/focus refresh design was informed by [omarchy-fctix-status](https://github.com/manateelazycat/omarchy-fctix-status); its source is GPL-3.0-only. This project implements the behavior independently.

## Upstream and attribution

- Original project: [gohlihan/omarchy-cn-input-plugin](https://github.com/gohlihan/omarchy-cn-input-plugin)
- Rime Ice: [iDvel/rime-ice](https://github.com/iDvel/rime-ice)
- This repository contains modifications to the upstream project; see [`NOTICE`](NOTICE) for details.

## License

MIT
