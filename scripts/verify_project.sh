#!/usr/bin/env bash
#
# ATHAR - automated project verification.
#
# Runs every check that can be done without a display, a GPU, or an Android
# toolchain. Exits 0 only when every check passes.
#
# Usage:
#   ./scripts/verify_project.sh [--frames N] [--godot PATH] [--verbose] [--help]
#
# Environment:
#   GODOT                    Path to the Godot 4.7.2 executable.
#   REQUIRED_GODOT_VERSION   Version to require (default 4.7.2).
#   GODOT_TIMEOUT            Seconds allowed per engine run (default 180).
#
# See TESTING.md for what each check verifies and how to read the output.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRED_GODOT_VERSION="${REQUIRED_GODOT_VERSION:-4.7.2}"
FRAMES=180
VERBOSE=0
GODOT_BIN="${GODOT:-}"
# Every engine run is bounded: a scene that never reaches quit() must fail the
# harness instead of blocking it forever.
GODOT_TIMEOUT="${GODOT_TIMEOUT:-180}"

# Engine messages that are not project problems: this machine ships without
# fontconfig and without a display, so these appear on every run.
IGNORE_PATTERNS='Unable to load fontconfig|libfontconfig\.so|fontconfig, system font support is disabled'

usage() {
	sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		--frames) FRAMES="${2:?--frames needs a value}"; shift 2 ;;
		--godot) GODOT_BIN="${2:?--godot needs a value}"; shift 2 ;;
		--verbose|-v) VERBOSE=1; shift ;;
		--help|-h) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/athar-verify.XXXXXX")"
FAILURES=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
info() { printf '        %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

cleanup() {
	if [ "$FAILURES" -eq 0 ] && [ "$VERBOSE" -eq 0 ]; then
		rm -rf "$LOG_DIR"
	else
		printf '\nLogs kept in %s\n' "$LOG_DIR"
	fi
}
trap cleanup EXIT

# Project errors in a log: engine diagnostics with the environmental noise removed.
project_errors() {
	grep -aE '^(ERROR|SCRIPT ERROR|USER ERROR|FATAL|Parse Error|Failed to load|Failed to instantiate)' "$1" \
		| grep -avE "$IGNORE_PATTERNS"
}

# Prints the first lines of a filter's output, indented and bounded.
show() {
	local limit="${2:-10}"
	head -n "$limit" "$1" | sed 's/^/          /'
}

# Runs the engine under a wall-clock limit. Returns 124 when the limit is hit,
# which the sections report as a timeout rather than a pass.
godot_run() {
	if command -v timeout >/dev/null 2>&1; then
		timeout --kill-after=10 "$GODOT_TIMEOUT" "$GODOT_BIN" "$@"
	else
		"$GODOT_BIN" "$@"
	fi
}

printf 'ATHAR project verification\n'
printf 'Repository: %s\n' "$ROOT"

# ---------------------------------------------------------------- A. version --
section "A. Godot version"
if [ -z "$GODOT_BIN" ]; then
	for candidate in godot4 godot godot-4 \
		"$ROOT/Godot_v4.7.2-stable_linux.x86_64" \
		/tmp/godot/Godot_v4.7.2-stable_linux.x86_64; do
		if command -v "$candidate" >/dev/null 2>&1; then GODOT_BIN="$(command -v "$candidate")"; break; fi
		if [ -x "$candidate" ]; then GODOT_BIN="$candidate"; break; fi
	done
fi
if [ -z "$GODOT_BIN" ] || [ ! -x "$GODOT_BIN" ]; then
	fail "Godot executable not found (set GODOT=/path/to/godot)"
	printf '\nCannot continue without the engine.\n' >&2
	VERBOSE=1
	exit 1
fi
info "binary: $GODOT_BIN"

VERSION_RAW="$("$GODOT_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r')"
info "reported: ${VERSION_RAW:-<no output>}"
if [[ "$VERSION_RAW" == "$REQUIRED_GODOT_VERSION".* ]]; then
	pass "engine version is $REQUIRED_GODOT_VERSION"
else
	fail "engine version mismatch: expected $REQUIRED_GODOT_VERSION, got '${VERSION_RAW:-unknown}'"
fi

# ----------------------------------------------------------------- B. import --
section "B. Project import"
IMPORT_LOG="$LOG_DIR/import.log"
godot_run --headless --path "$ROOT" --import >"$IMPORT_LOG" 2>&1
IMPORT_STATUS=$?
project_errors "$IMPORT_LOG" >"$LOG_DIR/import.errors"
if [ "$IMPORT_STATUS" -eq 0 ]; then
	pass "headless import exited 0"
else
	fail "headless import exited $IMPORT_STATUS"
	show "$LOG_DIR/import.errors"
fi
if [ -s "$LOG_DIR/import.errors" ]; then
	fail "import reported project errors"
	show "$LOG_DIR/import.errors"
else
	info "no project errors in import output"
fi
if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ] && [ ! -d "$ROOT/.godot" ]; then
	fail "import did not produce the .godot cache directory"
fi

# ------------------------------------------------------------ C. GDScript ----
section "C. GDScript validation"
GD_FILES=()
while IFS= read -r file; do GD_FILES+=("$file"); done < <(
	cd "$ROOT" && find . -name '*.gd' -not -path './.godot/*' -not -path './.git/*' | sort
)
if [ "${#GD_FILES[@]}" -eq 0 ]; then
	fail "no GDScript files found"
fi
for file in "${GD_FILES[@]}"; do
	rel="${file#./}"
	log="$LOG_DIR/check-$(echo "$rel" | tr '/' '_').log"
	godot_run --headless --path "$ROOT" --check-only --script "res://$rel" >"$log" 2>&1
	status=$?
	project_errors "$log" >"$log.err"
	if [ "$status" -eq 0 ] && [ ! -s "$log.err" ]; then
		pass "$rel parses"
	else
		fail "$rel failed to parse (exit $status)"
		show "$log.err"
	fi
done

# ------------------------------------------------------------- D. startup ----
section "D. Headless startup ($FRAMES frames)"
START_LOG="$LOG_DIR/startup.log"
godot_run --headless --path "$ROOT" --quit-after "$FRAMES" >"$START_LOG" 2>&1
START_STATUS=$?
project_errors "$START_LOG" >"$LOG_DIR/startup.errors"
if [ "$START_STATUS" -eq 0 ]; then
	pass "project ran $FRAMES frames and exited cleanly"
else
	fail "project exited with $START_STATUS after $FRAMES frames (crash or unexpected termination)"
	show "$LOG_DIR/startup.errors"
fi
if [ -s "$LOG_DIR/startup.errors" ]; then
	fail "runtime errors during startup"
	show "$LOG_DIR/startup.errors"
else
	info "no runtime errors during startup"
fi
if grep -aq '^ATHAR_TEST_WORLD_CHECKSUM=' "$START_LOG"; then
	pass "main scene built and world generated"
else
	fail "main scene did not finish building (no world checksum printed)"
	show "$START_LOG" 20
fi

# ----------------------------------------------------- E. repository integrity
section "E. Repository integrity"
for required in project.godot scenes/main.tscn scenes/tests/hunting_tests.tscn scenes/tests/visual_tests.tscn scenes/tests/wildlife_tests.tscn scenes/tests/world_tests.tscn scenes/tests/audio_tests.tscn scenes/tools/capture_shots.tscn scenes/tools/behaviour_shots.tscn scenes/tools/world_shots.tscn scripts/main.gd scripts/animals/deer_ai.gd scripts/animals/wildlife_profile.gd scripts/animals/wildlife_perception.gd scripts/animals/wildlife_steering.gd scripts/gameplay/hunt_session.gd scripts/tests/hunting_tests.gd scripts/tests/visual_tests.gd scripts/tests/wildlife_tests.gd scripts/tools/behaviour_shots.gd scripts/world/day_cycle.gd scripts/world/weather.gd scripts/world/rain.gd scripts/world/living_world.gd scripts/tests/world_tests.gd scripts/tests/audio_tests.gd scripts/tools/world_shots.gd scripts/audio/audio_director.gd scripts/audio/audio_settings.gd scripts/ui/audio_panel.gd scripts/ui/hud.gd scripts/ui/localization.gd scripts/ui/ui_kit.gd scripts/ui/virtual_joystick.gd scripts/ui/vitals_bar.gd scripts/ui/main_menu.gd scripts/ui/pause_menu.gd scripts/ui/settings_menu.gd scripts/ui/confirm_prompt.gd scripts/settings/game_settings.gd scripts/settings/graphics_profile.gd scripts/tests/ui_tests.gd scenes/tests/ui_tests.tscn scenes/ui/hud.tscn scenes/ui/main_menu.tscn scenes/ui/pause_menu.tscn scenes/ui/settings_menu.tscn scenes/ui/confirm_prompt.tscn scripts/world/region_definition.gd scripts/world/region_builder.gd scripts/world/region_manager.gd scripts/ui/region_menu.gd scenes/ui/region_menu.tscn scripts/tests/region_tests.gd scenes/tests/region_tests.tscn localization/ui_strings.csv assets/fonts/Amiri-Bold.ttf assets/fonts/IBMPlexSansArabic-Regular.ttf assets/fonts/IBMPlexSansArabic-SemiBold.ttf assets/fonts/OFL-Amiri.txt assets/fonts/OFL-IBMPlexSansArabic.txt audio/default_bus_layout.tres tools/generate_audio.py assets/audio/LICENSE.txt shaders/vegetation_wind.gdshader scripts/visuals/deer_rig.gd scripts/visuals/hunter_rig.gd scripts/visuals/rig_utils.gd scripts/visuals/camera_rig.gd scripts/visuals/forest.gd scripts/visuals/wilds_ground.gd scripts/visuals/wilds_environment.gd scripts/ui/deer_marker.gd scripts/tools/capture_shots.gd icon.svg icon.svg.import .gitignore README.md TESTING.md assets; do
	if [ -e "$ROOT/$required" ]; then
		pass "$required present"
	else
		fail "$required is missing"
	fi
done

MAIN_SCENE_SETTING="$(grep -aE '^run/main_scene=' "$ROOT/project.godot" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"')"
if [ "$MAIN_SCENE_SETTING" = "res://scenes/main.tscn" ]; then
	pass "project.godot points at res://scenes/main.tscn"
else
	fail "unexpected main scene setting: '${MAIN_SCENE_SETTING:-missing}'"
fi
if grep -aq 'path="res://scripts/main.gd"' "$ROOT/scenes/main.tscn"; then
	pass "main scene is wired to scripts/main.gd"
else
	fail "main scene does not reference scripts/main.gd"
fi

GIT_PROBE="$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>&1)"
if [ "$GIT_PROBE" = "true" ]; then
	ARTIFACT_PATTERN='(^|/)\.godot/|\.tmp$|\.log$|\.orig$|\.rej$|(^|/)__pycache__/|(^|/)\.DS_Store$|(^|/)Thumbs\.db$|\.apk$|\.aab$|\.keystore$|\.jks$|(^|/)node_modules/|(^|/)\.import/'
	if git -C "$ROOT" ls-files | grep -aE "$ARTIFACT_PATTERN" >"$LOG_DIR/artifacts"; then
		fail "generated or temporary files are tracked"
		show "$LOG_DIR/artifacts"
	else
		pass "no generated or temporary files tracked"
	fi
	if git -C "$ROOT" check-ignore -q .godot 2>/dev/null; then
		pass ".godot/ is ignored"
	else
		fail ".godot/ is not ignored by .gitignore"
	fi
	if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
		info "note: working tree has uncommitted changes"
	fi
elif [ -e "$ROOT/.git" ]; then
	# A .git that git refuses to read (e.g. a copied worktree gitfile) would
	# silently skip these checks, so report it instead of passing.
	fail "git cannot inspect this checkout: $(echo "$GIT_PROBE" | head -n 1)"
else
	info "not a git checkout, skipping tracked-artifact checks"
fi

# ------------------------------------------- F. reproducible gameplay (seed) --
section "F. Reproducible gameplay"
run_world() {
	local log="$1"; shift
	godot_run --headless --path "$ROOT" --quit-after 3 "$@" >"$log" 2>&1
}
checksum_of() { sed -n 's/^ATHAR_TEST_WORLD_CHECKSUM=//p' "$1" | head -n 1; }

if [ "$VERBOSE" -eq 1 ]; then info "comparing world layouts generated across runs"; fi

run_world "$LOG_DIR/seed_a.log" -- --seed=20261030
run_world "$LOG_DIR/seed_b.log" -- --seed=20261030
run_world "$LOG_DIR/seed_c.log" -- --seed=1
run_world "$LOG_DIR/rand_a.log"
run_world "$LOG_DIR/rand_b.log"

SEED_A="$(checksum_of "$LOG_DIR/seed_a.log")"
SEED_B="$(checksum_of "$LOG_DIR/seed_b.log")"
SEED_C="$(checksum_of "$LOG_DIR/seed_c.log")"
RAND_A="$(checksum_of "$LOG_DIR/rand_a.log")"
RAND_B="$(checksum_of "$LOG_DIR/rand_b.log")"
info "seed 20261030 -> ${SEED_A:0:16}..."
info "seed 1        -> ${SEED_C:0:16}..."
info "no seed (1/2) -> ${RAND_A:0:16}..."
info "no seed (2/2) -> ${RAND_B:0:16}..."

if [ -z "$SEED_A" ] || [ -z "$SEED_B" ]; then
	fail "seeded runs did not report a world checksum"
elif [ "$SEED_A" = "$SEED_B" ]; then
	pass "same seed reproduces the identical world"
else
	fail "same seed produced different worlds"
fi
if [ -n "$SEED_C" ] && [ "$SEED_A" != "$SEED_C" ]; then
	pass "a different seed produces a different world"
else
	fail "changing the seed did not change the world"
fi
if [ -n "$RAND_A" ] && [ -n "$RAND_B" ] && [ "$RAND_A" != "$RAND_B" ]; then
	pass "unseeded runs stay randomized (normal gameplay preserved)"
else
	fail "unseeded runs are identical: normal randomization is not active"
fi

# ------------------------------------------------------- G. hunting system ---
section "G. Hunting system tests"
HUNT_LOG="$LOG_DIR/hunting-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/hunting_tests.tscn >"$HUNT_LOG" 2>&1
HUNT_STATUS=$?
project_errors "$HUNT_LOG" >"$LOG_DIR/hunting.errors"
if [ "$HUNT_STATUS" -eq 0 ]; then
	pass "hunting tests exited 0"
elif [ "$HUNT_STATUS" -eq 124 ]; then
	fail "hunting tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$HUNT_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "hunting tests exited $HUNT_STATUS"
fi
if [ -s "$LOG_DIR/hunting.errors" ]; then
	fail "hunting tests reported project errors"
	show "$LOG_DIR/hunting.errors"
else
	info "no project errors during hunting tests"
fi
HUNT_RESULT="$(grep -a '^RESULT:' "$HUNT_LOG" | tail -n 1)"
if [ -n "$HUNT_RESULT" ]; then
	info "$HUNT_RESULT"
else
	fail "hunting tests did not print a result summary"
	show "$HUNT_LOG" 30
fi
HUNT_CHECKS="$(printf '%s' "$HUNT_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$HUNT_CHECKS" ] && [ "$HUNT_CHECKS" -ge 50 ]; then
	pass "all $HUNT_CHECKS hunting checks reported"
else
	fail "hunting suite is incomplete (${HUNT_CHECKS:-0} checks reported, expected at least 50)"
fi
if printf '%s' "$HUNT_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every hunting check passed"
else
	fail "hunting checks failed: ${HUNT_RESULT:-no summary}"
	grep -a '^  FAIL' "$HUNT_LOG" | sed 's/^/          /' | head -n 12
fi

# -------------------------------------------------- H. camera and visuals ---
section "H. Camera and visual tests"
VISUAL_LOG="$LOG_DIR/visual-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/visual_tests.tscn >"$VISUAL_LOG" 2>&1
VISUAL_STATUS=$?
project_errors "$VISUAL_LOG" >"$LOG_DIR/visual.errors"
if [ "$VISUAL_STATUS" -eq 0 ]; then
	pass "visual tests exited 0"
elif [ "$VISUAL_STATUS" -eq 124 ]; then
	fail "visual tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$VISUAL_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "visual tests exited $VISUAL_STATUS"
fi
if [ -s "$LOG_DIR/visual.errors" ]; then
	fail "visual tests reported project errors"
	show "$LOG_DIR/visual.errors"
else
	info "no project errors during visual tests"
fi
VISUAL_RESULT="$(grep -a '^RESULT:' "$VISUAL_LOG" | tail -n 1)"
if [ -n "$VISUAL_RESULT" ]; then
	info "$VISUAL_RESULT"
else
	fail "visual tests did not print a result summary"
	show "$VISUAL_LOG" 30
fi
VISUAL_CHECKS="$(printf '%s' "$VISUAL_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$VISUAL_CHECKS" ] && [ "$VISUAL_CHECKS" -ge 45 ]; then
	pass "all $VISUAL_CHECKS camera and visual checks reported"
else
	fail "visual suite is incomplete (${VISUAL_CHECKS:-0} checks reported, expected at least 45)"
fi
if printf '%s' "$VISUAL_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every camera and visual check passed"
else
	fail "visual checks failed: ${VISUAL_RESULT:-no summary}"
	grep -a '^  FAIL' "$VISUAL_LOG" | sed 's/^/          /' | head -n 12
fi

# ------------------------------------------------------- I. Wildlife AI tests ---
section "I. Wildlife AI tests"
WILDLIFE_LOG="$LOG_DIR/wildlife-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/wildlife_tests.tscn >"$WILDLIFE_LOG" 2>&1
WILDLIFE_STATUS=$?
project_errors "$WILDLIFE_LOG" >"$LOG_DIR/wildlife.errors"
if [ "$WILDLIFE_STATUS" -eq 0 ]; then
	pass "wildlife tests exited 0"
elif [ "$WILDLIFE_STATUS" -eq 124 ]; then
	fail "wildlife tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$WILDLIFE_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "wildlife tests exited $WILDLIFE_STATUS"
fi
if [ -s "$LOG_DIR/wildlife.errors" ]; then
	fail "wildlife tests reported project errors"
	show "$LOG_DIR/wildlife.errors"
else
	info "no project errors during wildlife tests"
fi
WILDLIFE_RESULT="$(grep -a '^RESULT:' "$WILDLIFE_LOG" | tail -n 1)"
if [ -n "$WILDLIFE_RESULT" ]; then
	info "$WILDLIFE_RESULT"
else
	fail "wildlife tests did not print a result summary"
	show "$WILDLIFE_LOG" 30
fi
WILDLIFE_CHECKS="$(printf '%s' "$WILDLIFE_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$WILDLIFE_CHECKS" ] && [ "$WILDLIFE_CHECKS" -ge 90 ]; then
	pass "all $WILDLIFE_CHECKS wildlife AI checks reported"
else
	fail "wildlife suite is incomplete (${WILDLIFE_CHECKS:-0} checks reported, expected at least 90)"
fi
if printf '%s' "$WILDLIFE_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every wildlife AI check passed"
else
	fail "wildlife checks failed: ${WILDLIFE_RESULT:-no summary}"
	grep -a '^  FAIL' "$WILDLIFE_LOG" | sed 's/^/          /' | head -n 12
fi

# --------------------------------------------------------- J. Living world ---
section "J. Living world tests"
WORLD_LOG="$LOG_DIR/world-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/world_tests.tscn >"$WORLD_LOG" 2>&1
WORLD_STATUS=$?
project_errors "$WORLD_LOG" >"$LOG_DIR/world.errors"
if [ "$WORLD_STATUS" -eq 0 ]; then
	pass "living world tests exited 0"
elif [ "$WORLD_STATUS" -eq 124 ]; then
	fail "living world tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$WORLD_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "living world tests exited $WORLD_STATUS"
fi
if [ -s "$LOG_DIR/world.errors" ]; then
	fail "living world tests reported project errors"
	show "$LOG_DIR/world.errors"
else
	info "no project errors during living world tests"
fi
WORLD_RESULT="$(grep -a '^RESULT:' "$WORLD_LOG" | tail -n 1)"
if [ -n "$WORLD_RESULT" ]; then
	info "$WORLD_RESULT"
else
	fail "living world tests did not print a result summary"
	show "$WORLD_LOG" 30
fi
WORLD_CHECKS="$(printf '%s' "$WORLD_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$WORLD_CHECKS" ] && [ "$WORLD_CHECKS" -ge 85 ]; then
	pass "all $WORLD_CHECKS living world checks reported"
else
	fail "living world suite is incomplete (${WORLD_CHECKS:-0} checks reported, expected at least 85)"
fi
if printf '%s' "$WORLD_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every living world check passed"
else
	fail "living world checks failed: ${WORLD_RESULT:-no summary}"
	grep -a '^  FAIL' "$WORLD_LOG" | sed 's/^/          /' | head -n 12
fi

# ------------------------------------------------------------- K. Audio ------
section "K. Audio"
AUDIO_LOG="$LOG_DIR/audio-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/audio_tests.tscn >"$AUDIO_LOG" 2>&1
AUDIO_STATUS=$?
project_errors "$AUDIO_LOG" >"$LOG_DIR/audio.errors"
if [ "$AUDIO_STATUS" -eq 0 ]; then
	pass "audio tests exited 0"
elif [ "$AUDIO_STATUS" -eq 124 ]; then
	fail "audio tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$AUDIO_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "audio tests exited $AUDIO_STATUS"
fi
if [ -s "$LOG_DIR/audio.errors" ]; then
	fail "audio tests reported project errors"
	show "$LOG_DIR/audio.errors"
else
	info "no project errors during audio tests"
fi
AUDIO_RESULT="$(grep -a '^RESULT:' "$AUDIO_LOG" | tail -n 1)"
if [ -n "$AUDIO_RESULT" ]; then
	info "$AUDIO_RESULT"
else
	fail "audio tests did not print a result summary"
	show "$AUDIO_LOG" 30
fi
AUDIO_CHECKS="$(printf '%s' "$AUDIO_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$AUDIO_CHECKS" ] && [ "$AUDIO_CHECKS" -ge 80 ]; then
	pass "all $AUDIO_CHECKS audio checks reported"
else
	fail "audio suite is incomplete (${AUDIO_CHECKS:-0} checks reported, expected at least 80)"
fi
if printf '%s' "$AUDIO_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every audio check passed"
else
	fail "audio checks failed: ${AUDIO_RESULT:-no summary}"
	grep -a '^  FAIL' "$AUDIO_LOG" | sed 's/^/          /' | head -n 12
fi

# The game must not reference a sound that is not in the repository.
MISSING_SOUNDS=0
for sound in $(grep -aoE 'res://assets/audio/[a-z0-9_]+\.wav' "$ROOT/scripts/audio/audio_director.gd" | sort -u); do
	if [ ! -e "$ROOT/${sound#res://}" ]; then
		fail "the game plays $sound but the file does not exist"
		MISSING_SOUNDS=$((MISSING_SOUNDS + 1))
	fi
done
if [ "$MISSING_SOUNDS" -eq 0 ]; then
	pass "every referenced sound file exists"
fi
if grep -aq '^buses/default_bus_layout=' "$ROOT/project.godot" && [ -e "$ROOT/audio/default_bus_layout.tres" ]; then
	pass "the audio bus layout is registered and present"
else
	fail "the audio bus layout is missing or unregistered"
fi
if grep -aq 'generate_audio.py' "$ROOT/assets/audio/LICENSE.txt" 2>/dev/null; then
	pass "the audio provenance note ships with the project"
else
	fail "the audio provenance note is missing"
fi

# ---------------------------------------------------- L. Mobile interface ---
section "L. Mobile interface and localization"
UI_LOG="$LOG_DIR/ui-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/ui_tests.tscn >"$UI_LOG" 2>&1
UI_STATUS=$?
project_errors "$UI_LOG" >"$LOG_DIR/ui.errors"
if [ "$UI_STATUS" -eq 0 ]; then
	pass "UI tests exited 0"
elif [ "$UI_STATUS" -eq 124 ]; then
	fail "UI tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  '"$UI_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "UI tests exited $UI_STATUS"
fi
if [ -s "$LOG_DIR/ui.errors" ]; then
	fail "UI tests reported project errors"
	show "$LOG_DIR/ui.errors"
else
	info "no project errors during UI tests"
fi
UI_RESULT="$(grep -a '^RESULT:' "$UI_LOG" | tail -n 1)"
if [ -n "$UI_RESULT" ]; then
	info "$UI_RESULT"
else
	fail "UI tests did not print a result summary"
	show "$UI_LOG" 30
fi
UI_CHECKS="$(printf '%s' "$UI_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$UI_CHECKS" ] && [ "$UI_CHECKS" -ge 150 ]; then
	pass "all $UI_CHECKS interface checks reported"
else
	fail "interface suite is incomplete (${UI_CHECKS:-0} checks reported, expected at least 150)"
fi
if printf '%s' "$UI_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every interface check passed"
else
	fail "interface checks failed: ${UI_RESULT:-no summary}"
	grep -a '^  FAIL' "$UI_LOG" | sed 's/^/          /' | head -n 12
fi

# The two languages must stay in step: every row has both columns filled.
CSV_FILE="$ROOT/localization/ui_strings.csv"
if [ -e "$CSV_FILE" ]; then
	pass "the translation table is in the repository"
else
	fail "localization/ui_strings.csv is missing"
fi
CSV_ROWS="$(tail -n +2 "$CSV_FILE" | grep -c ',')"
if [ "$CSV_ROWS" -ge 75 ]; then
	pass "the table covers the interface ($CSV_ROWS rows)"
else
	fail "the translation table is too small ($CSV_ROWS rows)"
fi
EMPTY_ROWS="$(tail -n +2 "$CSV_FILE" | awk -F',' 'NF < 3 || $2 == "" || $3 == ""' | wc -l | tr -d ' ')"
if [ "$EMPTY_ROWS" -eq 0 ]; then
	pass "every row is translated into Arabic and English"
else
	fail "$EMPTY_ROWS translation rows are incomplete"
fi

# No visible string may be hardcoded in a UI script: they are all keyed.
# A format string of placeholders and punctuation is not a sentence; a literal with
# Latin letters in it would be an untranslated string.
LITERALS="$(grep -rnE '(text|placeholder_text) = "' "$ROOT/scripts/ui" "$ROOT/scripts/settings" 2>/dev/null | grep -v 'ui_tests' | grep -v '= "%' | wc -l | tr -d ' ')"
if [ "$LITERALS" -eq 0 ]; then
	pass "no hardcoded visible strings in the interface scripts"
else
	fail "$LITERALS hardcoded interface strings found"
	grep -rnE '(text|placeholder_text) = "' "$ROOT/scripts/ui" "$ROOT/scripts/settings" 2>/dev/null | grep -v '= "%' | head -n 6
fi

# Every key the interface asks for must exist in the CSV.
MISSING_KEYS=0
for key in $(grep -rhoE '"(app|menu|pause|settings|hud|status|toast|confirm|regions|region)\.[a-z0-9_.]+"' "$ROOT/scripts" | tr -d '"' | grep -v '\.$' | sort -u); do
	if ! grep -aq "^${key}," "$CSV_FILE"; then
		fail "the interface asks for the missing key ${key}"
		MISSING_KEYS=$((MISSING_KEYS + 1))
	fi
done
if [ "$MISSING_KEYS" -eq 0 ]; then
	pass "every translation key used by the game exists"
fi

# Arabic needs a font with Arabic glyphs, plus its licence.
for font in Amiri-Bold.ttf IBMPlexSansArabic-Regular.ttf IBMPlexSansArabic-SemiBold.ttf OFL-Amiri.txt OFL-IBMPlexSansArabic.txt; do
	if [ -s "$ROOT/assets/fonts/$font" ]; then
		pass "font asset present: $font"
	else
		fail "font asset missing: $font"
	fi
done

# ------------------------------------------------------- M. World regions ---
section "M. World regions"
REGION_LOG="$LOG_DIR/region-tests.log"
godot_run --headless --path "$ROOT" res://scenes/tests/region_tests.tscn >"$REGION_LOG" 2>&1
REGION_STATUS=$?
project_errors "$REGION_LOG" >"$LOG_DIR/region.errors"
if [ "$REGION_STATUS" -eq 0 ]; then
	pass "world region tests exited 0"
elif [ "$REGION_STATUS" -eq 124 ]; then
	fail "world region tests timed out after ${GODOT_TIMEOUT}s (the suite never exited)"
	grep -a '^  ' "$REGION_LOG" | sed 's/^/          /' | tail -n 8
else
	fail "world region tests exited $REGION_STATUS"
fi
if [ -s "$LOG_DIR/region.errors" ]; then
	fail "world region tests reported project errors"
	show "$LOG_DIR/region.errors"
else
	info "no project errors during world region tests"
fi
REGION_RESULT="$(grep -a '^RESULT:' "$REGION_LOG" | tail -n 1)"
if [ -n "$REGION_RESULT" ]; then
	info "$REGION_RESULT"
else
	fail "world region tests did not print a result summary"
	show "$REGION_LOG" 30
fi
REGION_CHECKS="$(printf '%s' "$REGION_RESULT" | sed -n 's/^RESULT: \([0-9][0-9]*\) checks,.*/\1/p')"
if [ -n "$REGION_CHECKS" ] && [ "$REGION_CHECKS" -ge 300 ]; then
	pass "all $REGION_CHECKS region checks reported"
else
	fail "region suite is incomplete (${REGION_CHECKS:-0} checks reported, expected at least 300)"
fi
if printf '%s' "$REGION_RESULT" | grep -aqE '^RESULT: [0-9]+ checks, 0 failed$'; then
	pass "every region check passed"
else
	fail "region checks failed: ${REGION_RESULT:-no summary}"
	grep -a '^  FAIL' "$REGION_LOG" | sed 's/^/          /' | head -n 12
fi

# The ten regions are pure data, so the repository itself can be checked: the
# table must define exactly ten entries and every one needs a landmark and exits.
REGION_COUNT="$(grep -c '^static func _[a-z_]*() -> Dictionary:' "$ROOT/scripts/world/region_definition.gd")"
if [ "$REGION_COUNT" -eq 10 ]; then
	pass "the region table defines ten regions"
else
	fail "the region table defines $REGION_COUNT regions, expected 10"
fi
for f in scripts/world/region_definition.gd scripts/world/region_builder.gd scripts/world/region_manager.gd scripts/ui/region_menu.gd scripts/tests/region_tests.gd; do
	if [ -s "$ROOT/$f" ]; then
		pass "region source present: $f"
	else
		fail "region source missing: $f"
	fi
done

# ----------------------------------------------------------------- summary ---
printf '\n== Summary ==\n'
printf '  %d checks, %d failed\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
	printf '  \033[31mVERIFICATION FAILED\033[0m\n'
	exit 1
fi
printf '  \033[32mALL CHECKS PASSED\033[0m\n'
exit 0
