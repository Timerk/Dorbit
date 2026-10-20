class_name Story
extends RefCounted
## Personal story chapters. The server advances one step at a time and saves the
## pilot's position in the chain with any step reward in the same transaction.
## Sites, quantities and rewards are provisional playtesting values.

const CHAPTER := "Operation Foothold"
const CONTACTS := {
	"vance": {"name": "Commander Rhea Vance", "call": "VANCE"},
	"brell": {"name": "Chief Engineer Tomas Brell", "call": "BRELL"},
	"sato": {"name": "Dr. Imani Sato", "call": "SATO"},
}
# Objective types: reach/recover complete inside the radius, scan needs `required`
# seconds inside it, kill counts qualifying kills of `kind`, collect counts fresh loot
# units, deliver consumes cargo at the station and contract needs any active hunt.
# Hints name input actions in braces; clients substitute the current bindings.
const STEPS: Array[Dictionary] = [
	{
		"id": "comms_check", "title": "Comms Check", "contact": "vance", "type": "reach",
		"map": 0, "position": Vector3(0, 10, -140), "radius": 25.0, "required": 1, "site": "Rendezvous",
		"credits": 300, "research": 0,
		"objective": "Fly to the rendezvous point",
		"hint": "Hold {steer} and move the mouse to steer. {forward} thrusts; release to brake.",
		"briefing": "Pilot, this is Commander Vance aboard Outpost 01. We jumped in hours ago and this sector is still hostile. Before I put you on the line, show me you can fly. Take your ship to the rendezvous marker off our bow.",
		"done": "Clean flying. Stay on this channel.",
	},
	{
		"id": "survey_run", "title": "Survey Run", "contact": "vance", "type": "reach",
		"map": 0, "position": Vector3(0, 40, -560), "radius": 40.0, "required": 1, "site": "Survey point",
		"credits": 500, "research": 0,
		"objective": "Reach the survey point beyond the asteroid field",
		"hint": "Press {sector_map}, click the survey point, then press {autopilot} to fly there. {boost} boosts.",
		"briefing": "Our charts of this sector are thirty years old. Fly past the asteroid field and give us fresh sensor data on the route to the outer gate. Plot the course on the sector map; the autopilot can take you there.",
		"done": "Telemetry received. Those craters on the planet are bombardment scars. This was a colony once.",
	},
	{
		"id": "ring_scan", "title": "Ring Scan", "contact": "sato", "type": "scan",
		"map": 0, "position": Vector3(520, -60, 300), "radius": 45.0, "required": 5, "site": "Defense ring wreck",
		"credits": 800, "research": 0,
		"objective": "Hold position inside the scan field",
		"hint": "Stay inside the ring until the scan completes. Leaving restarts it.",
		"briefing": "Dr. Imani Sato, xenobiology. A section of the old orbital defense ring drifted into the sector. I need a close scan, so stay inside the scanning field until my instruments finish.",
		"done": "Look at these marks. The ring was not just destroyed. Something cut it apart and hauled the pieces away.",
	},
	{
		"id": "first_contact", "title": "First Contact", "contact": "vance", "type": "kill",
		"kind": "Scout", "required": 2,
		"credits": 1200, "research": 0,
		"objective": "Destroy Scouts",
		"hint": "{cycle_target} or {select_target} locks a target. {fire} toggles automatic lasers; keep the target ahead and in range.",
		"briefing": "Sato's scan woke something up. Scout patrols are probing our perimeter. Lock on and drive them off; two kills will make the point.",
		"done": "That is how it is done. They will be back, and bigger.",
	},
	{
		"id": "heavier_resistance", "title": "Heavier Resistance", "contact": "vance", "type": "kill",
		"kind": "Sentinel", "required": 1,
		"credits": 2500, "research": 0,
		"objective": "Destroy a Sentinel",
		"hint": "Sentinels carry strong shields. {rocket} fires a rocket; {launcher} loads and fires a Hellstorm launcher if fitted.",
		"briefing": "A Sentinel is moving on the outpost. Its shields are stronger than anything you have faced. Hit it with everything: lasers and rockets.",
		"done": "Sentinel down. Good work, pilot.",
	},
	{
		"id": "black_box", "title": "Black Box", "contact": "sato", "type": "recover",
		"map": 0, "position": Vector3(-460, 80, -240), "radius": 15.0, "required": 1, "site": "Flight recorder",
		"credits": 1500, "research": 1,
		"objective": "Recover the garrison flight recorder",
		"hint": "Fly into the recorder to pick it up. Only you can see your copy.",
		"briefing": "The old garrison's flight recorder is still sending a weak carrier signal. Bring it to me. Whatever happened here is on that recorder.",
		"done": "Garrison Wing 7 log: \"They came through the Frontier relay first. The ring is holding... no, they are not attacking the ring, they are taking it apart. Evacuate the colony. All wings, fall back to...\" The recording ends there.",
	},
	{
		"id": "field_salvage", "title": "Field Salvage", "contact": "brell", "type": "collect",
		"required": 10,
		"credits": 1500, "research": 0,
		"objective": "Collect resources from destroyed aliens",
		"hint": "Destroyed aliens leave glowing loot boxes. Fly within 12 m to collect them.",
		"briefing": "Chief Engineer Brell here. The station's approach beacon is dead and I am short of raw materials. Alien wrecks are full of ore, so bring some back in your hold.",
		"done": "That will do. Now bring it home.",
	},
	{
		"id": "beacon_parts", "title": "Beacon Parts", "contact": "brell", "type": "deliver",
		"resource": "prometium", "required": 5,
		"credits": 2000, "research": 0,
		"objective": "Deliver Prometium at Outpost 01",
		"hint": "Return to Outpost 01, slow down, open Quests ({contracts}) and press DELIVER. {repair} repairs your ship.",
		"briefing": "Bring five units of Prometium to the outpost. I will fabricate the beacon parts while you get patched up.",
		"done": "Parts are printing. I am loading them into your ship.",
	},
	{
		"id": "light_beacon", "title": "Light the Beacon", "contact": "brell", "type": "scan",
		"map": 0, "position": Vector3(-220, 30, 440), "radius": 30.0, "required": 6, "site": "Approach beacon",
		"credits": 2000, "research": 0,
		"objective": "Hold at the beacon while the parts install",
		"hint": "Stay inside the ring around the beacon mast until installation completes.",
		"briefing": "The old approach beacon is just off our stern. Hold position at the mast while I talk you through the install.",
		"done": "Beacon is online. Supply convoys from home can find us now.",
	},
	{
		"id": "standing_orders", "title": "Standing Orders", "contact": "vance", "type": "contract",
		"required": 1,
		"credits": 5000, "research": 3,
		"objective": "Accept a hunting contract at Outpost 01",
		"hint": "Open Quests ({contracts}), choose Hunting and accept any contract. Hunts pay credits and research points.",
		"briefing": "We have a foothold, pilot, and you helped build it. Command wants this sector cleared before we push to the outer gates. Take a hunting contract from the board. Those are your standing orders.",
		"done": "Welcome to the reclamation, pilot. Vance out.",
	},
]
# Controls taught by each step's pop-up: input actions shown as key caps, then the
# explanation. A row is ticked when the pilot presses any of its actions.
const CONTROLS := {
	"comms_check": [
		[["steer"], "Hold and move mouse to steer"],
		[["forward", "backward"], "Thrust forward / reverse"],
		[["strafe_left", "strafe_right"], "Strafe sideways"],
	],
	"survey_run": [
		[["sector_map"], "Map: click the survey point"],
		[["autopilot"], "Autopilot to your selection"],
		[["boost"], "Boost while energy lasts"],
	],
	"ring_scan": [
		[["move_up", "move_down"], "Climb / descend"],
		[["backward"], "Reverse to stop in the field"],
	],
	"first_contact": [
		[["cycle_target"], "Lock the alien nearest your aim"],
		[["select_target"], "Or click a ship to lock it"],
		[["fire"], "Toggle automatic lasers"],
	],
	"heavier_resistance": [
		[["rocket"], "Fire a single rocket"],
		[["launcher"], "Load, then fire Hellstorm"],
		[["quickslot_1", "quickslot_2"], "Switch laser ammunition"],
	],
	"black_box": [
		[["sector_map"], "Find the recorder on the map"],
		[["autopilot"], "Autopilot stops right at it"],
	],
	"field_salvage": [
		[["cycle_target"], "Lock an alien"],
		[["fire"], "Destroy it, fly into its loot"],
	],
	"beacon_parts": [
		[["repair"], "Repair at the outpost"],
		[["station_shop"], "Shop and sell spare cargo"],
		[["contracts"], "Quests: deliver Prometium"],
	],
	"light_beacon": [
		[["ship_equipment"], "Fit equipment at the station"],
		[["move_up", "move_down"], "Climb / descend to the mast"],
	],
	"standing_orders": [
		[["contracts"], "Open Quests and accept a hunt"],
		[["jump_gate"], "Jump through a gate (later)"],
	],
}
const POSITIONAL := ["reach", "scan", "recover"]
const BEACON_STEP := 8


static func empty() -> Dictionary:
	return {"step": 0, "progress": 0}


# Pilots without saved progress start at the first step; no save migration is needed.
static func state(equipment: Dictionary) -> Dictionary:
	return equipment.get("story", empty())


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Skylab.integer(value.get("step"), 0, STEPS.size()):
		return false
	var limit := 0 if int(value["step"]) == STEPS.size() else int(STEPS[int(value["step"])]["required"]) - 1
	return Skylab.integer(value.get("progress"), 0, limit)


static func normalize(value: Dictionary) -> void:
	value["step"] = int(value["step"])
	value["progress"] = int(value["progress"])


static func complete(story: Dictionary) -> bool:
	return int(story["step"]) >= STEPS.size()


# Empty input means no story is available, as before the first inventory arrives.
static func current(story: Dictionary) -> Dictionary:
	return {} if story.is_empty() or complete(story) else STEPS[int(story["step"])]


## Count one event toward the current step. Returns the next state with any step
## reward, or an empty dictionary when the event does not apply.
static func advance(story: Dictionary, type: String, amount: int = 1, kind: String = "") -> Dictionary:
	var step := current(story)
	if step.is_empty() or step["type"] != type or amount < 1 or (step.has("kind") and step["kind"] != kind):
		return {}
	var progress := int(story["progress"]) + amount
	if progress < int(step["required"]):
		return {"story": {"step": story["step"], "progress": progress}, "credits": 0, "research": 0, "finished": {}}
	return {"story": {"step": int(story["step"]) + 1, "progress": 0}, "credits": step["credits"], "research": step["research"], "finished": step}


## Remaining step rewards for pilots who skip the chapter.
static func skip(story: Dictionary) -> Dictionary:
	var credits := 0
	var research := 0
	for index in range(int(story["step"]), STEPS.size()):
		credits += int(STEPS[index]["credits"])
		research += int(STEPS[index]["research"])
	return {"story": {"step": STEPS.size(), "progress": 0}, "credits": credits, "research": research, "finished": {}}


static func site(story: Dictionary, map: int) -> Dictionary:
	var step := current(story)
	return step if not step.is_empty() and step["type"] in POSITIONAL and step["map"] == map else {}


static func site_position(step: Dictionary) -> Vector3:
	return SectorMaps.origin(step["map"]) + step["position"]


static func objective(story: Dictionary, scan_seconds: float = 0.0) -> String:
	var step := current(story)
	if step.is_empty():
		return "Prologue complete."
	var progress := float(story["progress"])
	if step["type"] == "scan":
		progress = minf(scan_seconds, step["required"])
		return "%s  %d / %d s" % [step["objective"], floori(progress), step["required"]]
	if int(step["required"]) > 1:
		return "%s  %d / %d" % [step["objective"], int(progress), step["required"]]
	return step["objective"]


## The in-flight transmission for a step: speaker call sign and briefing.
static func transmission(step: Dictionary, text_key: String = "briefing") -> String:
	return "%s: %s" % [CONTACTS[step["contact"]]["call"], step[text_key]]


static func reward_text(credits: int, research: int) -> String:
	var text := "+%s CR" % StationShop.credits_text(credits)
	return text + (" and +%d research points" % research if research > 0 else "")


## Transmission after a completed step: its closing line, reward and the next briefing.
static func completion_notice(finished: Dictionary, story: Dictionary) -> String:
	var notice := "%s %s." % [transmission(finished, "done"), reward_text(finished["credits"], finished["research"])]
	var next := current(story)
	if next.is_empty():
		return notice + " %s complete." % CHAPTER
	return notice + "\n" + transmission(next)


## Replace {action} names with the player's current bindings.
static func hint(step: Dictionary) -> String:
	var text: String = step.get("hint", "")
	var start := text.find("{")
	while start >= 0:
		var finish := text.find("}", start)
		if finish < 0:
			break
		var action := text.substr(start + 1, finish - start - 1)
		var label := GameSettings.binding_text(action)
		text = text.substr(0, start) + label + text.substr(finish + 1)
		start = text.find("{", start + label.length())
	return text
