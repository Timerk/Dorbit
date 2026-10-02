class_name HuntingContracts
extends RefCounted
## Concurrent hunts. Saved runs keep their own objective and reward across tuning changes.

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


static func valid_collection(value: Variant) -> bool:
	if not value is Dictionary or value.size() > OFFERS.size():
		return false
	for kind: Variant in value:
		if not kind is String or not OFFERS.has(kind) or not valid(value[kind]) or value[kind].is_empty() or value[kind]["type"] != kind:
			return false
	return true


# Clear paid runs in the same transaction as their rewards. Full wallets keep pending runs.
static func settle(contracts: Dictionary, credits: int) -> Dictionary:
	var next := contracts.duplicate(true)
	var paid: Array[String] = []
	var reward := 0
	for kind: String in OFFERS:
		if next.has(kind) and ready(next[kind]) and credits <= PilotStore.MAX_CREDITS - int(next[kind]["reward"]):
			var amount := int(next[kind]["reward"])
			credits += amount
			reward += amount
			paid.append(kind.capitalize())
			next.erase(kind)
	return {"contracts": next, "credits": credits, "reward": reward, "paid": paid}


static func ready(contract: Dictionary) -> bool:
	return not contract.is_empty() and contract["progress"] == contract["required"]


static func objective(contract: Dictionary) -> String:
	return "%s hunt: %d / %d  |  %d CR%s" % [str(contract["type"]).capitalize(), contract["progress"], contract["required"], contract["reward"], "  |  WALLET FULL / REWARD PENDING" if ready(contract) else ""]
