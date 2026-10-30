# ATHAR — Wildlands

A first playable prototype of ATHAR: a third-person 3D hunting game for mobile,
built with **Godot 4.7.2**. Everything you see in the scene — terrain, forest,
ruins, the hunter, the deer and the HUD — is generated at runtime from Godot
primitives inside `scripts/main.gd`. There are no imported models, textures or
audio files yet.

> **Status: prototype / vertical slice.** This is not a finished game and there
> is no distributable APK yet. There is no Android export preset in this
> repository, so the project is intended to be opened and run in the Godot
> editor for now.

Arabic documentation: [README_AR.md](README_AR.md).

## Requirements

- **Godot 4.7.2** (standard build; the project declares the `4.7` + `Mobile`
  feature tags and uses the `mobile` renderer).
- No plugins, addons, paid dependencies or external assets are required.

## Quick start

```bash
git clone https://github.com/stolga7/Athar.git
cd Athar
```

1. Launch Godot 4.7.2.
2. In the Project Manager choose **Import**, then select `project.godot` at the
   **root of this repository**.
3. Open the project and press **F5** (or the ▶ button) to run `scenes/main.tscn`.

The first import regenerates the `.godot/` cache, which is intentionally
git-ignored.

## Controls

| Action | Touch (target platform) | Desktop |
| --- | --- | --- |
| Move | Four on-screen direction buttons, bottom-left | `W` `A` `S` `D` or arrow keys |
| Hunt / Track | `HUNT / TRACK` button, bottom-right | — (touch button only) |

The on-screen buttons drive the `move_forward`, `move_back`, `move_left` and
`move_right` input actions. Those actions are declared in `project.godot` with
keyboard equivalents (`W`/`S`/`A`/`D` and the arrow keys) so the prototype can
be driven from the editor on desktop; the touch buttons remain the primary
control scheme and press the same actions directly.

## Project structure

```
project.godot        Project settings (name, main scene, display, input, renderer)
scenes/main.tscn     The only scene: a single Node3D root with main.gd attached
scripts/main.gd      All gameplay and procedural content (world, actors, HUD, AI)
assets/              Reserved for imported assets — currently empty
icon.svg             Project icon
README_AR.md         Arabic project notes
```

## What this prototype contains

- Procedural environment: sky, sun with shadows, fog, ground plane.
- Procedural world: trees, rocks and a ruined stone arch.
- A hunter character with third-person follow camera and gravity.
- A deer that grazes, notices the player at close range and flees.
- Touch HUD: title, status line, stamina bar, direction pad, hunt button.
- One hunt loop: approach the deer, then use `HUNT / TRACK` within capture range.

## Known limitations

These are known and intentionally **not** changed in this baseline phase:

- All visuals are Godot primitives, not final art. `assets/` is empty.
- One scene and one script; no separate actor/UI scenes, no autoloads, no audio.
- HUD text is English only; no Arabic font or right-to-left layout yet.
- No `export_presets.cfg` and no Android build template, so the project cannot
  be exported to an APK as-is. Signing credentials are not part of this repo.
- No save system, settings, pause menu or localized strings.
- World layout uses an unseeded random generator, so each run differs.
- The deer is faster than the hunter, which makes the final capture step hard to
  reach — gameplay balance is a design decision pending owner review.
- Gameplay behaviour, balance and art direction are unchanged from the original
  uploaded archive.

## License

No license has been chosen for this project yet, so all rights are reserved by
the author. Do not add a `LICENSE` file without the owner's explicit approval.
