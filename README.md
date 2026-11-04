# ATHAR — Wildlands

A first playable prototype of ATHAR: a third-person 3D hunting game for mobile,
built with **Godot 4.7.2**. Everything you see in the scene — terrain, forest,
ruins, the hunter, the deer and the HUD — is generated at runtime from Godot
primitives: the world and HUD in `scripts/main.gd`, the two characters in
dedicated rig scripts. There are no imported models, textures or audio files yet.
The wilderness is now ten regions — desert, silver forest, frozen highlands,
ember lands, ancient ruins, mirage oasis, crystal caves, reflection swamp, sky
cliffs and the void realm — with one loaded at a time.

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
| Move | Analogue stick, bottom-left | `W` `A` `S` `D` or arrow keys |
| Track / capture | `TRACK` button, bottom-right; when the deer is within 1.8 m a `CAPTURE` context button appears above it | — (touch buttons only) |
| New hunt | The same button, relabelled `NEW HUNT` after a capture | — (touch button only) |
| Pause | `PAUSE` button in the top corner: resume, settings, restart, main menu | same button (mouse) |
| Settings | Sound, graphics quality, language and stick sensitivity; saved between sessions | same screen (mouse) |
| Travel | Stand at a region's gate and press the `TRAVEL` context button, or open `المناطق` / `REGIONS` from the title or pause screen | same screens (mouse) |

The interface is Arabic by default and fully right to left; English is one tap
away in Settings and the whole HUD mirrors immediately. Every visible string
lives in `localization/ui_strings.csv` and is filled in at runtime, so no text is
hardcoded in a script. The movement stick stays bottom-left and the action button
bottom-right in both languages, because that is where thumbs already expect them.

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
scripts/world/region_definition.gd  The ten regions as data: palette, habitat, gates
scripts/world/region_builder.gd      Builds one region: ground, woodland, landmark, gate
scripts/world/region_manager.gd      Loads/unloads one region and tracks discovery
shaders/vegetation_wind.gdshader  Vertex wind for trees and grass
scenes/ui/                  HUD, main menu, pause, settings and confirmation scenes
scripts/ui/hud.gd            Vitals panel, touch stick, context buttons, toast, safe areas
scripts/ui/ui_kit.gd         One palette, theme and widget set for every screen
scripts/ui/localization.gd   Reads the CSV into translations and mirrors the layout
scripts/ui/virtual_joystick.gd  Analogue stick: deadzone, clamping, one-finger ownership
scripts/ui/vitals_bar.gd     One labelled gauge
scripts/ui/main_menu.gd      Title screen
scripts/ui/pause_menu.gd     Resume, settings, restart, return to title
scripts/ui/settings_menu.gd  Sound, graphics, language and sensitivity
scripts/ui/confirm_prompt.gd Restart / return-to-title confirmation
scripts/ui/deer_marker.gd    Off-screen / distant deer cue
scripts/ui/audio_panel.gd    Volume sliders and mute, now a section of Settings
scripts/ui/region_menu.gd    Region list, descriptions, discovery ticks and travel
scripts/settings/game_settings.gd     Persisted audio, language, graphics, sensitivity
scripts/settings/graphics_profile.gd  Low/medium/high 3D rendering presets
scripts/tests/ui_tests.gd    Headless interface, localization, layout and menu suite
scripts/tests/region_tests.gd  Headless region data, loading, travel and determinism suite
localization/ui_strings.csv  Every visible string, Arabic and English
assets/fonts/                Amiri + IBM Plex Sans Arabic with their OFL licences
scripts/audio/audio_director.gd  Beds, one-shot pool, footsteps and 3D animal audio
scripts/audio/audio_settings.gd  Master/music/effects volumes and mute, persisted
scripts/tests/audio_tests.gd      Headless audio asset, bus, settings and wiring suite
tools/generate_audio.py      Regenerates every sound file in assets/audio
assets/audio/                The game's own generated WAVs + LICENSE.txt (provenance)
audio/default_bus_layout.tres  Master/Music/SFX bus layout
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
- Sound from a bus layout with music and effects sub-buses and a master: forest
  ambience that cross-fades between day and night, wind and distant birds, rain
  tied to the weather, hunter footsteps that change with the surface (stone in
  the ruin, grass and soil elsewhere), deer hoofbeats, a warning snort and a
  flight call that are positional (`AudioStreamPlayer3D` on the animal, so
  distance and direction are the engine's), a capture chime, a quiet interface
  tap and a slow ambient pad. Volume and mute live in an `AUDIO` panel and are
  saved to `user://audio_settings.cfg`.
- Touch HUD: title, status line, stamina bar, direction pad, hunt button.
- Repeatable hunt loop: approach, alert, chase, capture, then `NEW HUNT`.

### Interface (Phase 3.5)

- A rebuilt mobile HUD: a dark violet panel with the hunt message, a
  time/weather/quarry line and three vitals — the hunter's breath, the quarry's
  condition and how alert it is. There is no health bar because the prototype has
  no damage model; the three bars show state that actually exists.
- One analogue movement stick instead of four direction buttons, with a deadzone,
  clamping and single-finger ownership, plus a context `CAPTURE` button that
  appears only when the deer is within reach.
- Title, pause, settings and confirmation screens. Restart and "return to main
  menu" both ask first, because a thumb slips.
- Arabic by default with full RTL mirroring, and English from the settings screen.
  The layout mirrors panels, text and the pause corner; the stick and the action
  button keep their sides.
- Settings for the Phase 3.4 volumes and mute, three graphics levels (3D render
  scale, sun shadows, MSAA, shadow atlas), the interface language and stick
  sensitivity, saved to `user://athar_settings.cfg`.
- Safe-area insets for notches and rounded corners, and layouts verified from
  800×360 up to a 2048×1536 tablet.

### World regions (Phase 3.6)

- Ten regions, each a dictionary in `scripts/world/region_definition.gd`: a
  ground palette, a woodland profile, an atmosphere tint, a landmark style, a
  wildlife habitat and its entry, gate and exits. Nothing about a region is
  hardcoded in the scene, so a future creature, boss, quest or event can be
  attached to the same definition without rewriting the world.
- Region identity: the silver forest is the original Phase 3.1 world, unchanged;
  the desert is open dunes with two obelisks; the frozen highlands raise ice
  spires over a frozen pool; the ember lands are basalt columns around a glowing
  lava crack; the ancient ruins are a colonnade; the mirage oasis has a pool and
  palms; the crystal caves are an emissive crystal field; the reflection swamp
  has still water, sunken bridges and planks; the sky cliffs are rock terraces and
  a rope bridge; the void realm is floating shards around a violet ring.
- Atmosphere is a tint multiplied over the day/night and weather result, not a
  replacement for it. A neutral tint leaves every lighting value exactly as the
  older phases computed it; a region can warm the sun, thicken the fog or push
  the exposure without ever pausing the clock.
- One region exists at a time. Loading a new one frees the previous region's
  nodes immediately, so the peak is one ground, one woodland and one landmark
  (the heaviest region measures 41 nodes and 23 mesh instances).
- Travel is safe: breath, the current hunt, its capture count, the language, the
  settings and the audio volumes all survive a transition. Only the ground, the
  woodland, the landmark and the uncaught quarry are replaced, and the hunter is
  placed at the new region's entry point.
- Discovery is a simple indicator: the HUD shows the region's name and how many
  of the ten have been seen, and the region screen ticks each one. It is kept in
  memory for the session (there is no save system yet), so a restart starts the
  count again.
- Region definitions declare empty `future` hooks — `creatures`, `bosses`,
  `quests`, `events` — which this phase fills with nothing on purpose.
- Hunting balance is untouched: senses, speeds, stamina and the 1.8 m capture
  reach are the Phase 3.2 values. A region may choose its deer's temperament and
  a habitat distance band, and the band is clamped to the tuned 16 m floor.

## Known limitations

These are known and intentionally **not** changed in this baseline phase:

- All visuals are Godot primitives, not final art: trees, ground and lighting
  are generated in code with no textures or models on disk.
- One scene and one script; no separate actor/UI scenes and no autoloads.
- The audio is synthesised, not recorded: `tools/generate_audio.py` produces
  every WAV from sine waves and filtered noise, so there is nothing to license
  and nothing borrowed — but also no field recording, and an ambience built from
  noise layers is simpler than a real forest. See `assets/audio/LICENSE.txt`.
- No audio could be listened to during development: every check runs headlessly
  on the dummy audio driver, so the suites verify assets, buses, volumes, player
  state and wiring, not how it sounds. Mix levels are judgement calls that need
  an owner's ear on a phone.
- The only interactive sound the world offers is the hunt itself; there is no
  menu music or stingers because there is no menu beyond the audio panel.
- HUD text is English only; no Arabic font or right-to-left layout yet.
- No `export_presets.cfg` and no Android build template, so the project cannot
  be exported to an APK as-is. Signing credentials are not part of this repo.
- No save system, pause menu or localized strings. Settings exist only for audio
  (`user://audio_settings.cfg`); nothing else is persisted.
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
- Region discovery is session-only, and there is no save file for it. Closing
  the game forgets which regions were seen; the regions themselves are always
  reachable, so nothing is locked behind the count.
- A region's wildlife is the same single deer species in a different habitat:
  the temperament and the spacing change, not the animal. New species and the
  creatures/bosses the definitions reserve hooks for are later phases.
- No Phase 3.6 screenshots exist: this environment has no display server, no
  root to install one, and no software Vulkan driver, so the renderer cannot be
  started. The region suites verify geometry, budgets and transitions; they do
  not prove the ten regions look distinct. That check needs a real screen.
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
camera/visual suite, the wildlife AI suite, the living world suite, the audio
suite, the interface suite and the world region suite — and exits non-zero if any
of them fail. The hunting suite runs 66 checks, the visual suite 53, the wildlife
suite 100, the living world suite 95, the audio suite 86, the interface suite 217
and the region suite 398; the script itself reports 177 checks, including every
suite's verdict. Full details in
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
