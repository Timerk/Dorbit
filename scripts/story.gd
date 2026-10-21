class_name Story
extends RefCounted
## Personal story chapters. The server advances one step at a time and saves the
## pilot's position in the chain with any step reward in the same transaction.
## Chapters are consecutive runs of STEPS, so a pilot who finished one chapter is
## already at the first step of the next. Sites, quantities and rewards are
## provisional playtesting values.

# Each chapter starts at `start` and runs to the next chapter's start.
const CHAPTERS: Array[Dictionary] = [
	{"title": "Operation Foothold", "label": "Prologue", "start": 0},
	{"title": "Operation Groundwork", "label": "Chapter 1", "start": 10},
]
const CONTACTS := {
	"vance": {"name": "Commander Rhea Vance", "call": "VANCE"},
	"brell": {"name": "Chief Engineer Tomas Brell", "call": "BRELL"},
	"sato": {"name": "Dr. Imani Sato", "call": "SATO"},
}
# Objective types: reach/recover complete inside the radius, scan needs `required`
# seconds inside it, kill counts qualifying kills of `kind`, collect counts fresh loot
# units, deliver consumes cargo at the station and contract needs any active hunt.
# lab_upgrade counts Skylab upgrades started on a `kind` module (basic or collector), lab_ship counts
# dispatched Skylab shipments and research counts learned skill levels.
# `lab` rewards add refined stock to Skylab, up to its storage capacity; only
# station and Skylab steps pay them, inside the same transaction.
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
	{
		"id": "industry_online", "title": "Industry Online", "contact": "brell", "type": "lab_upgrade",
		"kind": "basic", "required": 1,
		"credits": 1000, "research": 0, "lab": {"prometid": 50, "duranium": 50},
		"objective": "Start a Basic module upgrade in Skylab",
		"hint": "Press {pause_game} and open SKYLAB, in flight or docked. Select the Basic module and press Build on its Upgrade tab.",
		"briefing": "Brell again. A beacon is not a base. Outpost 01 brought a Skylab industrial platform: collectors pull raw ore out of the debris around us and refineries process it, around the clock, even while you are off shift. Everything is still on factory settings, and no module can outgrow the Basic core. Open Skylab and start a Basic upgrade.",
		"done": "Core upgrade is underway; it finishes on its timer. Meanwhile, collectors feed the refineries: Prometium and Endurium become Prometid, Endurium and Terbium become Duranium. I ran your first batch through the line myself.",
	},
	{
		"id": "countermeasures", "title": "Countermeasures", "contact": "sato", "type": "research",
		"required": 1,
		"credits": 2000, "research": 1,
		"objective": "Learn a research skill level",
		"hint": "At Outpost 01, press {pause_game} and open RESEARCH. Select any unlocked skill and learn it. Each level costs a research point plus refined Skylab stock.",
		"briefing": "Sato here. I have been through the garrison recorder and the Sentinel wreck you left me. Their shields adapt to what hits them. Field intelligence becomes research points, and with Brell's refined stock we can build countermeasures into your ship. Bring the ship home and open the Research console. Pick whichever skill suits you.",
		"done": "Installed and calibrated, and it applies the moment you launch. Higher levels and later skills need Promerium and Seprom, which Brell's deeper refineries make from Prometid and Duranium. Hunts and operations like this one earn more points.",
	},
	{
		"id": "field_test", "title": "Field Test", "contact": "vance", "type": "kill",
		"kind": "Scout", "required": 3,
		"credits": 2500, "research": 0,
		"objective": "Destroy Scouts with your upgraded ship",
		"hint": "{cycle_target} locks a target and {fire} toggles lasers. Kills for a hunting contract count here too.",
		"briefing": "Vance. Sato says your ship has new tricks. A lab bench is not a battlefield. Take it out and prove it on three Scouts.",
		"done": "Confirmed kills. Command will want more of that.",
	},
	{
		"id": "raw_supply", "title": "Raw Supply", "contact": "brell", "type": "lab_upgrade",
		"kind": "collector", "required": 1,
		"credits": 1500, "research": 0,
		"objective": "Start an ore collector upgrade in Skylab",
		"hint": "In SKYLAB, select a Prometium, Endurium or Terbium collector and press Build. If Basic is still building, wait for its timer or press Finish now.",
		"briefing": "Brell. The Basic core should be finished by now, which lifts the ceiling for everything else. More raw ore means faster refining, so raise one of the collectors.",
		"done": "Collector upgrade is building. Each level costs credits and raw ore and takes longer than the last, so plan ahead.",
	},
	{
		"id": "supply_line", "title": "Supply Line", "contact": "brell", "type": "lab_ship",
		"required": 1,
		"credits": 1500, "research": 0,
		"objective": "Send a Skylab shipment to your ship",
		"hint": "In SKYLAB, select Transport, enter an amount of any stock and press Send. It lands in your active ship's cargo, so leave room.",
		"briefing": "One more thing. Stock in the lab does you no good out there. The Transport module ships anything in storage, raw or refined, straight into your hold. Send yourself a load: sell it, refine it aboard or hand it in for jobs like mine.",
		"done": "Shipment is on its way. It arrives in the ship you sent it from, even if you switch hulls.",
	},
	{
		"id": "shield_samples", "title": "Shield Samples", "contact": "sato", "type": "kill",
		"kind": "Sentinel", "required": 1,
		"credits": 3000, "research": 2,
		"objective": "Destroy a Sentinel",
		"hint": "Sentinels carry strong shields. Combine lasers with {rocket} rockets; your research applies in every fight.",
		"briefing": "One more reading. I need to watch a Sentinel shield collapse against your countermeasures. Bring one down and my sensors will do the rest.",
		"done": "There it is. Their shield pattern shifts with every hit, but it is a pattern. With enough research we can stay ahead of it.",
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
	"industry_online": [
		[["pause_game"], "Menu, then SKYLAB"],
		[["contracts"], "Quests: reread the briefing"],
	],
	"countermeasures": [
		[["sector_map"], "Map: select Outpost 01"],
		[["autopilot"], "Autopilot home"],
		[["pause_game"], "Menu, then RESEARCH"],
	],
	"raw_supply": [
		[["pause_game"], "Menu, then SKYLAB"],
		[["contracts"], "Quests: reread the briefing"],
	],
	"field_test": [
		[["cycle_target"], "Lock an alien"],
		[["fire"], "Toggle automatic lasers"],
		[["contracts"], "Take a hunt for the same kills"],
	],
	"supply_line": [
		[["pause_game"], "Menu, then SKYLAB > Transport"],
		[["station_shop"], "Shop: sell delivered cargo"],
	],
	"shield_samples": [
		[["rocket"], "Fire a single rocket"],
		[["launcher"], "Load, then fire Hellstorm"],
		[["repair"], "Repair between fights"],
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
		return {"story": {"step": story["step"], "progress": progress}, "credits": 0, "research": 0, "lab": {}, "finished": {}}
	return {"story": {"step": int(story["step"]) + 1, "progress": 0}, "credits": step["credits"], "research": step["research"], "lab": step.get("lab", {}), "finished": step}


## Remaining step rewards of the current chapter for pilots who skip it.
static func skip(story: Dictionary) -> Dictionary:
	var credits := 0
	var research := 0
	var lab := {}
	var finish := chapter_end(chapter(int(story["step"])))
	for index in range(int(story["step"]), finish):
		credits += int(STEPS[index]["credits"])
		research += int(STEPS[index]["research"])
		for resource: String in STEPS[index].get("lab", {}):
			lab[resource] = int(lab.get(resource, 0)) + int(STEPS[index]["lab"][resource])
	return {"story": {"step": finish, "progress": 0}, "credits": credits, "research": research, "lab": lab, "finished": {}}


## The chapter containing a step index; a finished story belongs to the last chapter.
static func chapter(index: int) -> int:
	var found := 0
	for number in CHAPTERS.size():
		if int(CHAPTERS[number]["start"]) <= mini(index, STEPS.size() - 1):
			found = number
	return found


static func chapter_start(number: int) -> int:
	return CHAPTERS[number]["start"]


static func chapter_end(number: int) -> int:
	return STEPS.size() if number + 1 >= CHAPTERS.size() else int(CHAPTERS[number + 1]["start"])


## Pay an `advance` or `skip` result into a copied pilot record and save the new
## position. Credits saturate at the wallet cap; lab stock stops at storage capacity.
static func pay(pilot: Dictionary, result: Dictionary) -> void:
	pilot["credits"] = mini(PilotStore.MAX_CREDITS, int(pilot["credits"]) + int(result["credits"]))
	Research.add_points(pilot["equipment"], result["research"])
	var lab: Dictionary = pilot["skylab"]
	var capacities := Skylab.capacities(lab)
	for resource: String in result["lab"]:
		var stock := int(lab["inventory"][resource])
		lab["inventory"][resource] = maxi(stock, mini(capacities[resource], stock + int(result["lab"][resource])))
	pilot["equipment"]["story"] = result["story"]


## Count a station or Skylab event inside the caller's transaction.
static func record(pilot: Dictionary, type: String, kind: String = "") -> void:
	var result := advance(state(pilot["equipment"]), type, 1, kind)
	if not result.is_empty():
		pay(pilot, result)


## The Skylab command that just succeeded, as a story event.
static func record_lab(pilot: Dictionary, action: String, payload: Dictionary) -> void:
	var module: Variant = payload.get("module", "")
	if action in ["upgrade", "build_instant"]:
		record(pilot, "lab_upgrade", "collector" if Skylab.COLLECTORS.has(module) else str(module))
	elif action in ["ship", "ship_instant"]:
		record(pilot, "lab_ship")


## A confirmation suffix when a transaction also finished a story step.
static func progress_notice(previous: Dictionary, story: Dictionary) -> String:
	if previous.is_empty() or int(story["step"]) != int(previous["step"]) + 1:
		return ""
	var finished: Dictionary = STEPS[int(previous["step"])]
	return " %s complete: %s." % [finished["title"], reward_text(finished["credits"], finished["research"], finished.get("lab", {}))]


static func site(story: Dictionary, map: int) -> Dictionary:
	var step := current(story)
	return step if not step.is_empty() and step["type"] in POSITIONAL and step["map"] == map else {}


static func site_position(step: Dictionary) -> Vector3:
	return SectorMaps.origin(step["map"]) + step["position"]


static func objective(story: Dictionary, scan_seconds: float = 0.0) -> String:
	var step := current(story)
	if step.is_empty():
		return "Story complete."
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


static func reward_text(credits: int, research: int, lab: Dictionary = {}) -> String:
	var text := "+%s CR" % StationShop.credits_text(credits)
	text += (" and +%d research points" % research) if research > 0 else ""
	return text + (" and %s in Skylab" % CargoResources.describe(lab) if not lab.is_empty() else "")


## Transmission after a completed step: its closing line, reward and the next briefing.
static func completion_notice(finished: Dictionary, story: Dictionary) -> String:
	var parts: PackedStringArray = []
	for line: Array in completion_lines(finished, story):
		parts.append("%s: %s" % [CONTACTS[line[0]]["call"], line[1]])
	return "\n".join(parts)


## The same transmission as [contact, text] lines, one per speaker.
static func completion_lines(finished: Dictionary, story: Dictionary) -> Array:
	var closing := "%s %s." % [finished["done"], reward_text(finished["credits"], finished["research"], finished.get("lab", {}))]
	var next := current(story)
	var step := int(story["step"])
	if next.is_empty() or step == chapter_start(chapter(step)):
		closing += " %s complete." % CHAPTERS[chapter(step - 1)]["title"]
	if next.is_empty():
		return [[finished["contact"], closing]]
	if next["contact"] == finished["contact"]:
		return [[finished["contact"], closing + "\n" + next["briefing"]]]
	return [[finished["contact"], closing], [next["contact"], next["briefing"]]]


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
