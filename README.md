# Workspace Order

An Omarchy bar widget for reordering workspaces. Clicking still switches, as
the stock indicator does; the addition is putting a workspace somewhere else.

Reordering is a **renumber**, not a window move: Hyprland's `change_id` carries
a workspace and everything in it to a new id, so nothing is shuffled window by
window and nothing changes size or position on the way.

## Install

```bash
omarchy plugin add https://github.com/pynetreedev/omarchy-workspace-order.git --enable
```

Then bind the mode to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "Workspace order mode", "omarchy-shell -q workspace-order toggle")
```

## Remove

```bash
omarchy plugin remove pynetreedev.workspace-order
```

That unloads the widget and takes its entry out of your bar. If you added the
keybinding above, delete that line from `~/.config/hypr/bindings.lua` as well —
a plugin cannot remove Hyprland configuration you wrote.

## Requirements

- **Hyprland 0.56+ with the Lua config API**, for `hl.dsp.workspace.change_id`.
  It will not work on the classic config-file build.
- **Omarchy Quattro** (the Quickshell shell), for the bar widget contract.
- Nothing else. No runtime dependencies, no companion scripts, no files outside
  the plugin directory. It shells out only to `hyprctl`, which Hyprland ships.

## Use

| Gesture | Effect |
|---|---|
| Left click | switch to that workspace (unchanged) |
| Right click | swap the workspace you are on with that one |
| Reorder mode, then left click | the same swap, one click |
| Drag one pill onto another | swap those two |

Right click needs no mode at all — Omarchy's bar claims only the left button for
its own widget dragging, so a right click reaches the pill untouched.

Reorder mode outlines the pills so the state is visible, and turns itself off
once a swap is done. Drag is there for moving a workspace you are *not*
standing on; click covers the common case, where the source is wherever you
already are.

## IPC

```bash
omarchy-shell workspace-order toggle   # flip reorder mode
omarchy-shell workspace-order on       # arm it
omarchy-shell workspace-order off      # disarm it
omarchy-shell workspace-order state    # "on" or "off"
```

A bar exists per monitor, so the widget is instantiated more than once while an
IPC target routes to only one of them. The call is relayed to the others through
`BarWidget.broadcast()`; without that the mode would light up on one screen and
leave the rest looking untouched.

## Per-monitor workspaces

Works with [hyprsplit](https://github.com/shezdy/hyprsplit), where each monitor
owns a block of ids — the first display 1-10, the next 11-20. The widget works
out which block belongs to the monitor it is drawn on and labels that block
1-10, so both screens read the same and a swap stays on one monitor. Set
`workspacesPerMonitor` to match hyprsplit's `num_workspaces` if you have changed
it from 10. Without hyprsplit the block is just 1-10 and the labels are the ids.

## Keyboard

This is the mouse half. The keyboard half — a submap where bare number keys
swap the current workspace into a slot — is a Hyprland Lua module, because
keybindings live in `~/.config/hypr` and no shell plugin can install them:
[workspace-order](https://github.com/pynetreedev/workspace-order).

## Why it does not use Quickshell's workspace model

It cannot survive a renumber. `change_id` emits neither a create nor a destroy,
so Quickshell never learns that a workspace stopped existing under an id and
keeps a phantom — five occupied pills against four real workspaces, in the case
that prompted this. `refreshWorkspaces()` updates the objects it already holds
without pruning them, and `refreshToplevels()` cannot correct a list that is
wrong to begin with. A `renameworkspace` nudge does not help either: it carries
a name for an id and says nothing about an id having changed.

So ids, window counts and the active workspace all come from `hyprctl -j`,
re-read on a 60 ms debounce whenever a relevant event goes past. Focus events
Quickshell does model correctly, but taking that from one source and the rest
from another leaves the selected marker stranded on the pill you just left, so
it all comes from the same place.

## Tests

`test/` holds regression coverage for the workspace-name encoder, the one place
untrusted input reaches the compositor's Lua parser. Run with `node --test test/`.
It is developer tooling and plays no part in the installed plugin.

## Limitations

- Swaps stay within one monitor's block. Moving a workspace to another display
  is what Hyprland's own `moveworkspacetomonitor` is for.
- Requires a Hyprland with `hl.dsp.workspace.change_id` (0.56 and its Lua
  config API; tested on 0.56.1).
- Window order *within* a workspace is untouched — only whole workspaces move.
