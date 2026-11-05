# ATHAR — Testing and Verification

How to check that the project still builds, parses, starts, generates the same
world from the same seed, and plays the hunting loop correctly — everything that
can be verified without a display, a GPU, or an Android toolchain.

Verification is a plain Bash script. There is no third-party test framework and
no extra dependency to install.

---

## 1. Requirements

| Requirement | Value |
|---|---|
| Godot | **4.7.2 stable** (the exact version the project targets) |
| Shell | Bash 4+ (Linux, macOS, Git Bash, or the GitHub Actions runner) |
| Also used | `git`, `find`, `grep`, `sed`, `mktemp` — all present on any normal system |

Nothing else: no package manager, no addons, no plugin, no paid service. The
project itself has zero runtime dependencies beyond the engine.

The script needs a Godot **editor** binary (the same executable the editor
uses). Headless mode is used for every check, so no window is opened.

> If your engine version differs from 4.7.2, the script fails check **A** on
> purpose: a different engine can change physics, RNG, and import results, so
> "verified" would otherwise mean something different on each machine.

---

## 2. How to run

From the repository root:

```bash
./scripts/verify_project.sh
```

If Godot is not on `PATH`, point the script at it:

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 ./scripts/verify_project.sh
# or
./scripts/verify_project.sh --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
```

Options:

| Option | Effect |
|---|---|
| `--frames N` | Frames to run for the startup check (default `180`, about 3 seconds) |
| `--godot PATH` | Engine binary to use |
| `--verbose`, `-v` | Keep the log directory even on success and list each compared world |
| `--help`, `-h` | Print usage |

Environment:

| Variable | Effect |
|---|---|
| `GODOT` | Engine binary to use (same as `--godot`) |
| `REQUIRED_GODOT_VERSION` | Version check target (default `4.7.2`) |
| `GODOT_TIMEOUT` | Seconds allowed per engine run (default `180`) |

Every engine run is wrapped in a wall-clock limit, so a scene that never exits
fails the check with `timed out after Ns` instead of blocking the harness.

Exit status: **`0`** when every check passed, **`1`** on any failure, **`2`** on
a bad command-line option. The script never reports success for a check it did
not run.

---

## 3. What each check verifies

### A. Godot version
Runs `--version` and requires the reported version to start with `4.7.2`. The
binary actually used is printed, so the report can never be ambiguous about
which engine produced the results.

### B. Project import
Runs `--headless --import` and requires exit code 0. Import output is then
scanned for genuine project errors (`ERROR:`, `SCRIPT ERROR`, `Parse Error`,
`Failed to load/instantiate`). Environmental engine noise is filtered out first
(see §5). A non-zero exit, a surviving error line, or a missing `.godot` cache
directory all fail this check.

### C. GDScript validation
Every `*.gd` file in the project (excluding `.godot/` and `.git/`) is parsed
individually with `--check-only --script res://<path>`. A file that fails to
parse or reports an error fails the check and its diagnostic is printed. This
catches syntax and compilation errors before they can reach a device build.

### D. Startup verification
Runs the real main scene headlessly for `--frames` frames, then requires:

- exit code 0 — no crash and no unexpected termination;
- no runtime/script errors in the output;
- the world checksum marker (`ATHAR_TEST_WORLD_CHECKSUM=…`) was printed, which
  only happens after the main scene has fully built its world, hunter, deer,
  camera, and HUD.

That third condition is what makes a green run meaningful: exit code 0 alone
would also be produced by a scene that loaded no world at all.

### E. Repository integrity
Confirms the files the project cannot work without are present — `project.godot`,
`scenes/main.tscn`, `scenes/tests/hunting_tests.tscn`, `scripts/main.gd`,
`scripts/animals/deer_ai.gd`, `scripts/gameplay/hunt_session.gd`,
`scripts/tests/hunting_tests.gd`, `scripts/visuals/deer_rig.gd`,
`scripts/visuals/hunter_rig.gd`, `scripts/visuals/rig_utils.gd`, `icon.svg`,
`icon.svg.import`, `.gitignore`, `README.md`, `TESTING.md`, `assets/` — and that:

- `project.godot` still points at `res://scenes/main.tscn`;
- the main scene is still wired to `scripts/main.gd`;
- no generated or temporary files are tracked by git (`.godot/`, `*.log`,
  `*.tmp`, `*.orig`, `*.rej`, `__pycache__/`, `.DS_Store`, `Thumbs.db`, `*.apk`,
  `*.aab`, `*.keystore`, `*.jks`, `node_modules/`, `.import/`);
- `.godot/` is in fact ignored by `.gitignore`.

Uncommitted local changes are reported as a note, not a failure.

### F. Reproducible gameplay
The world is generated from a random seed. A seed can be supplied so the layout
can be reproduced exactly:

```bash
# as a user argument (note the -- separator)
./scripts/verify_project.sh
godot --headless --path . --quit-after 3 -- --seed=20261030

# or through the environment
ATHAR_SEED=20261030 godot --headless --path . --quit-after 3
```

With no seed supplied, the engine's normal random seed is used and the world is
random on every launch — ordinary gameplay is unchanged. An unparseable value
(`--seed=abc`) is ignored and falls back to normal randomization.

This check runs the world five times and compares a checksum of the generated
layout:

| Runs | Required result | Proves |
|---|---|---|
| `--seed=20261030` twice | identical checksums | a fixed seed reproduces the world |
| `--seed=1` | different from the above | the seed really drives generation |
| no seed, twice | different from each other | normal randomized gameplay is preserved |

The checksum is printed when a test seed is active, and also in headless runs so
these comparisons are possible. Desktop play prints nothing.

### G. Hunting system tests
Runs `scenes/tests/hunting_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/hunting_tests.tscn
```

The suite prints one `PASS`/`FAIL` line per check and ends with
`RESULT: <n> checks, <m> failed`, exiting `0` only when nothing failed. Check G
requires all of: exit code 0, no project errors in the output, a result summary
with at least 50 checks, and `0 failed`. A partial run cannot pass: an exit
without a summary, or a summary with too few checks, is a failure.

Two independent guards stop a broken suite from hanging:

- **Inside the suite** a watchdog timer ends the process with code `2` and a
  failure summary if the tests do not reach their verdict within 90 seconds
  (this covers a script error that aborts the test entry point).
- **In the harness** every engine run has a wall-clock limit (`GODOT_TIMEOUT`,
  180 s by default); exceeding it reports `timed out after Ns` as a failure and
  keeps going (this covers a genuine infinite loop, which no timer can interrupt).

What it verifies, in three groups.

*Behaviour (`scripts/animals/deer_ai.gd`, simulated at a fixed 60 Hz step):*

| Area | Checks |
|---|---|
| Detection | a hunter 17 m away is ignored; inside 13 m the deer becomes `ALERTED` |
| Alert delay | the deer freezes for 0.55 s instead of bolting instantly |
| State order | `GRAZING → ALERTED → FLEEING → ESCAPING`, and the speed that belongs to each |
| Speeds | sprint 5.6 m/s > hunter 4.4 m/s > tired 3.4 m/s |
| Fair chase | a fresh deer gains ground; sustained pursuit captures it, in 10.2 s, and not instantly or never (window: 3–30 s) |
| Escape | an unpursued deer breaks away at 23 m and returns to `GRAZING` |
| Boundaries | a fleeing deer stays inside the world and steers back from the edge |
| Determinism | the same seed replays the same hunt and the same grazing path; a different seed changes it |
| Capture | out-of-reach is refused, in-reach succeeds once, repeats are refused, count stays 1 |
| Signals | `deer_captured` and `hunt_started` fire exactly once each |
| New hunt | cannot start before a capture, starts after one, advances the index, capture works again |

*Models (mesh bounding boxes, no renderer):* the hunter measures 2.13 m to the
hood tip, 0.84 × 0.74 m in footprint, with boots on the ground; the deer measures
1.81 m to the antler tips, 1.40 m long, 0.51 m wide, hooves on the ground. These
catch a collapsed or floating model, not an ugly one.

*Live scene (`scenes/main.tscn`):* the hunter rig has 56 mesh parts and the deer
46; the hunter's legs rotate when walking; the deer's neck moves between idle
poses; every deer state poses without error; walking into the deer captures it
exactly once, disables its collision, stops its movement and takes it out of
active play; the button becomes `NEW HUNT`; pressing it starts a new hunt with a
visible, colliding, grazing deer at least 15 m away.

Exact hunting values, all named constants:

| Constant | Value | File |
|---|---|---|
| `HUNTER_SPEED` | 4.4 m/s | `scripts/main.gd` |
| `DETECT_RADIUS` | 13.0 m | `deer_ai.gd` |
| `ALERT_DURATION` | 0.55 s | `deer_ai.gd` |
| `SPRINT_SPEED` | 5.6 m/s | `deer_ai.gd` |
| `SPRINT_DRAIN` | 0.35 stamina/s | `deer_ai.gd` |
| `SPRINT_EXIT_STAMINA` | 0.25 | `deer_ai.gd` |
| `ESCAPE_SPEED` | 3.4 m/s | `deer_ai.gd` |
| `STAMINA_REGEN` | 0.06 stamina/s | `deer_ai.gd` |
| `SECOND_WIND_DISTANCE` / `_STAMINA` | 7.5 m / 0.45 | `deer_ai.gd` |
| `ESCAPE_BREAK_DISTANCE` / `_STAMINA` | 23.0 m / 0.60 | `deer_ai.gd` |
| `STEER_INTERVAL` | 0.30 s | `deer_ai.gd` |
| `GRAZE_SPEED` | 1.05 m/s | `deer_ai.gd` |
| `WORLD_LIMIT` / `BOUNDARY_MARGIN` | 41.0 m / 5.0 m | `deer_ai.gd` |
| `CAPTURE_DISTANCE` | 1.8 m | `hunt_session.gd` |
| `NEW_HUNT_MIN_DISTANCE` / `_MAX_` | 16.0 m / 26.0 m | `main.gd` |

### H. Camera and visual tests
Runs `scenes/tests/visual_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/visual_tests.tscn
```

Same contract as G: exit code 0, no project errors, a `RESULT:` summary with at
least 45 checks, and `0 failed`. It uses the real main scene and its real physics
world, because the camera's obstruction probe is a physics query — a mock world
would prove nothing.

| Area | What is asserted | Measured in the last run |
|---|---|---|
| Framing | camera rig exists, is current, 60° field of view | 60 deg |
| Distance | holds its configured follow distance | 6.00 m |
| Position | sits 4–7.5 m behind and 1.6–3.4 m above the hunter | 5.85 m behind, 2.80 m up |
| Readability | hunter occupies >20% of the frame height | 31% |
| Shoulder | camera offset from the hunter's centre line | 0.62 m |
| Obstruction | a layer-2 cylinder on the camera line pulls it in | 6.00 → 2.17 m |
| Obstruction safety | never inside the obstacle, never below the ground floor | 0.78 m clear, y = 2.76 |
| Recovery | returns to full distance after the obstacle is removed | 6.00 m |
| Stability | no jitter while the hunter stands still | 0.000 m over 30 frames |
| Smoothing | a 3 m jump moves the camera < 2 m in one frame | 0.42 m |
| Canopy clearance | worst-case camera height stays below foliage | 2.88 m vs 3.60 m |
| Forest size | full stand plus a distant treeline | 84 + 54 trees |
| Instancing | many trees, few nodes | 17 nodes for 138 trees |
| Variety | enough distinct tree shapes | 8 variants |
| Spacing | trunks keep at least the configured gap | 3.53 m |
| Clear areas | no tree in the clearing, spawn pocket or ruin | 4.5 m / 6.0 m clear |
| Height range | trees vary in height | 6.9 – 13.4 m |
| Collision | trunks answer layer 2 only, one collider each | 84 colliders |
| Determinism | same seed reproduces the forest, a new seed changes it | identical / different |
| Lighting | fog, tonemapping, ambient, soft lifted shadows, no second shadow map | density 0.0095, filmic, ambient 1.00, blur 1.6, opacity 0.78 |
| Ground | textured albedo, normal map, matte, still collides | roughness 0.96 |
| Deer cue | hides when close and in view, chevron when behind, diamond when far | 4 states |
| Gameplay | hunter speed, walking through trunks, deer still flees, rigs in use | 4.40 m in 1 s, FLEEING |

Camera and world constants, all named:

| Constant | Value | File |
|---|---|---|
| `DISTANCE` / `PITCH_DEGREES` | 6.0 m / −14° | `camera_rig.gd` |
| `FOCUS_HEIGHT` / `FIELD_OF_VIEW` | 1.35 m / 60° | `camera_rig.gd` |
| `SHOULDER_OFFSET` | 0.62 m | `camera_rig.gd` |
| `MIN_DISTANCE` / `CLOSE_RANGE` | 1.2 m / 3.4 m | `camera_rig.gd` |
| `CLOSE_PITCH_LIFT` | 30° | `camera_rig.gd` |
| `FOLLOW_RATE` / `YAW_RATE` / `PULL_OUT_RATE` | 9 / 5 / 3 per s | `camera_rig.gd` |
| `PROBE_RADIUS` / `OBSTRUCTION_MASK` | 0.32 m / layers 1+2 | `camera_rig.gd` |
| `TREE_COUNT` / `FAR_TREE_COUNT` | 84 / 54 | `forest.gd` |
| `MIN_SPACING` / `INNER_RADIUS` / `OUTER_RADIUS` | 3.5 m / 14 m / 43 m | `forest.gd` |
| `CANOPY_BOTTOM` / `COLLISION_LAYER` | 3.6 m / layer 2 | `forest.gd` |
| `SUN_ENERGY` / `SUN_SHADOW_OPACITY` / `SUN_SHADOW_BLUR` | 1.55 / 0.78 / 1.6 | `wilds_environment.gd` |
| `AMBIENT_ENERGY` / `FILL_ENERGY` | 1.00 / 0.30 | `wilds_environment.gd` |
| `FOG_DENSITY` / `FOG_SKY_AFFECT` | 0.0095 / 0.85 | `wilds_environment.gd` |
| `ALBEDO_TILE` / `NORMAL_TILE` | 26 / 58 | `wilds_ground.gd` |
| `ON_SCREEN_DISTANCE` / `EDGE_MARGIN` | 15 m / 76 px | `deer_marker.gd` |

### I. Wildlife AI tests
Runs `scenes/tests/wildlife_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/wildlife_tests.tscn
```

Same contract as G and H: exit code 0, no project errors, a `RESULT:` summary
with at least 90 checks, and `0 failed`. Perception and avoidance are fed fake
probes (an open field, an infinite wall, permanent cover), so line of sight and
obstacle avoidance are tested without a renderer or real physics; the last group
loads the real scene to prove the brain is wired to it.

| Area | What is asserted |
|---|---|
| Architecture | the brain is split into profile, perception and steering layers |
| Calm behaviour | grazing, watching and wandering cycle on timers; no state change every frame; minimum dwell respected; a grazing deer walks; it drifts back from the world edge |
| Vision | seen at 12.5 m ahead; missed at 20 m; missed 12 m directly behind; noticed 6 m behind; a trunk blocks sight, even at close range; field of view is panoramic but not all-round; personality never moves the detection distance |
| Hearing | a running hunter is heard from behind and causes an alarm; the same hunter beyond earshot is not heard; a walking hunter at that range is not heard; a standing hunter is silent but visible; quiet footsteps behind cover are heard without an alarm |
| Memory | a sighting is stored with its position; cover does not erase it; it keeps the deer from relaxing; it expires on its own; seeing the threat again refreshes it |
| Alarm flow | a close threat leads to flight; a distant one is investigated; investigating closes distance and then ends by itself; returning re-alerts if the hunter reappears; the deer relaxes again |
| Flight | sprint and escape speeds are the tuned ones; speed cap respected; no per-frame teleport; breaking away goes through `RETURNING` before grazing |
| Avoidance | a blocked course is turned aside; the chosen detour is open; the deer commits to one side; it runs along a wall instead of through it or stalling |
| Personality | all four temperaments appear across 60 seeds; memory and hearing differ; the same seed gives the same animal; speeds never change; every temperament is still catchable in 3–30 s |
| Determinism | the same seed replays the same states and positions; another seed diverges |
| Compatibility | capture is single-shot, reset restores a calm rested deer, `state_changed` fires once per transition, the hunt session still starts and ends a hunt |
| Live scene | the scene uses the layered brain, a temperament is assigned, the deer notices a hunter in the open and moves away, every state poses cleanly, walking into it still captures it |

Wildlife values, all named constants:

| Constant | Value | File |
|---|---|---|
| `DETECT_RADIUS` (sight floor) | 13.0 m | `deer_ai.gd` |
| `VISION_ANGLE_DEGREES` | 300° (±150°) | `deer_ai.gd` |
| `PROXIMITY_RANGE` | 10.0 m | `deer_ai.gd` |
| `HEARING_RANGE` | 18.0 m at a sprint | `deer_ai.gd` |
| `MEMORY_TIME` | 6.0 s (×0.6 when only heard) | `deer_ai.gd` |
| `RECOVERY_TIME` | 4.0 s | `deer_ai.gd` |
| `ALERT_DURATION` | 0.55 s freeze | `deer_ai.gd` |
| `confirm_distance` | vision × 0.74–0.90 | `wildlife_profile.gd` |
| `NOISE_ALERT_LEVEL` | 0.45 of a sprint | `deer_ai.gd` |
| `NOISE_REFERENCE_SPEED` / `MIN_NOISE_SPEED` | 4.4 m/s / 0.3 m/s | `wildlife_perception.gd` |
| `ACCELERATION` / `DECELERATION` | 9.0 / 14.0 m/s² | `deer_ai.gd` |
| `AVOID_LOOKAHEAD` / `AVOID_REFRESH` | 2.8 m / 0.45 s | `deer_ai.gd` |
| `MIN_DWELL` | 0.9 s | `deer_ai.gd` |
| `SPRINT_SPEED` / `ESCAPE_SPEED` / `GRAZE_SPEED` | 5.6 / 3.4 / 1.05 m/s | `deer_ai.gd` |
| `TRAIT_JITTER` | ±6% | `wildlife_profile.gd` |

Temperaments (multipliers on the blueprint, `wildlife_profile.gd`):

| Archetype | Field of view | Hearing | Memory | Recovery | Confirm flight at |
|---|---|---|---|---|---|
| steady | ×1.00 | ×1.00 | ×1.00 | ×1.00 | 0.82 × sight |
| cautious | ×1.03 | ×1.05 | ×1.30 | ×1.35 | 0.90 × sight |
| bold | ×0.93 | ×0.92 | ×0.80 | ×0.85 | 0.74 × sight |
| nervous | ×1.00 | ×1.18 | ×1.10 | ×1.15 | 0.86 × sight |

### J. Living world tests
Runs `scenes/tests/world_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/world_tests.tscn
```

Same contract as G–I: exit code 0, no project errors, a `RESULT:` summary with
at least 85 checks, and `0 failed`. The clock and the weather are stepped
directly at 60 Hz; the last groups load the real scene and drive the lighting,
the shader parameters and the rain emitter by hand.

| Area | What is asserted |
|---|---|
| Clock | advances with real time, wraps past midnight, reports every phase boundary, reads 12:00 at noon |
| Daylight | noon reproduces the approved sun (1.55), ambient (1.00) and fog (0.0095); sunrise and sunset are warm twilight moments; moonlight is cool |
| Night | full darkness still has moon light, an ambient floor, lifted exposure and a combined light budget above 0.7 |
| Continuity | over 720 samples the sun energy never steps more than 0.05, ambient 0.03, fog colour 0.03, and no frame is unlit |
| Weather | starts clear, changes at least three times in seven minutes, respects the hold time, only reports known conditions, rain only in rain, blends without snapping |
| Conditions | rain dims and thickens, fog is thicker than rain and still leaves more than 20 m of visibility, conditions get progressively hazier |
| Determinism | the same seed replays the same weather sequence, a different seed diverges |
| Wildlife modifiers | clear midday is exactly 1.0; night lowers sight and raises hearing and memory; rain masks sound; every combination stays inside the fairness band |
| Wildlife at night | a night-scaled deer is still catchable in 3–30 s, misses a hunter at 12 m and reacts at 10.5 m |
| Scene | one bounded rain system that casts no shadow, wind shader on trees and grass, eight variants sharing one material, single shadow map, throttled environment updates |
| Scene night and rain | night dims but never blacks out the light, the HUD clock moves, the deer's senses follow, rain emits and thickens fog, the ground looks wet and dries again |

Living world values, all named constants:

| Constant | Value | File |
|---|---|---|
| `SECONDS_PER_DAY` | 480 s | `day_cycle.gd` |
| `START_TIME` | 0.5 (noon) | `day_cycle.gd` |
| `MAX_SUN_ELEVATION` / `MOON_ELEVATION` | 44° / 38° | `day_cycle.gd` |
| `DAY_SUN_ENERGY` / `MOON_ENERGY` / `TWILIGHT_ENERGY` | 1.55 / 0.55 / 0.80 | `day_cycle.gd` |
| `DAY_AMBIENT_ENERGY` / `NIGHT_AMBIENT_ENERGY` | 1.00 / 0.92 | `day_cycle.gd` |
| `DAY_EXPOSURE` / `NIGHT_EXPOSURE` | 1.45 / 1.72 | `day_cycle.gd` |
| `TRANSITION_SECONDS` | 14 s | `weather.gd` |
| `HOLD_MIN` / `HOLD_MAX` | 38 s / 85 s | `weather.gd` |
| Fog multipliers (clear/cloudy/rain/fog) | 1.0 / 1.45 / 2.05 / 3.40 | `weather.gd` |
| Sun multipliers (clear/cloudy/rain/fog) | 1.0 / 0.68 / 0.50 / 0.58 | `weather.gd` |
| `PARTICLE_COUNT` | 700 | `rain.gd` |
| `APPLY_INTERVAL` | 0.1 s | `living_world.gd` |
| Wildlife vision floor / hearing floor | ×0.78 / ×0.72 | `living_world.gd` |
| `WIND_STRENGTH` / wind strength in rain | 0.14 m / ×1.25 | `forest.gd`, `weather.gd` |

---

### K. Audio tests
Runs `scenes/tests/audio_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/audio_tests.tscn
```

Same contract as G–J: exit code 0, no project errors, a `RESULT:` summary with
at least 80 checks, and `0 failed`. The suite also reads the shipped WAV headers
directly, because the importer re-encodes them.

| Area | What is asserted |
|---|---|
| Files | all 17 sounds exist, load as streams, sit under 3 MB, use the documented sample rates, and no bed is shorter than its loop |
| Levels | no file clips, none is silent, the interface tap and a footstep stay under 0.3 s |
| Provenance | `assets/audio/LICENSE.txt` ships with the project and states the audio is generated, not borrowed |
| Import | long beds are compressed on import rather than held as raw PCM |
| Buses | Master, Music and SFX exist and both sub-buses send to Master |
| Settings | defaults, clamping, the effects bus following the slider, mute muting the Master bus, unmute restoring the level |
| Persistence | save → new instance → load round-trip of volumes and mute, a missing file falling back to defaults, `reset()` restoring them |
| Director | 8–12 players total, both ambience beds running for cross-fade, loop flags set, music at least 12 dB under the effects, rain fading in with the weather, night taking over from day |
| Footsteps | silence while standing, steps while walking, stone inside the ruin and grass/soil outside, a fixed reused pool |
| 3D | the deer owns inverse-distance players with a bounded range and panning, the snort and flight call fire at its position, hooves stop with the animal |
| Scene | the panel exists with three sliders and mute, starts collapsed, opens and closes, slider and mute changes reach the settings, weather reaches the rain bed, the live deer's snort is audible, the button taps, and capture still captures |

Audio values, all named constants in `scripts/audio/audio_director.gd`:

| Constant | Value |
|---|---|
| `AMBIENCE_DAY_DB` / `AMBIENCE_NIGHT_DB` | −15 / −14 dB |
| `RAIN_DB` / `MUSIC_DB` | −11 / −17 dB |
| `STEP_DB` / `HOOF_DB` / `VOICE_DB` / `SFX_DB` | −9 / −13 / −7 / −8 dB |
| `STEP_INTERVAL` / `DEER_RUN_INTERVAL` | 0.33 s / 0.22 s |
| `AUDIBLE_RANGE` | 42 m |
| `SFX_POOL_SIZE` | 4 players |
| Default master / music / effects | 0.9 / 0.55 / 0.85 |

---

### L. Interface, localization and settings
Runs `scenes/tests/ui_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/ui_tests.tscn
```

Same contract as G–K: exit code 0, no project errors, a `RESULT:` summary with at
least 150 checks, and `0 failed`. Section L also checks the repository itself: no
hardcoded visible strings in `scripts/ui` or `scripts/settings`, every key the
game asks for exists in the CSV, every row has both languages, and the fonts and
their licences ship.

| Area | What is asserted |
|---|---|
| Assets | the CSV parses, 79 keys, no duplicate or blank rows, both columns present and genuinely translated, Arabic rows contain Arabic letters |
| Runtime | Arabic is the default, English switches every string, unknown keys and locales fall back safely, RTL/LTR layout direction and text alignment follow the language |
| Look | one shared theme, a packaged Arabic font with Arabic and Latin glyphs, an ordered type scale, a distinct palette, minimum 56 px touch targets |
| Localization | no control in the HUD, title, pause, settings or confirmation screens shows untranslated text, in either language |
| HUD | status, information, action, context, pause and three vitals exist; the context button hides when there is nothing to do; a toast appears and fades |
| Layout | at 1280×720, 2400×1080, 800×360, 2048×1536 and 1920×1080: touch targets stay ≥ 56 px, every control is inside the screen, the stick and action button cannot be hit together, the panel keeps its corner, the toast never covers the action button |
| Safe areas | a notch inset pushes the pad and the panel inwards; a short screen drops the title, clock and hint rather than stacking text over the controls |
| Stick | a touch grabs it, a second finger is ignored, a release anywhere resets it, the deadzone keeps a resting thumb still, full tilt never exceeds 1, sensitivity scales the push, the mouse path works |
| Settings | save → new instance → load round-trips language, quality, sensitivity and the Phase 3.4 volumes; invalid values clamp or fall back; a missing file is not fatal; reset restores defaults; only the low level turns shadows off |
| Menus | pause suspends the hunt and releases the stick, resume restores it, settings open over pause and return to it, language and graphics changes apply live and persist, restart and return-to-title both require confirmation |
| Scene | the scene exposes the old `hunt_button`/`status_label`/`deer_marker` references, boots in Arabic, captures on contact, relabels to NEW HUNT and starts a fresh hunt |

What this cannot prove: it measures rectangles and delivers synthetic touches with
no renderer and no display, so it does not show that the interface *looks* right,
that a real thumb reaches every control comfortably, or how a specific phone
shapes Arabic text. Those need a device; see section 5.

### M. World regions
Runs `scenes/tests/region_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/region_tests.tscn
```

Same contract as G–L: exit code 0, no project errors, a `RESULT:` summary with at
least 300 checks, and `0 failed`. Section M also checks the repository: the
region table must define exactly ten entries, and the region sources must exist.

| Area | What is asserted |
|---|---|
| Data | ten regions exist with the brief's ids, unique ids, every field present, a landmark, exits that point at real regions, no region exiting to itself, and a gate far enough from the entry point |
| Text | every region name and description key exists in both languages, plus the HUD, status, toast, menu and screen keys |
| Identity | ten distinct ground palettes, ten landmark styles, nine non-neutral atmospheres (the silver forest is neutral on purpose), and ground cover in every region |
| Loading | the manager loads a region, installs nodes, reports the same counts it built, discovers the region, and leaves exactly one ground, one grass batch and one collision body |
| Unloading | loading another region removes the previous nodes, never stacks two grounds, and frees the old nodes by the next frame; unconditional unload returns the scene to its baseline |
| Budget | each of the ten regions stays under 60 nodes, 40 mesh instances and 12 materials, and the suite prints the worst region it measured |
| Determinism | two managers with the same seed produce the same geometry fingerprint for the silver forest, the desert and the void realm; a different seed changes it; two unseeded managers differ |
| Missing resources | an unknown region id is refused with a reason and the current region stays loaded; a definition without a gate, with an inverted vegetation ring, or exiting to itself is rejected; an unknown landmark style still builds a stone circle; a treeless region still provides a collision body |
| Travel | the scene boots in the silver forest, travels to the desert and back, keeps breath, the capture count and the secured quarry, moves the hunter to the entry point, replaces the ground, applies the region's atmosphere, places the quarry inside the habitat band with the habitat's temperament, updates the HUD name and the discovery count, and refuses travel to the same or an unknown region |
| Gate | standing on the gate turns the context button into travel, and walking away hides it |
| Screen | the region screen lists ten regions, opens on the current one, disables travel for it, describes the selection, requests travel for another region, and closes once |
| Reachability | all ten regions can actually be entered in one session, and the discovery indicator reaches ten |

What this cannot prove: the suite measures nodes, colours and numbers without a
renderer, so it cannot show that the ten regions *look* distinct or pleasant.
That needs a screen; see section 7.

### N. Phase 4 models and combat
Runs `scenes/tests/combat_tests.tscn` headlessly:

```bash
godot --headless --path . res://scenes/tests/combat_tests.tscn
```

Same contract as G–M: exit code 0, no project errors, a `RESULT:` summary with at
least 100 checks, and `0 failed`. Section N also inspects the repository: both
imported models must be real GLB files (the `glTF` magic and more than 100 KiB of
geometry, so a placeholder cannot pass), both must appear in the asset manifest,
and the manifest and credits must name CC0.

| Area | What is asserted |
|---|---|
| Manifest | the file exists, parses as JSON, lists both assets, and every entry has a file that exists, an `https://` source, a creator, a recognised license, modification and redistribution permissions, and an attribution line |
| Loading | a missing model returns `ok = false` with a reason instead of crashing; a real scene without a skeleton is refused; the hunter loads 62 bones and 24 clips, the deer 38 bones and 14 clips, and both are normalised to their target height |
| Rigs | the hunter rig builds an `AnimationTree`, catalogs its clips, picks idle/walk/run from speed, scales playback with speed, plays a one-shot attack that ends by itself, returns to idle, holds a guard clip, dies, refuses actions while dead and revives; the deer plays eating, walk, gallop and head-low rest for its states and animates every state without error |
| Combat rules | light and heavy attacks cost stamina, a second attack mid-swing is refused, each swing opens exactly one hit window, phases run windup → active → recovery, stamina gates attacks and dodges, stamina regenerates after a delay, a dodge has an invulnerability window, a blocked hit keeps 20% damage and spends stamina, holding block drains it, unblocked hits stagger, enough damage kills, and `heal_full` restores the hunter |
| Camera | the camera builds and becomes current, zoom changes and clamps to 3.2–9 m, dragging orbits the camera, yaw and pitch offsets clamp, sensitivity is settable with a floor, lock-on takes a target, stays locked while it lives, pulls the camera in, and releases |
| Mobile controls | six combat controls exist, the camera drag area exists, tapping a control emits its action, the cluster hides and shows, every button stays on screen with safe-area insets, no two overlap, the layout fits 1280×720, 960×540, 720×1280 and 1600×900, and the buttons grey out or highlight from combat state |
| Live scene | the scene owns combat and a training target, an attack inside reach damages the target and an attack out of reach misses, the target can be knocked down and resets, attacking spends stamina, the deer can still be captured and keeps animating, lock-on takes and releases the nearest target, and the regions, living world and audio are still attached |

What this cannot prove: no model is rendered here, so the suite cannot say the
hunter looks like a hunter or that the deer's coat reads on a phone. Those are
judged from the Phase 4 screenshots in section 7, and from play.

## 4. Reading the result

Each check prints `PASS` or `FAIL`, failures print the exact diagnostic lines
that caused them, and the run ends with a summary:

```
== Summary ==
  208 checks, 0 failed
  ALL CHECKS PASSED
```

Checks G–N are one line each here; the 78 hunting, 53 camera/visual, 100
wildlife, 95 living world, 86 audio, 217 interface, 398 region and 138 combat and
model checks they gate are listed in full in `hunting-tests.log`,
`visual-tests.log`, `wildlife-tests.log`, `world-tests.log`, `audio-tests.log`,
`ui-tests.log`, `region-tests.log` and `combat-tests.log`, and summarised as
`RESULT: <n> checks, 0 failed` — 1,165 checks in total.

A failing run keeps its logs (also on success with `--verbose`) and prints the
directory, e.g.:

```
Logs kept in /tmp/athar-verify.Ab3d9K
```

Useful log files:

| File | Contents |
|---|---|
| `import.log` | full engine output of the import |
| `import.errors` | project errors found in the import, after filtering |
| `check-*.log` / `check-*.log.err` | per-script parse output |
| `startup.log` / `startup.errors` | full startup run and its project errors |
| `seed_*.log`, `rand_*.log` | the five world-generation runs |
| `hunting-tests.log` | the full hunting suite output |
| `hunting.errors` | project errors found in the hunting run, after filtering |
| `visual-tests.log` | the full camera/visual suite output |
| `visual.errors` | project errors found in the visual run, after filtering |
| `wildlife-tests.log` | the full wildlife AI suite output |
| `wildlife.errors` | project errors found in the wildlife run, after filtering |
| `world-tests.log` | the full living world suite output |
| `world.errors` | project errors found in the living world run, after filtering |
| `audio-tests.log` | the full audio suite output |
| `audio.errors` | project errors found in the audio run, after filtering |

Intended workflow on failure:

1. Read the failing check and its diagnostic.
2. Reproduce that single step by hand, e.g.
   `godot --headless --path . --check-only --script res://scripts/main.gd`.
3. Fix the cause. Do not silence the check, and do not tighten the filter in §5
   to hide a real error.

A `FAIL` in check F ("same seed produced different worlds") means world
generation has become non-deterministic, usually because new code consumed
random numbers before or between the seeded steps.

---

## 5. Known environment limitations

These are honest gaps. None of them makes the automated run green by default.

- **The harness itself renders nothing.** Every check above runs under Godot's
  headless dummy renderer. It proves the scene builds, the camera geometry is
  sane and the world is configured as intended; it cannot prove that the result
  looks right. Rendered evidence exists separately (section 7) and still needs a
  human eye, especially on a phone screen.
- **Screenshots are software-rendered.** They were produced with Mesa's lavapipe
  Vulkan driver on a CPU. Geometry, materials, shadows and fog are the engine's
  own maths, but colour precision, antialiasing and performance on a real
  Adreno/Mali GPU are not reproduced.
- **Font warnings are filtered, not fixed.** The build container for this
  project historically had no `libfontconfig.so.1`, so every run prints
  `ERROR: Unable to load fontconfig, system font support is disabled.` (also seen
  on `--version`) plus a loader warning. These are environmental, appear before
  the project is even read, and are excluded by name in
  `IGNORE_PATTERNS`. The filter is a narrow allowlist — any other error still
  fails the run.
- **Sound cannot be heard in this environment.** There is no audio device, so
  every run falls back to Godot's dummy audio driver
  (`All audio drivers failed, falling back to the dummy driver`). The audio suite
  therefore verifies that the files exist and decode, that the buses and volumes
  are configured, which players are started, stopped and reused, that positional
  nodes are set up, and that gameplay events reach the director — never that a
  sound is pleasant, audible on a phone speaker, or correctly balanced. That
  needs a human ear on a device.
- **Input and touch are simulated.** There is no audio device and button presses
  cannot be delivered headlessly. The hunt button, the audio panel, the touch
  pads and the HUD interactions are exercised by emitting their signals
  directly. Touch event plumbing itself is unverified.
- **Balance is asserted, art is not.** The hunting suite encodes the agreed
  chase targets (sprint outruns the hunter, tired deer does not, capture inside
  3–30 s). It says nothing about whether the models *look* good, and no
  screenshot or render is produced anywhere in this harness.
- **Touch input is simulated, not touched.** The live-scene checks call the
  button's signal handler directly, so capture and `NEW HUNT` are exercised
  end-to-end in the scene, but no real touch event is delivered.
- **No Android checks.** No export preset, templates, SDK, or keystore are
  present, so no APK is built or validated. A device test remains the only real
  confirmation of the mobile build.
- **File discovery uses `find`.** In a checkout with unusual line endings the
  script still works, but it assumes the repository root is two levels above
  `scripts/verify_project.sh`.

---

## 6. Continuous integration

`.github/workflows/verify.yml` runs this script on pushes and pull requests to
the development branches, using the GitHub-hosted Ubuntu runner. It downloads
Godot **4.7.2 stable** from the official release URL and starts the script with
`GODOT=...`. No secret, token, or credential is used or required, and nothing is
deployed or published.

The workflow has to be confirmed by GitHub itself. Until a run has actually
completed there, treat it as unverified — this repository has never had a CI run
observed from this environment.

---

## 7. Rendered screenshots

The headless suites cannot see anything, so the visual phase adds a small
capture tool that renders the **real** main scene and writes PNGs:

```bash
# Any machine with a display and a Vulkan driver:
godot --path . --rendering-driver vulkan res://scenes/tools/capture_shots.tscn
```

It loads `scenes/main.tscn`, pauses gameplay, places the hunter and deer for five
situations, and writes `artifacts/*.png` (git-ignored). It also prints the camera
measurements and the frame cost, so the numbers in a report can be checked
against a run instead of being taken on trust:

```
SHOT spawn: camera_distance=6.00 obstructed=false
SHOT obstructed: tree=(9.59, 0.0, -11.78) camera_distance=1.93 clear=2.06 obstructed=true
RENDER_STATS draw_calls=268 objects=523 primitives=255976
SCENE_STATS nodes=265 trees=84 far_trees=54 tree_nodes=17
```

| Shot | What it is for |
|---|---|
| `01_spawn` | default gameplay framing: hunter readable, forest behind, deer ahead |
| `02_deer_close` | deer at close range in `ALERTED`, to judge the model and its contrast against foliage |
| `03_chase` | deer fleeing off to the side, showing that the shoulder offset keeps it out from behind the hunter |
| `04_obstructed` | hunter pinned against a trunk: the camera pulls in and looks over his shoulder instead of filling the screen with bark |
| `05_horizon` | treeline, fog and horizon seam at the world edge |

Phase 3.6 adds no screenshots: the environment the phase was developed in has no
display server, no root to install one and no software Vulkan driver, so the
capture tool cannot start there. The region suite asserts what can be asserted
without a renderer; whether the ten regions look distinct is unverified and needs
a machine with a display.

The committed copies live in `docs/screenshots/phase-3.1/` (960×540, downscaled
from the 1280×720 renders to keep the repository small).

### Behaviour screenshots

`scenes/tools/behaviour_shots.tscn` renders the animal itself, one frame per
behaviour state, using the same real scene and rig:

```bash
godot --path . --rendering-driver vulkan res://scenes/tools/behaviour_shots.tscn
```

It writes `artifacts/behaviour_0*.png` for `GRAZING`, `OBSERVING`, `ALERTED`,
`FLEEING`, `RETURNING` and `RESTING`, and the committed copies are in
`docs/screenshots/phase-3.2/`. Positions and camera are staged by hand; the
states, poses and animation are the project's own, so the images show what the
rig does with each state rather than a mock-up. They are a review aid, not a
test: nothing in the harness depends on them.

### Rendering without a GPU

This project's verification VM has no GPU and no display server, so the shots
above were produced with Mesa's software Vulkan driver:

```bash
# Ubuntu 24.04 packages, extracted without root into /tmp:
#   xvfb, x11-xkb-utils, xkb-data, libxfont2, libxfontenc, libpixman, libpng,
#   libfreetype, libxkbfile, libxcursor, libxrandr, libxi, libxinerama,
#   libxext, libxrender, libxfixes, libxkbcommon, libx11-xcb, libwayland-client,
#   mesa-vulkan-drivers (lavapipe)
Xvfb :99 -screen 0 1600x900x24 &          # inside a user namespace, because the
                                          # keymap path is hard-coded
export DISPLAY=:99
export VK_ICD_FILENAMES=/path/to/lvp_icd.json
godot --path . --rendering-driver vulkan --resolution 1280x720 \
      res://scenes/tools/capture_shots.tscn
```

Godot reports `Vulkan 1.4.318 - Forward+ - Using Device #0: llvmpipe`, i.e. the
project's own mobile/Forward+ renderer path on a CPU rasteriser. This is a
developer convenience, not a supported configuration, and it is **not** part of
`scripts/verify_project.sh` or CI: those run headless and must stay green on a
machine with no display at all.

### Phase 4 model, combat and mobile screenshots

`scenes/tools/phase4_shots.tscn` renders the same real scene from staged angles:

```bash
godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
      --display-driver x11 --resolution 1280x720 \
      res://scenes/tools/phase4_shots.tscn
```

It writes `artifacts/*.png` and prints `SHOT <name>` for each frame, then a
`CAPTURE_DONE` line listing all of them. The committed copies are in
`docs/screenshots/phase-4/`.

| Shot | What it is for |
|---|---|
| `01_hunter_front` | the imported hunter from the front: silhouette, face, gear, bow |
| `02_hunter_side` | the same model from the side, to judge proportions |
| `03_hunter_run` | the run clip mid-stride, to check the pose rather than the mesh |
| `04_hunter_attack` | the light attack clip during its swing |
| `05_hunter_block` | the raised guard with the HUD block control held |
| `06_deer_grazing` | the imported stag grazing, antlers and coat visible |
| `07_deer_alert` | the stag with its head up, the alert state |
| `08_deer_gallop` | the gallop clip, which is also the flee animation |
| `09_combat_target` | a swing at the training target from a player's side view, with stamina and HUD state |
| `10_mobile_controls` | the full touch layout: stick, six combat buttons, context button, toast |
| `11_forest_gameplay` | the default gameplay framing, to judge the forest after the colour work |

`scenes/tools/model_preview.tscn` renders a single model on a neutral backdrop,
which is useful when checking a new import before wiring it into a rig:

```bash
godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
      --display-driver x11 res://scenes/tools/model_preview.tscn
```

Unlike the Phase 3 tools, these renders use Godot's `gl_compatibility` backend on
Mesa's `llvmpipe` software OpenGL, because that is the path this VM can drive
(Xvfb plus software OpenGL, no Vulkan device). The images are therefore what the
**mobile renderer** draws, not the Forward+ path: colours and silhouettes carry
over, but shadow quality and post-processing do not.

### Living world screenshots

`scenes/tools/world_shots.tscn` renders the same scene at different hours and in
different weather:

```bash
godot --path . --rendering-driver vulkan res://scenes/tools/world_shots.tscn
```

It sets the clock and the weather on the real systems (not on the lights
directly) and writes `artifacts/world_0*.png` for midday, sunset, night, rain and
fog. The committed copies are in `docs/screenshots/phase-3.3/`.

Measured mean frame luminance of the committed renders (0–1, software renderer):
day 0.190, sunset 0.145, rain 0.145, fog 0.161, night 0.097. Night is the
darkest by design, but it is not black: the hunter, the deer and the treeline all
stay readable, which is the test the night lighting has to pass.
