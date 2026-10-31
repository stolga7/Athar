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
for required in project.godot scenes/main.tscn scenes/tests/hunting_tests.tscn scripts/main.gd scripts/animals/deer_ai.gd scripts/gameplay/hunt_session.gd scripts/tests/hunting_tests.gd scripts/visuals/deer_rig.gd scripts/visuals/hunter_rig.gd scripts/visuals/rig_utils.gd icon.svg icon.svg.import .gitignore README.md TESTING.md assets; do
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

# ----------------------------------------------------------------- summary ---
printf '\n== Summary ==\n'
printf '  %d checks, %d failed\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
	printf '  \033[31mVERIFICATION FAILED\033[0m\n'
	exit 1
fi
printf '  \033[32mALL CHECKS PASSED\033[0m\n'
exit 0
