class_name HuntingContracts
extends RefCounted
## Fixed station trips. Saved runs keep their own objective and reward across tuning changes.

const OFFERS: Dictionary = {
	"scout": {"type": "scout", "required": 3, "reward": 90},
	"sentinel": {"type": "sentinel", "required": 2, "reward": 150},
	"heavy": {"type": "heavy", "required": 1, "reward": 200},
}


static func accept(offer: String) -> Dictionary:
	if not OFFERS.has(offer):
		return {}
	var contract: Dictionary = OFFERS[offer].duplicate()
	contract["run"] = Crypto.new().generate_random_bytes(32).hex_encode()
	contract["progress"] = 0
	return contract


static func valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if value.size() != 5 or not value.get("type") is String or not OFFERS.has(value["type"]):
		return false
	if not value.get("run") is String or not PilotStore.valid_hex(value["run"]):
		return false
	for field in ["required", "reward", "progress"]:
		var number: Variant = value.get(field)
		if not (number is int or number is float) or not is_finite(number) or number != floor(number):
			return false
	return value["required"] >= 1 and value["required"] <= 1000 and value["reward"] >= 1 and value["reward"] <= PilotStore.MAX_CREDITS and value["progress"] >= 0 and value["progress"] <= value["required"]


static func after_kill(contract: Dictionary, alien_type: String) -> Dictionary:
	var next := contract.duplicate()
	if not next.is_empty() and next["type"] == alien_type:
		next["progress"] = mini(next["required"], next["progress"] + 1)
	return next


static func ready(contract: Dictionary) -> bool:
	return not contract.is_empty() and contract["progress"] == contract["required"]


static func objective(contract: Dictionary) -> String:
	return "%s hunt: %d / %d  |  %d CR%s" % [str(contract["type"]).capitalize(), contract["progress"], contract["required"], contract["reward"], "  |  READY TO CLAIM" if ready(contract) else ""]
