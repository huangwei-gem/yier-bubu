class_name Pads
extends RefCounted

const DEADZONE := 0.35

static var _devices: Array[int] = []
static var _scanned := false


# Player 0 drives the first pad that was connected, player 1 the second. Slots are
# resolved by sorted device id so the pairing stays stable across a reconnect.
static func refresh() -> void:
	_devices.clear()
	var connected: Array = Input.get_connected_joypads()
	connected.sort()
	for d: int in connected:
		_devices.append(d)
	_scanned = true


static func device_for(slot: int) -> int:
	if not _scanned:
		refresh()
	return _devices[slot] if slot < _devices.size() else -1


static func axis(slot: int, joy_axis: JoyAxis) -> float:
	var dev := device_for(slot)
	if dev < 0:
		return 0.0
	var v: float = Input.get_joy_axis(dev, joy_axis)
	return 0.0 if absf(v) < DEADZONE else v


static func button(slot: int, index: int) -> bool:
	var dev := device_for(slot)
	return dev >= 0 and Input.is_joy_button_pressed(dev, index)
