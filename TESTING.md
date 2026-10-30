# ATHAR — Testing and Verification

How to check that the project still builds, parses, starts, and generates the
same world from the same seed — everything that can be verified without a
display, a GPU, or an Android toolchain.

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
`scenes/main.tscn`, `scripts/main.gd`, `icon.svg`, `icon.svg.import`,
`.gitignore`, `README.md`, `TESTING.md`, `assets/` — and that:

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

---

## 4. Reading the result

Each check prints `PASS` or `FAIL`, failures print the exact diagnostic lines
that caused them, and the run ends with a summary:

```
== Summary ==
  24 checks, 0 failed
  ALL CHECKS PASSED
```

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

- **No visual or GPU verification.** Headless mode uses a dummy renderer. The
  script confirms the scene builds and the game loop runs cleanly; it cannot
  confirm that anything looks right. Layout, colours, HUD readability, and
  shadows need a human on a real machine.
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
- **No gameplay-balance assertions.** Deliberately out of scope: current
  behaviour is recorded as-is, and no test encodes a balance target that was
  never agreed.
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
