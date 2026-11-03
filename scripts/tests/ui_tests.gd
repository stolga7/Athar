extends Node
## Headless tests for the Phase 3.5 interface: localization, HUD layout, the
## touch stick, every menu, settings persistence and the scene wiring.
##
## Run with:
##   godot --headless --path . res://scenes/tests/ui_tests.tscn
##
## Nothing here needs a display: the HUD lays itself out from a given viewport
## size, controls are measured as rectangles, touches are delivered as input
## events, and persistence round-trips a temporary file. What it therefore cannot
## prove is that the result looks good or that a real thumb can reach it — that
## part needs a device, and TESTING.md says so.

const Localization := preload("res://scripts/ui/localization.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const GameSettings := preload("res://scripts/settings/game_settings.gd")
const GraphicsProfile := preload("res://scripts/settings/graphics_profile.gd")

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const CONFIRM_SCENE := preload("res://scenes/ui/confirm_prompt.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const TEST_SETTINGS := "user://athar_test_ui.cfg"
const PLAYER_SETTINGS := "user://athar_settings.cfg"
const CSV_PATH := "res://localization/ui_strings.csv"
const FONT_DIR := "res://assets/fonts/"
const WATCHDOG_SECONDS := 120.0

## A phone in landscape, a tall 20:9 phone, a small phone, a 4:3 tablet and a
## tiny window: the four margins and touch sizes have to work on all of them.
const VIEWPORTS := [
	Vector2(1280, 720),
	Vector2(2400, 1080),
	Vector2(800, 360),
	Vector2(2048, 1536),
	Vector2(1920, 1080),
]

var _checks := 0
var _failures := 0
var _settings: RefCounted
var _watchdog: Timer
## The player's own settings file is moved aside during the run and put back after,
## so running the suite never costs a developer their language or volume choices.
var _saved_player_file := ""
var _player_file_existed := false


func _ready() -> void:
	print("ATHAR UI tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_watchdog)
	_watchdog.start()

	# Start from a clean slate: the scene reads the real player settings file at
	# boot, and a leftover language from another run would make these checks flaky.
	_player_file_existed = FileAccess.file_exists(PLAYER_SETTINGS)
	if _player_file_existed:
		_saved_player_file = FileAccess.get_file_as_string(PLAYER_SETTINGS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))

	_test_assets()
	_test_table()
	_test_runtime_translation()
	_test_ui_kit()
	_test_fonts()
	_localization_ui()
	_test_hud_scene()
	_test_hud_layout()
	_test_hud_language()
	_test_joystick()
	_test_settings_roundtrip()
	await _test_scene()
	_finish()


func _finish() -> void:
	_watchdog.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_SETTINGS))
	if _player_file_existed and not _saved_player_file.is_empty():
		var restore := FileAccess.open(PLAYER_SETTINGS, FileAccess.WRITE)
		if restore != null:
			restore.store_string(_saved_player_file)
			restore.close()
	_stop_all_audio(get_tree().root)
	OS.delay_msec(250)
	await get_tree().process_frame
	print("")
	if _failures > 0:
		print("RESULT: %d checks, %d failed" % [_checks, _failures])
		get_tree().quit(1)
	else:
		print("RESULT: %d checks, 0 failed" % _checks)
		get_tree().quit(0)


func _stop_all_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_stop_all_audio(child)


func _on_watchdog_timeout() -> void:
	print("RESULT: %d checks, %d failed (watchdog)" % [_checks, _failures + 1])
	get_tree().quit(1)


func _check(passed: bool, label: String, detail := "") -> void:
	_checks += 1
	if passed:
		print("  PASS  %s%s" % [label, "  (%s)" % detail if not detail.is_empty() else ""])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "  (%s)" % detail if not detail.is_empty() else ""])


func _spawn(scene: PackedScene) -> Control:
	var node: Control = scene.instantiate()
	add_child(node)
	return node


# ------------------------------------------------------------------ assets ---
func _test_assets() -> void:
	print("- assets")
	_check(FileAccess.file_exists(CSV_PATH), "the translation table exists")
	for file in ["Amiri-Bold.ttf", "IBMPlexSansArabic-Regular.ttf", "IBMPlexSansArabic-SemiBold.ttf"]:
		_check(FileAccess.file_exists(FONT_DIR + file), "font is packaged: %s" % file)
	_check(FileAccess.file_exists(FONT_DIR + "OFL-Amiri.txt"), "the Amiri licence ships with the font")
	_check(FileAccess.file_exists(FONT_DIR + "OFL-IBMPlexSansArabic.txt"), "the Plex licence ships with the font")
	var licence := FileAccess.get_file_as_string(FONT_DIR + "OFL-IBMPlexSansArabic.txt")
	_check(licence.contains("SIL OPEN FONT LICENSE"), "the licence text is the real OFL", licence.substr(0, 24))


# ------------------------------------------------------------------- table ---
func _test_table() -> void:
	print("- translation table")
	_check(Localization.ensure_installed(), "the CSV parses into translations")
	var keys := Localization.keys()
	_check(keys.size() >= 75, "the table covers the whole interface", "%d keys" % keys.size())
	var arabic := Localization.table("ar")
	var english := Localization.table("en")
	_check(arabic.size() == keys.size() and english.size() == keys.size(),
		"both languages have every key", "%d / %d" % [arabic.size(), english.size()])
	var missing := []
	var identical := 0
	var with_arabic_glyphs := 0
	var seen := {}
	var duplicates := []
	for key in keys:
		if seen.has(key):
			duplicates.append(key)
		seen[key] = true
		if String(arabic.get(key, "")).is_empty() or String(english.get(key, "")).is_empty():
			missing.append(key)
		if String(arabic.get(key, "")) == String(english.get(key, "")):
			identical += 1
		if _has_arabic(String(arabic.get(key, ""))):
			with_arabic_glyphs += 1
	_check(missing.is_empty(), "no key is blank in either language", ", ".join(missing))
	_check(duplicates.is_empty(), "no duplicated keys", ", ".join(duplicates))
	_check(identical <= 4, "the Arabic column is translated, not copied", "%d identical" % identical)
	_check(with_arabic_glyphs >= keys.size() - 12, "the Arabic column is real Arabic",
		"%d of %d rows use Arabic letters" % [with_arabic_glyphs, keys.size()])
	for required in ["app.title", "menu.begin", "menu.settings", "pause.title", "settings.title",
			"hud.vital.stamina", "hud.action.hunt", "status.captured", "confirm.yes"]:
		_check(arabic.has(required) and english.has(required), "key present: %s" % required)


func _has_arabic(text: String) -> bool:
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code >= 0x0600 and code <= 0x06FF:
			return true
	return false


# --------------------------------------------------------------- runtime -----
func _test_runtime_translation() -> void:
	print("- runtime translation")
	Localization.set_language("ar")
	_check(Localization.current_language() == "ar", "Arabic is selectable")
	var arabic_title := Localization.text("app.title")
	_check(arabic_title == "أَثَر", "the title translates", arabic_title)
	Localization.set_language("en")
	_check(Localization.current_language() == "en", "English is selectable")
	var english_title := Localization.text("app.title")
	_check(english_title == "ATHAR", "the title changes with the language", english_title)
	_check(arabic_title != english_title, "the two languages really differ")
	_check(Localization.text("missing.key") == "missing.key", "an unknown key falls back to itself")
	_check(Localization.is_rtl("ar") and not Localization.is_rtl("en"), "only Arabic is right to left")
	_check(Localization.layout_direction("ar") == Control.LAYOUT_DIRECTION_RTL, "RTL layout direction")
	_check(Localization.layout_direction("en") == Control.LAYOUT_DIRECTION_LTR, "LTR layout direction")
	_check(Localization.text_alignment("ar") == HORIZONTAL_ALIGNMENT_RIGHT, "Arabic text aligns right")
	_check(Localization.text_alignment("en") == HORIZONTAL_ALIGNMENT_LEFT, "English text aligns left")
	_check(Localization.set_language("fr") == "ar", "an unknown language falls back to Arabic")
	_check(Localization.text("hud.action.hunt") != "hud.action.hunt", "HUD keys resolve")
	Localization.set_language("ar")


# ------------------------------------------------------------------ kit -----
func _test_ui_kit() -> void:
	print("- shared look")
	var theme := UiKit.build_theme()
	_check(theme != null, "the theme builds")
	_check(theme == UiKit.build_theme(), "the theme is shared, not rebuilt per screen")
	_check(theme.default_font != null and theme.default_font != ThemeDB.fallback_font,
		"the theme uses the packaged Arabic font")
	_check(UiKit.MIN_TOUCH >= 56.0, "the minimum touch target is phone sized", "%.0f px" % UiKit.MIN_TOUCH)
	_check(UiKit.SIZE_CAPTION < UiKit.SIZE_BODY and UiKit.SIZE_BODY < UiKit.SIZE_SUBHEAD
		and UiKit.SIZE_SUBHEAD < UiKit.SIZE_HEADLINE and UiKit.SIZE_HEADLINE < UiKit.SIZE_DISPLAY,
		"the type scale is ordered")
	_check(UiKit.PURPLE != UiKit.GOLD and UiKit.CYAN != UiKit.GOLD, "the palette has distinct accents")
	var button := UiKit.button("menu.begin")
	_check(button.text == Localization.text("menu.begin"), "a tagged button starts translated")
	_check(button.custom_minimum_size.y >= UiKit.MIN_TOUCH, "every button gets a tall hit area")
	var panel := UiKit.panel_style()
	_check(panel.corner_radius_top_left > 0 and panel.content_margin_left > 0,
		"panels have rounded corners and padding")
	var before := button.text
	Localization.set_language("en")
	UiKit.retranslate(button)
	_check(button.text == Localization.text("menu.begin") and button.text != before,
		"retranslate re-fills a control in the new language", button.text)
	Localization.set_language("ar")
	button.queue_free()


func _test_fonts() -> void:
	print("- fonts")
	var body := UiKit.body_font()
	var display := UiKit.display_font()
	_check(body.has_char(0x0639), "the body font carries an Arabic letter (ain)")
	_check(body.has_char(0x0623), "the body font carries an Arabic hamza")
	_check(display.has_char(0x0623), "the display font carries Arabic")
	_check(body.has_char(0x0041), "the body font carries Latin")
	_check(body != display, "body and display faces differ")


func _localization_ui() -> void:
	print("- every screen is translated")
	var hud := _spawn(HUD_SCENE)
	hud.setup(_new_settings())
	var main_menu := _spawn(MAIN_MENU_SCENE)
	var pause_menu := _spawn(PAUSE_MENU_SCENE)
	var settings_menu := _spawn(SETTINGS_MENU_SCENE)
	settings_menu.setup(_new_settings())
	var confirm := _spawn(CONFIRM_SCENE)
	confirm.ask("confirm.return.title", "confirm.return.body")

	for screen in [hud, main_menu, pause_menu, settings_menu, confirm]:
		_check(UiKit.untranslated(screen).is_empty(), "no hardcoded text in %s" % screen.name,
			", ".join(UiKit.untranslated(screen)))

	Localization.set_language("en")
	for screen in [hud, main_menu, pause_menu, settings_menu, confirm]:
		screen.retranslate()
		_check(UiKit.untranslated(screen).is_empty(), "still no hardcoded text after switching to English in %s" % screen.name)
	_check(main_menu.begin_button.text == "BEGIN HUNT", "the main menu is in English", main_menu.begin_button.text)
	_check(pause_menu.resume_button.text == "RESUME", "the pause menu is in English", pause_menu.resume_button.text)
	_check(settings_menu.language_buttons["en"].text == "English", "the settings screen is in English")
	_check(hud.status_label.text == Localization.text("hud.initial_status"), "the HUD status is in English",
		hud.status_label.text)
	Localization.set_language("ar")
	for screen in [hud, main_menu, pause_menu, settings_menu, confirm]:
		screen.retranslate()
	_check(main_menu.begin_button.text == "ابدأ صيدًا", "the main menu is back in Arabic", main_menu.begin_button.text)
	_check(hud.layout_direction == Control.LAYOUT_DIRECTION_RTL, "the HUD mirrors for Arabic")
	_check(settings_menu.layout_direction == Control.LAYOUT_DIRECTION_RTL, "the settings screen mirrors for Arabic")

	for screen in [hud, main_menu, pause_menu, settings_menu, confirm]:
		screen.queue_free()


# -------------------------------------------------------------------- hud ----
func _test_hud_scene() -> void:
	print("- HUD structure")
	var hud := _spawn(HUD_SCENE)
	hud.setup(_new_settings())
	_check(hud.status_label != null, "the HUD has a status line")
	_check(hud.info_label != null, "the HUD has an information line")
	_check(hud.action_button != null and hud.action_button is Button, "the HUD has the action button")
	_check(hud.interact_button != null, "the HUD has a context button")
	_check(hud.pause_button != null, "the HUD has a pause button")
	_check(hud.joystick != null, "the HUD has a movement pad")
	_check(hud.marker != null, "the HUD still hosts the off-screen deer cue")
	_check(hud.stamina_bar != null and hud.condition_bar != null and hud.alert_bar != null,
		"the HUD shows three vitals")
	_check(hud.stamina_bar.title.text == Localization.text("hud.vital.stamina"), "vitals are labelled in Arabic")
	_check(not hud.interact_button.visible, "the context button hides when there is nothing to do")
	hud.set_interact_key("hud.capture")
	_check(hud.interact_button.visible and hud.interact_button.text == Localization.text("hud.capture"),
		"the context button appears with its action")
	hud.set_interact_key("")
	_check(not hud.interact_button.visible, "the context button hides again")
	hud.set_vitals(0.5, 0.25, 0.75)
	_check(is_equal_approx(hud.stamina_bar.value, 0.5) and is_equal_approx(hud.alert_bar.value, 0.75),
		"vitals follow the values handed to them")
	hud.toast("toast.too_far", 24)
	_check(hud.toast_visible(), "a refused action can show a toast")
	_check(hud.toast_label.text.contains("24"), "the toast carries the distance", hud.toast_label.text)
	hud._toast_seconds = 0.01
	hud._process(0.02)
	_check(not hud.toast_visible(), "the toast fades away by itself")
	hud.queue_free()


func _test_hud_layout() -> void:
	print("- HUD layout")
	var hud := _spawn(HUD_SCENE)
	hud.setup(_new_settings())
	for size in VIEWPORTS:
		hud.set_safe_insets(0, 0, 0, 0)
		hud.layout_for(size)
		var tag := "%dx%d" % [int(size.x), int(size.y)]
		var stick: Rect2 = Rect2(hud.joystick.position, hud.joystick.size)
		var action: Rect2 = Rect2(hud.action_button.position, hud.action_button.size)
		var pause: Rect2 = Rect2(hud.pause_button.position, hud.pause_button.size)
		_check(stick.size.x >= UiKit.MIN_TOUCH and action.size.x >= UiKit.MIN_TOUCH and pause.size.x >= UiKit.MIN_TOUCH,
			"touch targets stay large on %s" % tag, "%.0f/%.0f/%.0f" % [stick.size.x, action.size.x, pause.size.x])
		_check(stick.position.x >= 0.0 and stick.position.y >= 0.0
			and stick.end.x <= size.x + 0.5 and stick.end.y <= size.y + 0.5,
			"the movement pad sits inside a %s screen" % tag)
		_check(action.end.x <= size.x + 0.5 and action.end.y <= size.y + 0.5,
			"the action button sits inside a %s screen" % tag)
		_check(pause.end.x <= size.x + 0.5 and pause.position.x >= 0.0,
			"the pause button sits inside a %s screen" % tag)
		_check(not stick.intersects(action), "the stick and the action button cannot be hit together on %s" % tag)
		_check(stick.position.x < size.x * 0.5 and action.position.x > size.x * 0.5,
			"movement stays on the left and action on the right on %s" % tag)
		var panel: Rect2 = Rect2(hud.panel.position, hud.panel.size)
		_check(panel.position.x >= 0.0 and panel.end.x <= size.x + 0.5 and panel.end.y <= size.y * 0.65,
			"the vitals panel stays in its corner on %s" % tag, "%s h=%.0f limit=%.0f" % [panel, panel.size.y, size.y * 0.6])
		_check(Rect2(hud.toast_label.position, hud.toast_label.size).end.y <= action.position.y,
			"the toast never covers the action button on %s" % tag,
			"%s/%s vs %.0f" % [hud.toast_label.position, hud.toast_label.size, action.position.y])

	# A very short screen drops the hint instead of stacking text over the pads.
	hud.layout_for(Vector2(800, 360))
	_check(not hud.hint_label.visible, "the hint hides on a short screen")
	hud.layout_for(Vector2(2400, 1080))
	_check(hud.hint_label.visible, "the hint shows when there is room")

	# Safe-area insets push the controls inwards, as on a notched phone.
	hud.set_safe_insets(0, 0, 0, 0)
	hud.layout_for(Vector2(2400, 1080))
	var no_inset: Vector2 = hud.joystick.position
	hud.apply_safe_area(Rect2i(60, 30, 2340, 1050), Vector2i(2400, 1080), Vector2(2400, 1080))
	hud.layout_for(Vector2(2400, 1080))
	_check(hud.joystick.position.x > no_inset.x + 40.0, "a notch inset moves the pad inwards",
		"%.0f -> %.0f" % [no_inset.x, hud.joystick.position.x])
	_check(hud.panel.position.y > 30.0, "the top inset moves the panel down", "%.0f" % hud.panel.position.y)
	_check(hud.pause_button.position.x < 2400.0 - 100.0, "the pause button respects the right inset")
	hud.set_safe_insets(0, 0, 0, 0)
	hud.queue_free()


func _test_hud_language() -> void:
	print("- HUD language")
	var hud := _spawn(HUD_SCENE)
	hud.setup(_new_settings())
	hud.layout_for(Vector2(2400, 1080))
	Localization.set_language("ar")
	hud.retranslate()
	_check(hud.panel.position.x > 1200.0, "the Arabic panel sits on the right")
	_check(hud.pause_button.position.x < 1200.0, "the Arabic pause button sits on the left")
	_check(hud.action_button.position.x > 1200.0, "the action button stays on the right in Arabic")
	_check(hud.joystick.position.x < 1200.0, "the movement pad stays on the left in Arabic")
	_check(hud.stamina_bar.title.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
		"Arabic vitals labels align right")

	Localization.set_language("en")
	hud.retranslate()
	_check(hud.panel.position.x < 1200.0, "the English panel sits on the left")
	_check(hud.pause_button.position.x > 1200.0, "the English pause button sits on the right")
	_check(hud.stamina_bar.title.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
		"English vitals labels align left")

	hud.set_status_key("status.fleeing")
	Localization.set_language("ar")
	hud.retranslate()
	_check(hud.status_label.text == Localization.text("status.fleeing"),
		"the current status message survives a language change", hud.status_label.text)
	_check(hud.action_key() == "hud.action.hunt", "the action button keeps its meaning")
	hud.set_info("06:12", "hud.phase.dawn", "hud.weather.clear", "hud.deer.grazing")
	Localization.set_language("en")
	hud.retranslate()
	_check(hud.info_label.text.contains("Dawn") and hud.info_label.text.contains("Grazing"),
		"the information line is rebuilt in English", hud.info_label.text)
	Localization.set_language("ar")
	hud.retranslate()
	_check(hud.info_label.text.contains(Localization.text("hud.phase.dawn")),
		"the information line is rebuilt in Arabic")
	hud.queue_free()


# ---------------------------------------------------------------- joystick ---
func _test_joystick() -> void:
	print("- touch stick")
	var hud := _spawn(HUD_SCENE)
	hud.setup(_new_settings())
	var stick: Control = hud.joystick
	stick.setup(180.0)
	var centre := Vector2(90, 90)

	_check(stick.value == Vector2.ZERO, "the stick starts at rest")
	_touch(stick, 0, true, centre + Vector2(2, 1))
	_check(stick.active, "a touch inside the ring grabs the stick")
	_check(stick.value == Vector2.ZERO, "a resting thumb inside the deadzone does not move the hunter")

	_touch(stick, 0, false, centre)
	_check(not stick.active and stick.value == Vector2.ZERO, "lifting the finger releases the stick")

	_touch(stick, 0, true, centre + Vector2(0, -60))
	_check(stick.value.y < -0.5 and absf(stick.value.x) < 0.001, "pushing up asks the hunter to go forward",
		"%.2f" % stick.value.y)
	var forward: Vector2 = stick.value
	_touch(stick, 1, true, centre + Vector2(60, 0))
	_check(stick.value == forward, "a second finger cannot steal the stick")
	_touch(stick, 1, false, centre + Vector2(60, 0))
	_check(stick.active, "the first finger still owns the stick after the second leaves")
	_touch(stick, 0, false, centre + Vector2(300, -300))
	_check(not stick.active and stick.value == Vector2.ZERO, "a release outside the ring still stops the hunter")

	_touch(stick, 0, true, centre + Vector2(60, 60))
	_check(stick.value.length() <= 1.0001, "the stick never exceeds full tilt", "%.3f" % stick.value.length())
	_check(stick.value.x > 0.5 and stick.value.y > 0.5, "a diagonal push reports both axes")
	_touch(stick, 0, false, centre)

	stick.set_sensitivity(2.0)
	_touch(stick, 0, true, centre + Vector2(0, -30))
	_check(stick.intensity() > 0.5, "raising the sensitivity makes the same push stronger",
		"%.2f" % stick.intensity())
	stick.set_sensitivity(1.0)
	_touch(stick, 0, false, centre)

	# The mouse path is what desktop testing and the editor use.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre + Vector2(-40, 0)
	stick._gui_input(press)
	_check(stick.value.x < -0.3, "a mouse drag moves the stick too", "%.2f" % stick.value.x)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = centre
	stick._gui_input(release)
	_check(stick.value == Vector2.ZERO, "releasing the mouse settles the stick")

	stick.release()
	hud.queue_free()


func _touch(stick: Control, index: int, pressed: bool, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	stick._gui_input(event)


# ---------------------------------------------------------------- settings ---
func _new_settings() -> RefCounted:
	var created := GameSettings.new(TEST_SETTINGS)
	return created


func _test_settings_roundtrip() -> void:
	print("- settings persistence")
	var saved := GameSettings.new(TEST_SETTINGS)
	saved.set_language("en")
	saved.set_quality("low")
	saved.set_sensitivity(1.6)
	saved.set_master(0.4)
	saved.set_music(0.3)
	_check(saved.save(), "settings can be written")

	var loaded := GameSettings.new(TEST_SETTINGS)
	_check(loaded.load_settings(), "settings can be read back")
	_check(loaded.language == "en", "the language survives a restart", loaded.language)
	_check(loaded.quality == "low", "the graphics level survives a restart", loaded.quality)
	_check(absf(loaded.sensitivity - 1.6) < 0.001, "the sensitivity survives a restart", "%.2f" % loaded.sensitivity)
	_check(absf(loaded.master - 0.4) < 0.01 and absf(loaded.music - 0.3) < 0.01,
		"the Phase 3.4 volumes are in the same file")
	_check(FileAccess.file_exists(TEST_SETTINGS), "one settings file holds everything")

	_check(loaded.set_sensitivity(9.0) == GameSettings.SENSITIVITY_MAX, "sensitivity is clamped at the top")
	_check(loaded.set_sensitivity(-4.0) == GameSettings.SENSITIVITY_MIN, "sensitivity is clamped at the bottom")
	_check(loaded.set_language("fr") == "ar", "an unknown language resets to Arabic")
	_check(loaded.set_quality("ultra") == "medium", "an unknown graphics level resets to medium")

	var corrupt := ConfigFile.new()
	corrupt.set_value("game", "language", "xx")
	corrupt.set_value("game", "quality", "insane")
	corrupt.set_value("game", "sensitivity", 40.0)
	corrupt.save(TEST_SETTINGS)
	var recovered := GameSettings.new(TEST_SETTINGS)
	recovered.load_settings()
	_check(recovered.language == "ar" and recovered.quality == "medium"
		and recovered.sensitivity == GameSettings.SENSITIVITY_MAX,
		"a corrupted file still produces usable settings", "%s/%s/%.1f" % [recovered.language, recovered.quality, recovered.sensitivity])

	recovered.reset()
	_check(recovered.language == "ar" and recovered.quality == "medium"
		and is_equal_approx(recovered.sensitivity, 1.0), "reset restores the defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var missing := GameSettings.new(TEST_SETTINGS)
	_check(not missing.load_settings(), "a missing file is reported, not fatal")
	_check(missing.language == "ar" and missing.quality == "medium", "a missing file keeps the defaults")

	_check(GraphicsProfile.PRESETS.size() == 3, "there are three graphics levels")
	_check(GraphicsProfile.preset("low")["shadows"] == false and GraphicsProfile.preset("high")["shadows"] == true,
		"only the low level turns shadows off")
	_check(float(GraphicsProfile.preset("low")["scale"]) < float(GraphicsProfile.preset("high")["scale"]),
		"the low level renders fewer pixels")


# ------------------------------------------------------------------- scene ---
func _test_scene() -> void:
	print("- the live scene")
	var _main: Node3D = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_main.hud != null and _main.hud_root == _main.hud, "the scene builds the new HUD")
	_check(_main.hunt_button == _main.hud.action_button, "the old hunt_button still points at the action button")
	_check(_main.deer_marker == _main.hud.marker, "the scene still exposes the deer cue")
	_check(_main.audio_panel == _main.settings_menu.audio_section, "the audio panel now lives in settings")
	_check(_main.main_menu != null and _main.pause_menu != null and _main.settings_menu != null,
		"the scene builds every menu")
	_check(_main.game_state == "playing", "a headless run starts in the hunt", _main.game_state)
	_check(not _main.main_menu.visible and not _main.pause_menu.visible, "no menu covers the hunt at boot")
	_check(_main.status_label.text == Localization.text("hud.initial_status"),
		"the opening message is the localized one", _main.status_label.text)
	_check(_main.hud.layout_direction == Control.LAYOUT_DIRECTION_RTL, "the scene boots in Arabic")

	# Pause freezes the simulation without pausing the tree, so the menus and the
	# audio director keep working while the hunt is suspended.
	_main.open_pause()
	await get_tree().process_frame
	_check(_main.pause_menu.visible, "the pause button opens the pause menu")
	_check(not _main.is_physics_processing(), "pausing stops the hunt")
	_check(_main.game_state == "menu", "the scene knows it is in a menu", _main.game_state)
	_check(not _main.hud.joystick.active, "the movement pad is released when the menu opens")
	_main.resume_game()
	_check(not _main.pause_menu.visible and _main.is_physics_processing(), "resume restores the hunt")

	# Settings from the pause menu, and back again.
	_main.open_pause()
	_main.open_settings(false)
	_check(_main.settings_menu.visible and not _main.pause_menu.visible,
		"settings open over the paused hunt")
	_check(_main.settings_menu.audio_section.panel.visible == false, "the sound section starts folded")
	_main.settings_menu.audio_section.toggle()
	_check(_main.settings_menu.audio_section.panel.visible, "the sound section folds out on demand")
	_main.settings_menu.audio_section.toggle()

	_main.settings_menu._on_language("en")
	await get_tree().process_frame
	_check(_main.main_menu.begin_button.text == "BEGIN HUNT", "switching to English updates the menus")
	_check(_main.hud.status_label.text == Localization.text(_main.hud.current_status_key()),
		"switching language re-fills the HUD", _main.hud.status_label.text)
	_check(_main.hud.layout_direction == Control.LAYOUT_DIRECTION_LTR, "English lays the HUD out left to right")
	var persisted := GameSettings.new(PLAYER_SETTINGS)
	persisted.load_settings()
	_check(persisted.language == "en", "the language choice is saved immediately", persisted.language)

	_main.settings_menu._on_language("ar")
	await get_tree().process_frame
	_check(_main.hud.layout_direction == Control.LAYOUT_DIRECTION_RTL, "switching back restores Arabic")

	var sun := _main.get_node_or_null("Sun") as DirectionalLight3D
	_main.settings_menu._on_quality("low")
	_check(is_equal_approx(_main.get_viewport().scaling_3d_scale, 0.72),
		"the low graphics level renders the 3D view at 72%", "%.2f" % _main.get_viewport().scaling_3d_scale)
	_check(sun != null and not sun.shadow_enabled, "the low graphics level turns the sun's shadows off")
	_main.settings_menu._on_quality("high")
	_check(is_equal_approx(_main.get_viewport().scaling_3d_scale, 1.0) and (sun == null or sun.shadow_enabled),
		"the high graphics level renders at full resolution")

	_main.settings_menu.sensitivity_slider.value = 1.8
	await get_tree().process_frame
	_check(absf(_main.hud.joystick.sensitivity - 1.8) < 0.06, "the stick follows the sensitivity slider",
		"%.2f" % _main.hud.joystick.sensitivity)
	_main.settings_menu.reset_button.pressed.emit()
	_check(absf(_main.hud.joystick.sensitivity - 1.0) < 0.001, "reset puts the stick back to normal speed",
		"%.2f" % _main.hud.joystick.sensitivity)

	_main.settings_menu.close()
	_check(_main.pause_menu.visible, "closing settings returns to the pause menu")
	_main.resume_game()
	_check(_main.game_state == "playing", "the hunt is playable again")

	# Restart only happens after a confirmation.
	_main.open_pause()
	_main.request_restart()
	_check(_main.confirm_prompt.visible, "restart asks before it throws the hunt away")
	_main.confirm_prompt.confirm_button.pressed.emit()
	await get_tree().physics_frame
	_check(not _main.confirm_prompt.visible and not _main.pause_menu.visible, "confirming closes the prompt")
	_check(_main.is_physics_processing() and _main.game_state == "playing", "confirming restart resumes the hunt")
	_check(_main.deer_state == "GRAZING", "the restarted hunt begins with a calm deer", _main.deer_state)
	_check(is_equal_approx(_main.stamina, 100.0), "restarting restores the hunter's breath")

	# Returning to the title screen is guarded the same way.
	_main.open_pause()
	_main.request_return_to_menu()
	_check(_main.confirm_prompt.visible, "returning to the menu asks first")
	_main.confirm_prompt.confirm_button.pressed.emit()
	await get_tree().process_frame
	_check(_main.main_menu.visible, "confirming returns to the title screen")
	_check(_main.game_state == "menu" and not _main.is_physics_processing(), "the title screen suspends the hunt")
	_main.start_game()
	await get_tree().physics_frame
	_check(not _main.main_menu.visible and _main.is_physics_processing(), "BEGIN HUNT starts a fresh hunt")
	_check(_main.deer.visible and _main.deer_state == "GRAZING", "the fresh hunt has a deer to track")

	# Vitals and the information line follow the world.
	_main.stamina = 42.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(_main.hud.stamina_bar.value - 0.42) < 0.02, "the stamina bar follows the hunter",
		"%.2f" % _main.hud.stamina_bar.value)
	_check(_main.hud.info_label.text.contains(Localization.text("hud.phase." + String(_main.living_world.day.phase()))),
		"the information line names the current day phase", _main.hud.info_label.text)

	# Walking up to the deer hands the capture to the context button.
	_main.hunter.global_position = _main.deer.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_main.captured, "walking into the deer still captures it")
	_check(_main.hud.action_key() == "hud.action.new_hunt", "the action button becomes NEW HUNT")
	_check(_main.hud.toast_visible(), "the capture is announced with a toast")
	_main.hud.set_interact_key("")
	_main._reset_hunt_state()
	_check(_main.deer.visible and not _main.captured, "a new hunt brings the deer back")

	_stop_all_audio(_main)
	_main.queue_free()
	await get_tree().process_frame
