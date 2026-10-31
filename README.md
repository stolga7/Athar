# ATHAR — Wildlands

A first playable prototype of ATHAR: a third-person 3D hunting game for mobile,
built with **Godot 4.7.2**. Everything you see in the scene — terrain, forest,
ruins, the hunter, the deer and the HUD — is generated at runtime from Godot
primitives: the world and HUD in `scripts/main.gd`, the two characters in
dedicated rig scripts. There are no imported models, textures or audio files yet.

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
| Capture | `HUNT / TRACK` button, bottom-right — captures when the deer is within 1.8 m | — (touch button only) |
| New hunt | The same button, relabelled `NEW HUNT` after a capture | — (touch button only) |

The on-screen buttons drive the `move_forward`, `move_back`, `move_left` and
`move_right` input actions. Those actions are declared in `project.godot` with
keyboard equivalents (`W`/`S`/`A`/`D` and the arrow keys) so the prototype can
be driven from the editor on desktop; the touch buttons remain the primary
control scheme and press the same actions directly.

## Project structure

```
project.godot                Project settings (name, main scene, display, input, renderer)
scenes/main.tscn             Game scene: a Node3D root with main.gd attached
scenes/tests/                Test scenes (headless, not part of normal gameplay)
scripts/main.gd              World generation, hunter control, camera, HUD, wiring
scripts/visuals/rig_utils.gd Mesh and material helpers shared by both rigs
scripts/visuals/hunter_rig.gd  Hunter model and its idle/walk/run animation
scripts/visuals/deer_rig.gd    Deer model, state poses and gait animation
scripts/animals/deer_ai.gd   Deer behaviour: states, detection, flight, stamina
scripts/gameplay/hunt_session.gd  One hunt: capture rule, counts, new-hunt cycle
scripts/tests/hunting_tests.gd    Headless hunting and rig test suite
scripts/verify_project.sh    Automated verification (see TESTING.md)
assets/                      Reserved for imported assets — currently empty
icon.svg                     Project icon
README_AR.md                 Arabic project notes
```

## What this prototype contains

- Procedural environment: sky, sun with shadows, fog, ground plane.
- Procedural world: trees, rocks and a ruined stone arch.
- A hunter character with third-person follow camera and gravity.
- A hooded hunter built from articulated parts: hood, cloak, belt with a cyan
  gem, boots, quiver and a wooden bow, in a dark/purple/gold palette with one
  restrained cyan accent. Legs and arms swing in a procedural idle/walk cycle.
- A deer with a two-part neck, ears, tined antlers, a tail and four jointed legs
  (shoulder/hock). It stands and grazes naturally, and its pose changes per
  state, so an alerted or fleeing deer looks different from a grazing one.
- Deer behaviour states: `GRAZING → ALERTED → FLEEING → ESCAPING`, then either
  `CAPTURED` or back to `GRAZING` once it has broken away.
- Fair chase: the deer is faster in a short sprint and slower once tired, so a
  hunter who keeps pursuing closes the gap. See the numbers in `TESTING.md`.
- Touch HUD: title, status line, stamina bar, direction pad, hunt button.
- Repeatable hunt loop: approach, alert, chase, capture, then `NEW HUNT`.

## Known limitations

These are known and intentionally **not** changed in this baseline phase:

- All visuals are Godot primitives, not final art. `assets/` is empty.
- One scene and one script; no separate actor/UI scenes, no autoloads, no audio.
- HUD text is English only; no Arabic font or right-to-left layout yet.
- No `export_presets.cfg` and no Android build template, so the project cannot
  be exported to an APK as-is. Signing credentials are not part of this repo.
- No save system, settings, pause menu or localized strings.
- World layout uses a random generator; pass `--seed=<int>` (or set `ATHAR_SEED`)
  to reproduce a layout, otherwise each run differs. See `TESTING.md`.
- The hunter and deer are assembled from primitives by code. Their proportions
  are asserted numerically by the test suite (height, length, width, feet on the
  ground), but **no automated check can confirm they look good**: this project's
  automated runs use Godot's headless dummy renderer, so all visual judgement
  still needs a human on a real machine.
- No Android device or emulator test has been run, so touch feel, framerate and
  on-device rendering of the new models are unverified.

## Verification

```bash
./scripts/verify_project.sh
```

Runs the headless checks — engine version, project import, GDScript parsing,
startup, repository integrity, seed determinism and the hunting suite — and
exits non-zero if any of them fail. The hunting suite alone runs 66 checks; the
script reports 37 of its own. Full details in [TESTING.md](TESTING.md).

## License

No license has been chosen for this project yet, so all rights are reserved by
the author. Do not add a `LICENSE` file without the owner's explicit approval.
