extends Control
## Region screen: the ten regions, what they are, and which ones have been seen.
##
## It is a thin view over the region manager's listing, so the screen never owns
## progression state. Buttons carry the region's translation key, and a tick marks
## a discovered region; the description of the highlighted region is shown below
## the list, because a phone has no hover.

signal travel_requested(id: String)
signal closed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Localization := preload("res://scripts/ui/localization.gd")

var panel: PanelContainer
var content: VBoxContainer
var list_box: VBoxContainer
var scroll: ScrollContainer
var description_label: Label
var progress_label: Label
var travel_button: Button
var back_button: Button
var region_buttons := {}

var _listing: Array = []
var _selected_id := ""
var _built := false


func _ready() -> void:
	theme = UiKit.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if not _built:
		_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var frame := UiKit.modal(self, "regions.title")
	panel = frame["panel"]
	content = frame["content"]
	panel.custom_minimum_size = Vector2(430, 0)

	var subtitle := UiKit.label("regions.subtitle", "Caption")
	subtitle.name = "Subtitle"
	content.add_child(subtitle)

	progress_label = UiKit.label("regions.progress", "Caption")
	progress_label.name = "Progress"
	content.add_child(progress_label)

	scroll = ScrollContainer.new()
	scroll.name = "RegionScroll"
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.name = "RegionList"
	list_box.add_theme_constant_override("separation", 6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	description_label = UiKit.label("regions.subtitle", "Caption")
	description_label.name = "Description"
	description_label.custom_minimum_size = Vector2(0, 46)
	content.add_child(description_label)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	travel_button = UiKit.button("regions.travel")
	travel_button.name = "TravelButton"
	travel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travel_button.pressed.connect(_on_travel)
	actions.add_child(travel_button)
	back_button = UiKit.button("regions.back")
	back_button.name = "BackButton"
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(close)
	actions.add_child(back_button)
	content.add_child(actions)

	retranslate()


func open(listing: Array) -> void:
	visible = true
	refresh(listing)
	# Open on the region the hunter is standing in, so travel always starts from
	# where the player actually is.
	for region in listing:
		if bool(region["active"]):
			select(String(region["id"]))
			break
	if _selected_id.is_empty() and not listing.is_empty():
		select(String(listing[0]["id"]))


func close() -> void:
	visible = false
	closed.emit()


## Rebuilds the buttons from the manager's listing. Ten buttons is cheap enough to
## recreate, and it keeps the discovery ticks and the active marker honest.
func refresh(listing: Array) -> void:
	_listing = listing
	if not _built:
		return
	for child in list_box.get_children():
		child.queue_free()
	region_buttons.clear()
	var active_id := ""
	for region in listing:
		var id := String(region["id"])
		if bool(region["active"]):
			active_id = id
		var button := UiKit.button(String(region["name_key"]))
		button.name = "Region_%s" % id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(select.bind(id))
		if bool(region["active"]):
			button.add_theme_color_override("font_color", UiKit.GOLD)
		list_box.add_child(button)
		region_buttons[id] = button
	if _selected_id.is_empty():
		_selected_id = active_id if not active_id.is_empty() else String(listing[0]["id"]) if not listing.is_empty() else ""
	_apply_marks()
	_refresh_description()
	progress_label.text = Localization.text("regions.progress") % [_visited_count(), listing.size()]


func select(id: String) -> void:
	if not region_buttons.has(id):
		return
	_selected_id = id
	_apply_marks()
	_refresh_description()


func selected_id() -> String:
	return _selected_id


func _visited_count() -> int:
	var count := 0
	for region in _listing:
		if bool(region["visited"]):
			count += 1
	return count


## Button labels are rebuilt here (not by the generic retranslate pass) because
## they carry a discovery tick and an "active" marker around the region's name.
func _apply_marks() -> void:
	for region in _listing:
		var id := String(region["id"])
		if not region_buttons.has(id):
			continue
		var button: Button = region_buttons[id]
		var label := Localization.text(String(region["name_key"]))
		if bool(region["active"]):
			label += "   •  " + Localization.text("regions.current")
		elif bool(region["visited"]):
			label += "   ✓"
		UiKit.tag(button, String(region["name_key"]), HORIZONTAL_ALIGNMENT_LEFT)
		button.text = label


func _refresh_description() -> void:
	var region := _region(_selected_id)
	description_label.visible = not region.is_empty()
	if region.is_empty():
		return
	description_label.text = Localization.text(String(region["desc_key"]))
	travel_button.disabled = bool(region["active"])


func _region(id: String) -> Dictionary:
	for region in _listing:
		if String(region["id"]) == id:
			return region
	return {}


func _on_travel() -> void:
	if _selected_id.is_empty():
		return
	travel_requested.emit(_selected_id)


func retranslate() -> void:
	if not _built:
		return
	UiKit.retranslate(self)
	layout_direction = Localization.layout_direction()
	_apply_marks()
	_refresh_description()
	progress_label.text = Localization.text("regions.progress") % [_visited_count(), _listing.size()]
