extends RefCounted
## Arabic/English text for every visible string in ATHAR.
##
## One CSV is the only place UI text lives: `localization/ui_strings.csv` with a
## `keys,ar,en` header. This loader parses it at runtime into two [Translation]
## objects and registers them with the [TranslationServer], so nothing is
## compiled into the scripts and a translator only has to edit the CSV. Parsing
## it here (instead of relying on Godot's CSV import step) keeps the text working
## in a bare headless checkout and lets the tests read the table directly.
##
## Arabic is the default language and the one the game starts in when no saved
## settings say otherwise.

const CSV_PATH := "res://localization/ui_strings.csv"

const ARABIC := "ar"
const ENGLISH := "en"
const LANGUAGES := [ARABIC, ENGLISH]
const DEFAULT_LANGUAGE := ARABIC
## Languages written right to left. Only Arabic today; the list is the one place
## to extend if another RTL language is added.
const RTL_LANGUAGES := [ARABIC]

static var _installed := false
static var _keys := PackedStringArray()
static var _tables := {}


## Parses the CSV and registers both languages. Idempotent: later calls are free.
## Returns false when the CSV is missing or unreadable, so the caller can report
## it instead of shipping an untranslated UI.
static func ensure_installed() -> bool:
	if _installed:
		return true
	var parsed := _parse(CSV_PATH)
	if parsed.is_empty():
		return false
	_tables = parsed["tables"]
	_keys = parsed["keys"]
	for code in _tables.keys():
		var translation := Translation.new()
		translation.locale = code
		var table: Dictionary = _tables[code]
		for key in table.keys():
			translation.add_message(key, table[key])
		TranslationServer.add_translation(translation)
	_installed = true
	return true


static func _parse(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var tables := {}
	var keys := PackedStringArray()
	var header := file.get_csv_line()
	if header.size() < 2 or header[0].strip_edges() != "keys":
		return {}
	for index in range(1, header.size()):
		tables[header[index].strip_edges()] = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2:
			continue
		var key := row[0].strip_edges()
		if key.is_empty() or key.begins_with("#"):
			continue
		keys.append(key)
		for column in range(1, mini(row.size(), header.size())):
			var code: String = header[column].strip_edges()
			var table: Dictionary = tables[code]
			table[key] = row[column].strip_edges()
	file.close()
	if keys.is_empty():
		return {}
	return {"tables": tables, "keys": keys}


## Switches the whole game to `code`. Unknown codes fall back to the default so a
## corrupted settings file can never leave the player with an untranslated UI.
static func set_language(code: String) -> String:
	ensure_installed()
	var chosen := code if code in LANGUAGES else DEFAULT_LANGUAGE
	TranslationServer.set_locale(chosen)
	return chosen


static func current_language() -> String:
	ensure_installed()
	var locale := TranslationServer.get_locale()
	return locale if locale in LANGUAGES else DEFAULT_LANGUAGE


static func is_rtl(code: String = "") -> bool:
	var language := code if not code.is_empty() else current_language()
	return language in RTL_LANGUAGES


## Layout direction to put on a UI root, so containers, scrollbars and text all
## mirror together.
static func layout_direction(code: String = "") -> Control.LayoutDirection:
	return Control.LAYOUT_DIRECTION_RTL if is_rtl(code) else Control.LAYOUT_DIRECTION_LTR


## Left/right alignment for a run of text, mirroring with the language.
static func text_alignment(code: String = "") -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_RIGHT if is_rtl(code) else HORIZONTAL_ALIGNMENT_LEFT


static func keys() -> PackedStringArray:
	ensure_installed()
	return _keys


## Raw table for one language, used by the tests to check the CSV itself.
static func table(code: String) -> Dictionary:
	ensure_installed()
	return _tables.get(code, {})


## Translated text for a key, identical to `tr()` but callable from static code.
static func text(key: String) -> String:
	ensure_installed()
	return TranslationServer.translate(key)
