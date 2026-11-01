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

---

## 4. Reading the result

Each check prints `PASS` or `FAIL`, failures print the exact diagnostic lines
that caused them, and the run ends with a summary:

```
== Summary ==
  71 checks, 0 failed
  ALL CHECKS PASSED
```

Checks G, H and I are one line each here; the 66 hunting, 53 camera/visual and
100 wildlife checks they gate are listed in full in `hunting-tests.log`,
`visual-tests.log` and `wildlife-tests.log`, and summarised as
`RESULT: <n> checks, 0 failed`.

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
- **No audio, input, or touch verification.** There is no audio device, and
  button presses cannot be delivered headlessly. The hunt button, touch pads,
  and HUD interactions are exercised only by the scene being built.
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
