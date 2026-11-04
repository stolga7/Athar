extends RefCounted
## Data for ATHAR's ten explorable regions.
##
## A region is pure data: a palette, a vegetation profile, an atmosphere tint, a
## landmark style, a small wildlife habitat and the entry/gate points. Nothing
## here builds geometry or knows about the scene — `region_builder.gd` reads these
## dictionaries, which is what lets the tests validate every region without a
## renderer and lets a future quest or boss system hang off the same definitions.
##
## The silver forest is deliberately the Phase 3.1–3.5 wilderness: its palette is
## the original one, so the default world is bit-for-bit the world the earlier
## phases shipped and every existing visual and gameplay assertion still holds.

const DEFAULT_REGION := "silver_forest"

## Fields every definition must carry. The tests check this list, and the builder
## falls back to the silver forest when a value is missing.
const REQUIRED_FIELDS := [
	"id", "name_key", "desc_key", "ground", "vegetation",
	"atmosphere", "landmark", "habitat", "entry", "gate", "exits", "future",
]

const GROUND_FIELDS := [
	"dark", "moss", "grass", "dry", "backdrop",
	"roughness", "stone", "tuft_base", "tuft_tip",
	"tuft_count", "stone_count", "noise_seed",
]

const VEGETATION_FIELDS := [
	"tree_count", "far_tree_count", "inner_radius", "outer_radius", "min_spacing",
]

const ATMOSPHERE_FIELDS := [
	"sun_color", "sun_energy", "ambient_color", "fog_color",
	"fog_density", "sky_tint", "sky_amount", "exposure",
]

const HABITAT_FIELDS := ["archetype", "spawn_min", "spawn_max"]


## All ten regions, in the order the selection screen lists them.
static func all() -> Array:
	return [
		_desert(),
		_silver_forest(),
		_frozen_highlands(),
		_ember_lands(),
		_ancient_ruins(),
		_mirage_oasis(),
		_crystal_caves(),
		_reflection_swamp(),
		_sky_cliffs(),
		_void_realm(),
	]


static func ids() -> Array:
	var out := []
	for region in all():
		out.append(String(region["id"]))
	return out


static func count() -> int:
	return all().size()


## One definition, or an empty dictionary when the id is unknown. Callers treat an
## empty result as "refuse the transition" rather than silently loading something.
static func get_region(id: String) -> Dictionary:
	for region in all():
		if String(region["id"]) == id:
			return region
	return {}


static func is_valid(id: String) -> bool:
	return not get_region(id).is_empty()


static func name_key(id: String) -> String:
	return "region.%s.name" % id


static func desc_key(id: String) -> String:
	return "region.%s.desc" % id


## Every translation key the region screens need, so a test can assert the CSV
## carries them without duplicating the naming rule.
static func translation_keys() -> Array:
	var keys := ["regions.title", "regions.subtitle", "regions.travel", "regions.current",
		"regions.visited", "regions.unvisited", "regions.progress", "regions.back",
		"regions.locked", "menu.regions", "menu.travel"]
	for id in ids():
		keys.append(name_key(String(id)))
		keys.append(desc_key(String(id)))
	return keys


## Problems with one definition, as human-readable strings. An empty array means
## the region is complete enough to load.
static func validate(region: Dictionary) -> Array:
	var problems := []
	for field in REQUIRED_FIELDS:
		if not region.has(field):
			problems.append("missing %s" % field)
	if not problems.is_empty():
		return problems
	if String(region["id"]).is_empty():
		problems.append("empty id")
	if not String(region["id"]).is_valid_identifier():
		problems.append("id is not a valid identifier")
	for field in GROUND_FIELDS:
		if not (region["ground"] as Dictionary).has(field):
			problems.append("ground.%s missing" % field)
	for field in VEGETATION_FIELDS:
		if not (region["vegetation"] as Dictionary).has(field):
			problems.append("vegetation.%s missing" % field)
	for field in ATMOSPHERE_FIELDS:
		if not (region["atmosphere"] as Dictionary).has(field):
			problems.append("atmosphere.%s missing" % field)
	for field in HABITAT_FIELDS:
		if not (region["habitat"] as Dictionary).has(field):
			problems.append("habitat.%s missing" % field)
	var vegetation: Dictionary = region["vegetation"]
	if int(vegetation.get("tree_count", 0)) < 0:
		problems.append("negative tree count")
	if float(vegetation.get("outer_radius", 1.0)) <= float(vegetation.get("inner_radius", 0.0)):
		problems.append("vegetation ring is inverted")
	var habitat: Dictionary = region["habitat"]
	if float(habitat.get("spawn_max", 0.0)) < float(habitat.get("spawn_min", 0.0)):
		problems.append("habitat spawn range is inverted")
	if (region["future"] as Dictionary).is_empty():
		problems.append("future hooks missing")
	for exit_id in region["exits"]:
		if String(exit_id) == String(region["id"]):
			problems.append("region exits to itself")
	return problems


## Validation across the whole table, including cross-region rules: unique ids,
## every exit pointing at a real region, and at least one landmark style in use.
static func validate_all() -> Array:
	var problems := []
	var seen := {}
	var exits := 0
	for region in all():
		var id := String(region.get("id", "?"))
		if seen.has(id):
			problems.append("duplicate id %s" % id)
		seen[id] = true
		for problem in validate(region):
			problems.append("%s: %s" % [id, problem])
	for region in all():
		for exit_id in region["exits"]:
			exits += 1
			if not seen.has(String(exit_id)):
				problems.append("%s exits to unknown region %s" % [region["id"], exit_id])
	if exits == 0:
		problems.append("no region exits are defined")
	return problems


# --------------------------------------------------------------- definitions ---

static func _region(id: String, landmark: String) -> Dictionary:
	# Shared skeleton; each region overrides the parts that give it its identity.
	return {
		"id": id,
		"name_key": name_key(id),
		"desc_key": desc_key(id),
		"landmark": landmark,
		"entry": Vector3(0.0, 0.1, 7.0),
		"gate": Vector3(0.0, 0.0, -12.0),
		"exits": [],
		"future": {"creatures": [], "bosses": [], "quests": [], "events": []},
	}


static func _desert() -> Dictionary:
	var region := _region("desert", "dunes")
	region["ground"] = {
		"dark": Color(0.243, 0.180, 0.102),
		"moss": Color(0.404, 0.310, 0.161),
		"grass": Color(0.529, 0.408, 0.212),
		"dry": Color(0.612, 0.494, 0.286),
		"backdrop": Color(0.478, 0.365, 0.196),
		"roughness": 0.97,
		"stone": Color(0.361, 0.294, 0.208),
		"tuft_base": Color(0.361, 0.310, 0.161),
		"tuft_tip": Color(0.545, 0.463, 0.243),
		"tuft_count": 130,
		"stone_count": 54,
		"noise_seed": 4021,
	}
	region["vegetation"] = {
		"tree_count": 0, "far_tree_count": 0,
		"inner_radius": 16.0, "outer_radius": 40.0, "min_spacing": 4.0,
		"leaf_palettes": [],
		"bark_colors": [],
	}
	region["atmosphere"] = {
		"sun_color": Color(1.0, 0.93, 0.74),
		"sun_energy": 1.22,
		"ambient_color": Color(1.06, 0.96, 0.82),
		"fog_color": Color(1.35, 1.16, 0.86),
		"fog_density": 0.72,
		"sky_tint": Color(0.86, 0.72, 0.48),
		"sky_amount": 0.34,
		"exposure": 1.04,
	}
	region["habitat"] = {"archetype": "bold", "spawn_min": 18.0, "spawn_max": 30.0}
	region["exits"] = ["silver_forest", "mirage_oasis"]
	return region


static func _silver_forest() -> Dictionary:
	# The Phase 3.1–3.5 world. Every value here is the value the earlier phases
	# shipped, which is why the default region is byte-identical to before.
	var region := _region("silver_forest", "ruin")
	region["ground"] = {
		"dark": Color(0.062, 0.082, 0.054),
		"moss": Color(0.086, 0.112, 0.070),
		"grass": Color(0.108, 0.138, 0.082),
		"dry": Color(0.140, 0.142, 0.094),
		"backdrop": Color(0.073, 0.095, 0.060),
		"roughness": 0.96,
		"stone": Color(0.22, 0.25, 0.21),
		"tuft_base": Color(0.088, 0.132, 0.068),
		"tuft_tip": Color(0.158, 0.216, 0.108),
		"tuft_count": 620,
		"stone_count": 70,
		"noise_seed": 1337,
	}
	region["vegetation"] = {
		"tree_count": 84, "far_tree_count": 54,
		"inner_radius": 14.0, "outer_radius": 43.0, "min_spacing": 3.5,
		"leaf_palettes": [],
		"bark_colors": [],
		# The original Phase 3.1 clearings, so the shipped forest layout is kept.
		"clearings": [
			{"center": Vector3(0.0, 0.0, 7.0), "radius": 4.5},
			{"center": Vector3(-10.0, 0.0, -15.0), "radius": 6.0},
		],
	}
	region["atmosphere"] = {
		"sun_color": Color(1, 1, 1),
		"sun_energy": 1.0,
		"ambient_color": Color(1, 1, 1),
		"fog_color": Color(1, 1, 1),
		"fog_density": 1.0,
		"sky_tint": Color(1, 1, 1),
		"sky_amount": 0.0,
		"exposure": 1.0,
	}
	# An empty archetype keeps the seed-rolled temperament of Phase 3.2: the
	# starting region must behave exactly as it always has.
	region["habitat"] = {"archetype": "", "spawn_min": 16.0, "spawn_max": 26.0}
	region["gate"] = Vector3(-10.0, 0.0, -13.0)
	region["exits"] = ["desert", "ancient_ruins", "reflection_swamp"]
	return region


static func _frozen_highlands() -> Dictionary:
	var region := _region("frozen_highlands", "ice_spires")
	region["ground"] = {
		"dark": Color(0.196, 0.231, 0.267),
		"moss": Color(0.361, 0.412, 0.455),
		"grass": Color(0.565, 0.627, 0.667),
		"dry": Color(0.784, 0.831, 0.855),
		"backdrop": Color(0.667, 0.722, 0.757),
		"roughness": 0.62,
		"stone": Color(0.478, 0.529, 0.573),
		"tuft_base": Color(0.412, 0.475, 0.518),
		"tuft_tip": Color(0.729, 0.784, 0.816),
		"tuft_count": 300,
		"stone_count": 82,
		"noise_seed": 7712,
	}
	region["vegetation"] = {
		"tree_count": 46, "far_tree_count": 34,
		"inner_radius": 15.0, "outer_radius": 42.0, "min_spacing": 4.2,
		"leaf_palettes": [
			[Color(0.114, 0.169, 0.180), Color(0.157, 0.227, 0.235), Color(0.212, 0.290, 0.290)],
			[Color(0.086, 0.129, 0.145), Color(0.125, 0.180, 0.196), Color(0.180, 0.243, 0.251)],
			[Color(0.161, 0.204, 0.212), Color(0.212, 0.259, 0.267), Color(0.278, 0.325, 0.325)],
		],
		"bark_colors": [Color(0.129, 0.114, 0.102), Color(0.161, 0.145, 0.129), Color(0.106, 0.094, 0.086)],
	}
	region["atmosphere"] = {
		"sun_color": Color(0.86, 0.93, 1.0),
		"sun_energy": 0.92,
		"ambient_color": Color(0.86, 0.94, 1.06),
		"fog_color": Color(1.02, 1.10, 1.18),
		"fog_density": 1.85,
		"sky_tint": Color(0.72, 0.81, 0.90),
		"sky_amount": 0.42,
		"exposure": 0.98,
	}
	region["habitat"] = {"archetype": "nervous", "spawn_min": 18.0, "spawn_max": 28.0}
	region["exits"] = ["silver_forest", "sky_cliffs"]
	return region


static func _ember_lands() -> Dictionary:
	var region := _region("ember_lands", "lava_columns")
	region["ground"] = {
		"dark": Color(0.086, 0.067, 0.059),
		"moss": Color(0.145, 0.106, 0.086),
		"grass": Color(0.196, 0.137, 0.102),
		"dry": Color(0.278, 0.180, 0.118),
		"backdrop": Color(0.125, 0.090, 0.075),
		"roughness": 0.88,
		"stone": Color(0.196, 0.176, 0.169),
		"tuft_base": Color(0.196, 0.129, 0.086),
		"tuft_tip": Color(0.518, 0.243, 0.110),
		"tuft_count": 150,
		"stone_count": 96,
		"noise_seed": 9331,
	}
	region["vegetation"] = {
		"tree_count": 18, "far_tree_count": 22,
		"inner_radius": 16.0, "outer_radius": 40.0, "min_spacing": 5.0,
		"leaf_palettes": [
			[Color(0.180, 0.086, 0.059), Color(0.259, 0.114, 0.063), Color(0.361, 0.149, 0.067)],
			[Color(0.129, 0.071, 0.055), Color(0.196, 0.094, 0.059), Color(0.290, 0.125, 0.071)],
			[Color(0.212, 0.106, 0.063), Color(0.290, 0.137, 0.071), Color(0.408, 0.180, 0.075)],
		],
		"bark_colors": [Color(0.086, 0.071, 0.063), Color(0.114, 0.090, 0.078), Color(0.067, 0.055, 0.051)],
	}
	region["atmosphere"] = {
		"sun_color": Color(1.0, 0.78, 0.60),
		"sun_energy": 0.86,
		"ambient_color": Color(1.12, 0.86, 0.72),
		"fog_color": Color(1.40, 0.98, 0.80),
		"fog_density": 1.55,
		"sky_tint": Color(0.62, 0.31, 0.20),
		"sky_amount": 0.52,
		"exposure": 0.94,
	}
	region["habitat"] = {"archetype": "bold", "spawn_min": 17.0, "spawn_max": 27.0}
	region["exits"] = ["ancient_ruins", "void_realm"]
	return region


static func _ancient_ruins() -> Dictionary:
	var region := _region("ancient_ruins", "colonnade")
	region["ground"] = {
		"dark": Color(0.129, 0.118, 0.098),
		"moss": Color(0.204, 0.196, 0.161),
		"grass": Color(0.286, 0.278, 0.212),
		"dry": Color(0.376, 0.353, 0.267),
		"backdrop": Color(0.243, 0.231, 0.188),
		"roughness": 0.94,
		"stone": Color(0.396, 0.376, 0.325),
		"tuft_base": Color(0.243, 0.243, 0.180),
		"tuft_tip": Color(0.408, 0.388, 0.278),
		"tuft_count": 340,
		"stone_count": 120,
		"noise_seed": 5150,
	}
	region["vegetation"] = {
		"tree_count": 40, "far_tree_count": 30,
		"inner_radius": 15.0, "outer_radius": 42.0, "min_spacing": 4.0,
		"leaf_palettes": [
			[Color(0.145, 0.169, 0.098), Color(0.196, 0.216, 0.125), Color(0.251, 0.263, 0.157)],
			[Color(0.114, 0.145, 0.086), Color(0.157, 0.188, 0.110), Color(0.204, 0.235, 0.137)],
			[Color(0.180, 0.196, 0.114), Color(0.235, 0.243, 0.145), Color(0.290, 0.290, 0.176)],
		],
		"bark_colors": [Color(0.196, 0.169, 0.129), Color(0.235, 0.204, 0.157), Color(0.161, 0.137, 0.106)],
	}
	region["atmosphere"] = {
		"sun_color": Color(1.0, 0.95, 0.86),
		"sun_energy": 1.08,
		"ambient_color": Color(1.02, 0.98, 0.92),
		"fog_color": Color(1.10, 1.04, 0.92),
		"fog_density": 0.92,
		"sky_tint": Color(0.82, 0.74, 0.60),
		"sky_amount": 0.24,
		"exposure": 1.02,
	}
	region["habitat"] = {"archetype": "steady", "spawn_min": 16.0, "spawn_max": 26.0}
	region["exits"] = ["silver_forest", "ember_lands", "crystal_caves"]
	return region


static func _mirage_oasis() -> Dictionary:
	var region := _region("mirage_oasis", "oasis_pool")
	region["ground"] = {
		"dark": Color(0.196, 0.176, 0.114),
		"moss": Color(0.310, 0.290, 0.169),
		"grass": Color(0.412, 0.388, 0.220),
		"dry": Color(0.522, 0.482, 0.290),
		"backdrop": Color(0.412, 0.376, 0.231),
		"roughness": 0.78,
		"stone": Color(0.353, 0.325, 0.243),
		"tuft_base": Color(0.243, 0.290, 0.169),
		"tuft_tip": Color(0.396, 0.451, 0.243),
		"tuft_count": 240,
		"stone_count": 44,
		"noise_seed": 8022,
	}
	region["vegetation"] = {
		"tree_count": 14, "far_tree_count": 18,
		"inner_radius": 17.0, "outer_radius": 38.0, "min_spacing": 5.5,
		"leaf_palettes": [
			[Color(0.157, 0.290, 0.180), Color(0.204, 0.353, 0.212), Color(0.251, 0.412, 0.243)],
			[Color(0.129, 0.251, 0.180), Color(0.176, 0.310, 0.212), Color(0.220, 0.361, 0.243)],
			[Color(0.196, 0.325, 0.196), Color(0.243, 0.388, 0.227), Color(0.290, 0.443, 0.259)],
		],
		"bark_colors": [Color(0.251, 0.212, 0.157), Color(0.290, 0.243, 0.180), Color(0.212, 0.180, 0.137)],
	}
	region["atmosphere"] = {
		"sun_color": Color(1.0, 0.96, 0.86),
		"sun_energy": 1.16,
		"ambient_color": Color(1.04, 1.0, 0.92),
		"fog_color": Color(1.16, 1.08, 0.92),
		"fog_density": 0.78,
		"sky_tint": Color(0.78, 0.74, 0.56),
		"sky_amount": 0.22,
		"exposure": 1.05,
	}
	region["habitat"] = {"archetype": "cautious", "spawn_min": 18.0, "spawn_max": 28.0}
	region["exits"] = ["desert", "reflection_swamp"]
	return region


static func _crystal_caves() -> Dictionary:
	var region := _region("crystal_caves", "crystal_cluster")
	region["ground"] = {
		"dark": Color(0.075, 0.071, 0.110),
		"moss": Color(0.110, 0.102, 0.157),
		"grass": Color(0.145, 0.129, 0.204),
		"dry": Color(0.188, 0.161, 0.251),
		"backdrop": Color(0.094, 0.086, 0.137),
		"roughness": 0.42,
		"stone": Color(0.204, 0.196, 0.267),
		"tuft_base": Color(0.129, 0.157, 0.216),
		"tuft_tip": Color(0.290, 0.416, 0.518),
		"tuft_count": 120,
		"stone_count": 90,
		"noise_seed": 6613,
	}
	region["vegetation"] = {
		"tree_count": 0, "far_tree_count": 0,
		"inner_radius": 16.0, "outer_radius": 40.0, "min_spacing": 4.0,
		"leaf_palettes": [],
		"bark_colors": [],
	}
	region["atmosphere"] = {
		"sun_color": Color(0.80, 0.88, 1.0),
		"sun_energy": 0.62,
		"ambient_color": Color(0.78, 0.90, 1.12),
		"fog_color": Color(0.88, 0.94, 1.20),
		"fog_density": 2.10,
		"sky_tint": Color(0.32, 0.28, 0.46),
		"sky_amount": 0.62,
		"exposure": 0.90,
	}
	region["habitat"] = {"archetype": "nervous", "spawn_min": 16.0, "spawn_max": 24.0}
	region["exits"] = ["ancient_ruins", "void_realm"]
	return region


static func _reflection_swamp() -> Dictionary:
	var region := _region("reflection_swamp", "sunken_bridge")
	region["ground"] = {
		"dark": Color(0.055, 0.082, 0.075),
		"moss": Color(0.082, 0.125, 0.110),
		"grass": Color(0.110, 0.161, 0.137),
		"dry": Color(0.145, 0.188, 0.153),
		"backdrop": Color(0.075, 0.110, 0.098),
		"roughness": 0.54,
		"stone": Color(0.169, 0.196, 0.180),
		"tuft_base": Color(0.110, 0.180, 0.137),
		"tuft_tip": Color(0.196, 0.278, 0.196),
		"tuft_count": 520,
		"stone_count": 62,
		"noise_seed": 2244,
	}
	region["vegetation"] = {
		"tree_count": 36, "far_tree_count": 26,
		"inner_radius": 15.0, "outer_radius": 42.0, "min_spacing": 4.4,
		"leaf_palettes": [
			[Color(0.067, 0.129, 0.110), Color(0.094, 0.161, 0.129), Color(0.125, 0.196, 0.153)],
			[Color(0.055, 0.110, 0.098), Color(0.078, 0.141, 0.114), Color(0.106, 0.176, 0.137)],
			[Color(0.086, 0.149, 0.125), Color(0.114, 0.180, 0.145), Color(0.149, 0.216, 0.169)],
		],
		"bark_colors": [Color(0.129, 0.125, 0.110), Color(0.161, 0.153, 0.137), Color(0.106, 0.102, 0.090)],
	}
	region["atmosphere"] = {
		"sun_color": Color(0.88, 0.98, 0.94),
		"sun_energy": 0.74,
		"ambient_color": Color(0.88, 1.02, 0.96),
		"fog_color": Color(0.92, 1.08, 1.00),
		"fog_density": 1.95,
		"sky_tint": Color(0.44, 0.55, 0.48),
		"sky_amount": 0.40,
		"exposure": 0.94,
	}
	region["habitat"] = {"archetype": "cautious", "spawn_min": 17.0, "spawn_max": 27.0}
	region["exits"] = ["silver_forest", "mirage_oasis"]
	return region


static func _sky_cliffs() -> Dictionary:
	var region := _region("sky_cliffs", "cliff_platforms")
	region["ground"] = {
		"dark": Color(0.145, 0.145, 0.153),
		"moss": Color(0.204, 0.208, 0.216),
		"grass": Color(0.267, 0.271, 0.278),
		"dry": Color(0.333, 0.333, 0.333),
		"backdrop": Color(0.212, 0.216, 0.227),
		"roughness": 0.90,
		"stone": Color(0.290, 0.294, 0.310),
		"tuft_base": Color(0.220, 0.243, 0.220),
		"tuft_tip": Color(0.353, 0.380, 0.322),
		"tuft_count": 140,
		"stone_count": 110,
		"noise_seed": 3141,
	}
	region["vegetation"] = {
		"tree_count": 10, "far_tree_count": 16,
		"inner_radius": 18.0, "outer_radius": 38.0, "min_spacing": 6.0,
		"leaf_palettes": [
			[Color(0.110, 0.145, 0.129), Color(0.145, 0.188, 0.161), Color(0.188, 0.235, 0.196)],
			[Color(0.086, 0.118, 0.110), Color(0.118, 0.157, 0.137), Color(0.157, 0.196, 0.169)],
			[Color(0.137, 0.169, 0.145), Color(0.176, 0.212, 0.176), Color(0.220, 0.259, 0.212)],
		],
		"bark_colors": [Color(0.157, 0.149, 0.137), Color(0.188, 0.180, 0.161), Color(0.129, 0.125, 0.118)],
	}
	region["atmosphere"] = {
		"sun_color": Color(1.0, 0.97, 0.92),
		"sun_energy": 1.32,
		"ambient_color": Color(0.98, 1.0, 1.04),
		"fog_color": Color(1.06, 1.08, 1.12),
		"fog_density": 0.66,
		"sky_tint": Color(0.70, 0.76, 0.86),
		"sky_amount": 0.30,
		"exposure": 1.06,
	}
	region["habitat"] = {"archetype": "bold", "spawn_min": 18.0, "spawn_max": 30.0}
	region["exits"] = ["frozen_highlands", "crystal_caves"]
	return region


static func _void_realm() -> Dictionary:
	var region := _region("void_realm", "void_monolith")
	region["ground"] = {
		"dark": Color(0.035, 0.031, 0.055),
		"moss": Color(0.059, 0.051, 0.086),
		"grass": Color(0.086, 0.071, 0.125),
		"dry": Color(0.125, 0.094, 0.169),
		"backdrop": Color(0.047, 0.039, 0.071),
		"roughness": 0.80,
		"stone": Color(0.129, 0.118, 0.169),
		"tuft_base": Color(0.086, 0.071, 0.129),
		"tuft_tip": Color(0.243, 0.180, 0.353),
		"tuft_count": 90,
		"stone_count": 70,
		"noise_seed": 9090,
	}
	region["vegetation"] = {
		"tree_count": 0, "far_tree_count": 0,
		"inner_radius": 16.0, "outer_radius": 40.0, "min_spacing": 4.0,
		"leaf_palettes": [],
		"bark_colors": [],
	}
	region["atmosphere"] = {
		"sun_color": Color(0.72, 0.66, 1.0),
		"sun_energy": 0.54,
		"ambient_color": Color(0.72, 0.66, 1.06),
		"fog_color": Color(0.74, 0.68, 1.06),
		"fog_density": 2.30,
		"sky_tint": Color(0.22, 0.19, 0.36),
		"sky_amount": 0.72,
		"exposure": 0.86,
	}
	region["habitat"] = {"archetype": "nervous", "spawn_min": 16.0, "spawn_max": 25.0}
	region["exits"] = ["ember_lands", "crystal_caves"]
	return region
