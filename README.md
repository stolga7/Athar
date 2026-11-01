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
scenes/tools/                Development tools (screenshot capture, not shipped)
scripts/main.gd              World assembly, hunter control, HUD, wiring
docs/screenshots/            Rendered evidence from the visual phase
scripts/visuals/rig_utils.gd Mesh and material helpers shared by both rigs
scripts/visuals/hunter_rig.gd  Hunter model and its idle/walk/run animation
scripts/visuals/deer_rig.gd    Deer model, state poses and gait animation
scripts/visuals/camera_rig.gd  Follow camera: smoothing, shoulder offset, obstruction
scripts/visuals/forest.gd      Procedural tree variants, instanced placement, trunk colliders
scripts/visuals/wilds_ground.gd  Ground material, backdrop, stones
scripts/visuals/wilds_environment.gd  Sky, fog, sun and fill light
scripts/world/day_cycle.gd       Clock: sun, sky, fog and exposure over a day
scripts/world/weather.gd         Clear, cloudy, rain and fog, blended over time
scripts/world/rain.gd            One bounded rain particle emitter
scripts/world/living_world.gd    Binds clock, weather, wind and wildlife senses
shaders/vegetation_wind.gdshader  Vertex wind for trees and grass
scripts/ui/deer_marker.gd    Off-screen / distant deer cue
scripts/animals/deer_ai.gd      Deer behaviour: natural activity, alarm, flight
scripts/animals/wildlife_profile.gd    Species blueprint + seeded temperament
scripts/animals/wildlife_perception.gd Vision cone, hearing and threat memory
scripts/animals/wildlife_steering.gd   Heading smoothing and obstacle avoidance
scripts/gameplay/hunt_session.gd  One hunt: capture rule, counts, new-hunt cycle
scripts/tests/hunting_tests.gd    Headless hunting and rig test suite
scripts/tests/visual_tests.gd     Headless camera, forest and lighting test suite
scripts/tests/wildlife_tests.gd   Headless behaviour, perception and AI test suite
scripts/tests/world_tests.gd      Headless clock, weather and living-world suite
scripts/tools/capture_shots.gd    Renders review screenshots from the real scene
scripts/tools/behaviour_shots.gd  Renders the deer in each behaviour state
scripts/verify_project.sh    Automated verification (see TESTING.md)
assets/                      Reserved for imported assets — currently empty
icon.svg                     Project icon
README_AR.md                 Arabic project notes
```

## What this prototype contains

- A third-person camera built for a phone screen: 6 m back and 2.8 m up, a
  shoulder offset so the hunter never covers the middle of the frame, smoothed
  follow, and a swept-sphere obstruction probe that pulls the camera in front of
  trunks and terrain instead of letting foliage fill the screen.
- Procedural forest with eight tree shapes — tapered trunks with root flare and
  branches, irregular broadleaf crowns and stacked conifer tiers — instanced as
  a handful of MultiMesh batches, with a distant treeline for the horizon.
- Dusk lighting: warm low sun with soft, lifted shadows, cool fill light, depth
  fog, filmic tonemapping and a textured ground (moss/soil albedo plus a detail
  normal map) instead of one flat green plane.
- An off-screen/distant deer cue in the HUD corner: a gold chevron when the deer
  is behind the camera, a small diamond with the range when it is far away.
- A hunter character with gravity and the camera rig above.
- A hooded hunter built from articulated parts: hood, cloak, belt with a cyan
  gem, boots, quiver and a wooden bow, in a dark/purple/gold palette with one
  restrained cyan accent. Legs and arms swing in a procedural idle/walk cycle.
- A deer with a two-part neck, ears, tined antlers, a tail and four jointed legs
  (shoulder/hock). It stands and grazes naturally, and its pose changes per
  state, so an alerted or fleeing deer looks different from a grazing one.
- A deer that lives its own life: `GRAZING`, `WANDERING`, `OBSERVING` and
  `RESTING` cycle on timers, and an alarm leads to `ALERTED`, then
  `INVESTIGATING` for a distant noise or straight to `FLEEING`/`ESCAPING` for a
  close one, with `RETURNING` before it relaxes back to grazing.
- Senses instead of omniscience: a 300° field of view with trunk-line-of-sight
  checks, proximity awareness inside 10 m, hearing that carries a sprinting
  hunter about 18 m but a walking one only ~6 m, and ~6 s of threat memory so it
  does not forget you the moment you step behind a tree.
- Personality per animal, generated from the world seed: `steady`, `cautious`,
  `bold` or `nervous`, shifting field of view, hearing, memory, patience and how
  close you get before it commits to flight. Movement speeds are never varied.
- A living world on a clock: an eight-minute day with smooth dawn, daylight,
  sunset and night. Sun angle, colour, shadows, sky, fog and exposure all follow
  the hour, and night keeps a cool moonlight floor so the hunt stays playable.
- Weather that rolls in: clear, cloudy, rain and fog, eased over fourteen seconds
  instead of snapped, with rain that dims the light, wets the ground and thickens
  the air, and fog that swallows the distance without hiding the deer.
- Wind in the shader: every tree and every grass tuft sways from a single vertex
  shader driven by one shared parameter, so 138 trees cost two sin() calls per
  vertex and no per-frame CPU work.
- Wildlife that reads the weather: at night deer see a little less and hear more,
  in rain their hearing is masked and they stay spooked longer, and all of it
  stays inside a bounded band, so no weather makes the hunt unfair.
- Deer movement looks before it runs: smoothed turning and acceleration, and a
  probe that steers it around trunks instead of into them.
- Fair chase: the deer is faster in a short sprint and slower once tired, so a
  hunter who keeps pursuing closes the gap. See the numbers in `TESTING.md`.
- Touch HUD: title, status line, stamina bar, direction pad, hunt button.
- Repeatable hunt loop: approach, alert, chase, capture, then `NEW HUNT`.

## Known limitations

These are known and intentionally **not** changed in this baseline phase:

- All visuals are Godot primitives, not final art. `assets/` is empty: trees,
  ground and lighting are generated in code with no textures or models on disk.
- One scene and one script; no separate actor/UI scenes, no autoloads, no audio.
  The living world is silent on purpose: `assets/` is empty and the brief allows
  environmental sound only from assets that already exist.
- HUD text is English only; no Arabic font or right-to-left layout yet.
- No `export_presets.cfg` and no Android build template, so the project cannot
  be exported to an APK as-is. Signing credentials are not part of this repo.
- No save system, settings, pause menu or localized strings.
- World layout uses a random generator; pass `--seed=<int>` (or set `ATHAR_SEED`)
  to reproduce a layout, otherwise each run differs. See `TESTING.md`.
- The hunter and deer are assembled from primitives by code. Their proportions
  are asserted numerically by the test suite, and the environment is checked by
  the visual test suite, but **neither can confirm a scene looks good**.
  Screenshots in `docs/screenshots/phase-3.1/` were rendered from the real scene
  with software Vulkan (Mesa lavapipe) on a Linux VM; they are evidence of what
  the code draws, not a substitute for playing it.
- The deer does not drink: the world has no water body, and adding one is out of
  scope for this phase. `DRINKING` is therefore not implemented rather than
  simulated.
- Scent, wind and tracks are not modelled; the animal senses by sight and sound
  only. There is also no population system, so one deer exists at a time.
- No Android device or emulator test has been run. Touch feel, on-device
  framerate and colour reproduction on a phone screen are unverified, and the
  draw-call/triangle counts in `TESTING.md` come from a software rasteriser, so
  they indicate scene cost but are not a phone benchmark.

## Verification

```bash
./scripts/verify_project.sh
```

Runs the headless checks — engine version, project import, GDScript parsing,
startup, repository integrity, seed determinism, the hunting suite, the
camera/visual suite, the wildlife AI suite and the living world suite — and
exits non-zero if any of them fail. The hunting suite runs 66 checks, the visual
suite 53, the wildlife suite 100 and the living world suite 95; the script
itself reports 89 checks, including every suite's verdict. Full details in
[TESTING.md](TESTING.md).

Rendered screenshots are in [docs/screenshots](docs/screenshots/): the world
views of Phase 3.1 (spawn, deer at close range, chase, camera pinned against a
trunk, horizon) in `phase-3.1/`, the deer's behaviour states in `phase-3.2/`, and
the living world of Phase 3.3 (day, sunset, night, rain, fog) in `phase-3.3/`.
They can be regenerated on any machine with a display using
`scripts/tools/capture_shots.gd`, `behaviour_shots.gd` and `world_shots.gd`; see
section 7 of [TESTING.md](TESTING.md).

## License

No license has been chosen for this project yet, so all rights are reserved by
the author. Do not add a `LICENSE` file without the owner's explicit approval.
