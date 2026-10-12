class_name Ui
extends CanvasLayer
## HUD plus every menu card. Builds its own widgets in code and talks to the match
## controller only through signals and a handful of setters.

signal bot_requested
signal local_requested
signal join_requested(address: String)
signal pause_requested
signal resume_requested
signal leave_requested
signal rematch_requested
signal disconnect_requested
signal create_room_requested(room_name: String)
signal join_room_requested(room_id: int)
signal quick_join_requested
signal refresh_rooms_requested
signal skins_changed           ## Prefs.skins changed (the board behind the menus shows the new look)

const COL_ACCENT := Color("e9f48b")
const COL_TEXT := Color("f5f2df")
const COL_MUTED := Color("bbd0d0")
const COL_DIM := Color("8cafb1")
const COL_X := Color("ffad92")
const COL_O := Color("9ed5ff")

var minimap: Minimap

var _hud: Control
var _turn: Label
var _gauge: WindGauge
var _brand_sub: Label
var _pickers: Array = []   ## difficulty pickers (menu + rooms), kept in sync
var _ammo_panels: Array[PanelContainer] = []
var _ammo_labels: Array[Label] = []
var _timer: Label
var _notice: Label
var _crosshair: Label
var _compass: Label
var _flash: ColorRect
var _overlay: ColorRect
var _cards: Dictionary = {}
var _current := ""
var _name_edit: LineEdit
var _menu_msg: Label
var _settings_back := "menu"
var _sens_label: Label
var _vol_label: Label
var _sens_slider: HSlider
var _vol_slider: HSlider
var _rooms_empty: Label
var _rooms_scroll: ScrollContainer
var _ip_edit: LineEdit
var _join_status: Label
var _rooms_status: Label
var _room_list: VBoxContainer
var _room_name_edit: LineEdit
var _wait_text: Label
var _over_title: Label
var _over_sub: Label
var _rematch_btn: Button
var _warning_back := "menu"
var _hide_check: CheckBox
var _loadout_next := "bot"   ## what the skin screen's start button leads to: bot | local | lan
var _loadout_go: Button
var _skin_buttons := {}      ## kind -> Array of {id, button, label}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_all()
	if Prefs.hide_warning:
		show_menu()
	else:
		show_warning("menu")


func _build_all() -> void:
	_cards.clear()
	_pickers.clear()
	_ammo_panels.clear()
	_ammo_labels.clear()
	_skin_buttons.clear()
	_build_hud()
	set_difficulty(Prefs.difficulty)
	_build_overlay()
	_build_menu_card()
	_build_loadout_card()
	_build_join_card()
	_build_howto_card()
	_build_settings_card()
	_build_warning_card()
	_build_rooms_card()
	_build_wait_card()
	_build_pause_card()
	_build_over_card()


## Throws the whole interface away and builds it again, so every text is re-read in the current
## language. Used when the language changes; card is the screen to come back to.
func rebuild(card: String) -> void:
	var hud_visible := _hud.visible
	var warn_back := _warning_back
	for n: Node in [_hud, _overlay, _crosshair, _compass, _flash]:
		n.queue_free()
	_build_all()
	set_hud_visible(hud_visible)
	match card:
		"settings":
			show_settings(_settings_back)
		"loadout":
			show_loadout(_loadout_next)
		"warning":
			show_warning(warn_back)
		"":
			hide_overlay()
		_:
			_show_card(card)


# --- public API -----------------------------------------------------------------------------

func overlay_open() -> bool:
	return _overlay.visible


func current_card() -> String:
	return _current if _overlay.visible else ""


func hide_overlay() -> void:
	_overlay.visible = false
	_current = ""


func show_menu(message: String = "") -> void:
	_menu_msg.text = message
	_menu_msg.visible = message != ""
	_show_card("menu")


## The skin screen shown before a match; next is where its start button leads (bot | local | lan).
func show_loadout(next: String) -> void:
	_loadout_next = next
	_loadout_go.text = Loc.t("Tiếp tục") if next == "lan" else Loc.t("Bắt đầu trận")
	_refresh_skin_buttons()
	_show_card("loadout")


func show_join() -> void:
	_join_status.text = ""
	if _ip_edit.text == "":
		_ip_edit.text = Net.default_address()
	_show_card("join")


func show_rooms() -> void:
	_rooms_status.text = ""
	_rooms_status.visible = false
	_show_card("rooms")


func set_rooms_status(text: String) -> void:
	_rooms_status.text = text
	_rooms_status.visible = text != ""


func set_room_list(list: Array) -> void:
	for c in _room_list.get_children():
		c.queue_free()
	_rooms_empty.visible = list.is_empty()
	# Rooms you can join come first.
	var sorted_list := list.duplicate()
	sorted_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) < int(b["count"]))
	for room: Dictionary in sorted_list:
		_room_list.add_child(_room_row(room))
	_rooms_scroll.custom_minimum_size.y = clampf(list.size() * 62.0, 0.0, 250.0)


## One room = one plain row: name, who is in it, and a single action on the right.
func _room_row(room: Dictionary) -> Control:
	var count: int = room["count"]
	var open := count < 2
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(_label(room["name"] if room["name"] != "" else Loc.t("Phòng #%d") % int(room["id"]), 16))
	var who := ", ".join(PackedStringArray(room["names"]))
	var level := Loc.t(Rules.DIFF_NAMES[clampi(int(room.get("diff", 1)), 0, 3)])
	var state := Loc.t("%s · %d/2 người") % [level, count]
	if room["playing"]:
		state = Loc.t("%s · đang đấu") % level
	elif who != "":
		state = Loc.t("%s · %s đang chờ") % [level, who]
	info.add_child(_label(state, 12, COL_DIM))
	h.add_child(info)
	var b := _button(Loc.t("Vào") if open else Loc.t("Đầy"), open)
	b.custom_minimum_size = Vector2(84, 38)
	b.disabled = not open
	var id: int = room["id"]
	b.pressed.connect(func() -> void: join_room_requested.emit(id))
	h.add_child(b)
	return row


func set_join_status(text: String) -> void:
	_join_status.text = text


func show_waiting(text: String) -> void:
	_wait_text.text = text
	_show_card("wait")


## Developer helper (--card=NAME): jump straight to a screen, with sample rooms for the lobby.
func debug_card(card_name: String) -> void:
	if card_name == "warning":
		show_warning("menu")
	elif card_name == "settings":
		show_settings("menu")
	elif card_name == "loadout":
		show_loadout("bot")
	elif card_name == "rooms":
		set_room_list([
			{"id": 1, "name": "Phòng của Minh", "count": 1, "names": ["Minh"], "playing": false},
			{"id": 2, "name": "Cao thủ", "count": 2, "names": ["An", "Bình"], "playing": true},
			{"id": 3, "name": "Phòng của Lan", "count": 1, "names": ["Lan"], "playing": false}])
		show_rooms()
	elif card_name == "pause":
		show_pause(false)
	elif card_name == "over":
		show_over("manhtien chiến thắng!", "5 dấu X liên tiếp.", true)
	elif card_name == "wait":
		show_waiting("Phòng «Phòng của Minh». Bạn là đội X. Đang chờ đối thủ vào phòng…")
	elif card_name == "join":
		show_join()
		set_join_status("Kết nối thất bại. Kiểm tra IP, cùng mạng Wi-Fi, và server đã chạy chưa.")
	elif _cards.has(card_name):
		_show_card(card_name)


func show_warning(back_to: String) -> void:
	_warning_back = back_to
	_hide_check.button_pressed = Prefs.hide_warning
	_show_card("warning")


func show_settings(back_to: String) -> void:
	_settings_back = back_to
	_sens_slider.value = Prefs.sensitivity
	_vol_slider.value = Prefs.volume
	_sens_label.text = "%.2f×" % Prefs.sensitivity
	_vol_label.text = "%d%%" % roundi(Prefs.volume * 100.0)
	_show_card("settings")


func show_pause(online: bool) -> void:
	var sub: Label = _cards["pause"].get_meta("sub")
	sub.text = Loc.t("Trận đấu vẫn tiếp tục trong lúc bạn tạm dừng.") if online else Loc.t("Trò chơi đã tạm dừng.")
	_show_card("pause")


func show_over(title: String, sub: String, can_rematch: bool) -> void:
	_over_title.text = title
	_over_sub.text = sub
	_rematch_btn.visible = can_rematch
	_show_card("over")


func set_hud_visible(v: bool) -> void:
	_hud.visible = v
	if not v:
		_compass.text = ""
	_crosshair.visible = v


func set_env(view: Dictionary) -> void:
	_gauge.set_env(view)


func set_compass(text: String) -> void:
	_compass.text = text


func set_difficulty(level: int) -> void:
	_brand_sub.text = "%d × %d · %s" % [Rules.N, Rules.N, Loc.t(Rules.DIFF_NAMES[level]).to_upper()]


func set_hud(turn_text: String, turn_color: Color, time_text: String, time_urgent: bool, notice: String) -> void:
	_turn.text = turn_text
	_turn.add_theme_color_override("font_color", turn_color)
	_timer.text = time_text
	_timer.add_theme_color_override("font_color", Color("ff8a70") if time_urgent else COL_TEXT)
	_notice.text = notice


func flash() -> void:
	_flash.color.a = 0.25
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if not _overlay.visible:
				pause_requested.emit()
			elif _current == "pause":
				resume_requested.emit()
			get_viewport().set_input_as_handled()


# --- widget helpers ---------------------------------------------------------------------------

func _label(text: String, size: int = 16, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.1, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _para(text: String, color: Color = COL_MUTED, size: int = 15, width: float = 480.0) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func _button(text: String, primary: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 15)
	_style_button(b, primary)
	return b


func _style_button(b: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_ACCENT if primary else Color(1, 1, 1, 0.1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.18)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var off := normal.duplicate() as StyleBoxFlat
	off.bg_color = Color(1, 1, 1, 0.05)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.38))
	var fc := Color("20382c") if primary else COL_TEXT
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, fc)


## Four-way difficulty chooser with a one-line explanation of the selected level.
## The choice is shared (Prefs.difficulty) by offline games and rooms you create.
func _build_picker(parent: Control, width: float) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var buttons: Array[Button] = []
	for i in Rules.DIFF_NAMES.size():
		var b := _button(Loc.t(Rules.DIFF_NAMES[i]), false)
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void:
			Prefs.difficulty = i
			Prefs.save()
			set_difficulty(i)
			_refresh_pickers())
		row.add_child(b)
		buttons.append(b)
	col.add_child(row)
	var desc := _para("", COL_DIM, 12, width)
	col.add_child(desc)
	parent.add_child(col)
	_pickers.append({"buttons": buttons, "desc": desc})
	_refresh_pickers()


func _refresh_pickers() -> void:
	for pk: Dictionary in _pickers:
		var buttons: Array = pk["buttons"]
		for i in buttons.size():
			_style_button(buttons[i], i == Prefs.difficulty)
		(pk["desc"] as Label).text = Loc.t(Rules.DIFF_DESC[Prefs.difficulty])


func _panel_style(alpha: float = 0.9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.173, 0.196, alpha)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _make_card(card_name: String, width: float = 0.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	var sb := _panel_style(0.95)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(36)
	sb.border_color = Color(1, 1, 1, 0.2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_overlay.get_child(0).add_child(panel)
	_cards[card_name] = panel
	return box


## Title row for sub-screens: a clear way back on the left, the screen's name beside it.
func _header(box: VBoxContainer, title: String, back_text: String, back: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var b := _button(back_text, false)
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(back)
	row.add_child(b)
	var t := _label(title, 30)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	box.add_child(row)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)


## A big, readable choice: bold title plus a one-line explanation.
func _mode_button(title: String, desc: String, primary: bool) -> Button:
	var b := _button("", primary)
	b.custom_minimum_size = Vector2(0, 84)
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", 22)
	inner.add_theme_constant_override("margin_right", 22)
	inner.add_theme_constant_override("margin_top", 12)
	inner.add_theme_constant_override("margin_bottom", 12)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	var dark := Color("20382c")
	var t := _label(title, 19, dark if primary else COL_TEXT)
	t.add_theme_constant_override("outline_size", 0)
	var d := _label(desc, 13, Color("3c5a40") if primary else COL_MUTED)
	d.add_theme_constant_override("outline_size", 0)
	col.add_child(t)
	col.add_child(d)
	inner.add_child(col)
	b.add_child(inner)
	return b


func _show_card(card_name: String) -> void:
	for k: String in _cards:
		_cards[k].visible = (k == card_name)
	_current = card_name
	_overlay.visible = true


func _style_edit(e: LineEdit) -> void:
	e.custom_minimum_size = Vector2(0, 42)
	e.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("29454b")
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", Color.WHITE)


# --- building the screens -----------------------------------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 24)
	_hud.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# top row
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var brand := VBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_child(_label("ROCKET CARO.", 25, COL_TEXT))
	_brand_sub = _label("", 11, COL_MUTED)
	brand.add_child(_brand_sub)
	top.add_child(brand)
	var turn_panel := PanelContainer.new()
	turn_panel.add_theme_stylebox_override("panel", _panel_style())
	turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn = _label("", 18)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge = WindGauge.new()
	tv.add_child(_turn)
	tv.add_child(_gauge)
	turn_panel.add_child(tv)
	top.add_child(turn_panel)
	var time_wrap := Control.new()
	time_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(time_wrap)
	var time_panel := PanelContainer.new()
	time_panel.add_theme_stylebox_override("panel", _panel_style())
	time_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var tbox := VBoxContainer.new()
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tlabel := _label(Loc.t("THỜI GIAN"), 11, COL_MUTED)
	tlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer = _label("15", 30)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tbox.add_child(tlabel)
	tbox.add_child(_timer)
	time_panel.add_child(tbox)
	time_wrap.add_child(time_panel)
	time_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	# bottom row
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bottom)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap = Minimap.new()
	left.add_child(minimap)
	left.add_child(_label(Loc.t("Chuột ngắm · Click/Space bắn\n1-4 chọn đạn · Chuột phải/Z zoom\nEsc tạm dừng"), 12, COL_DIM))
	bottom.add_child(left)
	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_END
	center.add_theme_constant_override("separation", 10)
	center.add_child(_build_ammo_bar())
	_notice = _label("", 18)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_notice)
	bottom.add_child(center)
	var right := Control.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pause_btn := _button(Loc.t("Tạm dừng"), false)
	pause_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pause_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	right.add_child(pause_btn)
	bottom.add_child(right)

	_crosshair = _label("+", 30)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_crosshair.add_theme_color_override("font_shadow_color", Color.BLACK)
	_crosshair.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_crosshair)

	# Points toward the board when you have been spun away from it.
	_compass = _label("", 22, COL_ACCENT)
	_compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -240.0
	_compass.offset_right = 240.0
	_compass.offset_top = 144.0
	_compass.offset_bottom = 176.0
	add_child(_compass)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.91, 0.57, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	set_hud_visible(false)


const AMMO_NAMES := ["1 · Đạn thường", "2 · Đạn tẩy", "3 · Đạn đuổi", "4 · Đạn băng"]


func _build_ammo_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	for name_key in AMMO_NAMES:
		var name_text := Loc.t(name_key)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := _label(name_text, 14)
		panel.add_child(label)
		row.add_child(panel)
		_ammo_panels.append(panel)
		_ammo_labels.append(label)
	set_ammo(0, [true, true, true, true], [false, false, false, false], false, false)
	return row


## selected: Rules.AMMO_*. available[i]: can be fired right now; used[i]: spent this match.
## with_freeze: the freeze rocket only exists on insane, so its slot is hidden otherwise.
func set_ammo(selected: int, available: Array, used: Array, shown: bool, with_freeze: bool) -> void:
	_ammo_panels[0].get_parent().visible = shown
	_ammo_panels[Rules.AMMO_FREEZE].visible = with_freeze
	for i in _ammo_panels.size():
		var sb := _panel_style(0.9)
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		var usable: bool = available[i]
		if i == selected:
			sb.bg_color = Color(0.36, 0.42, 0.16, 0.95)
			sb.set_border_width_all(2)
			sb.border_color = COL_ACCENT
		_ammo_panels[i].add_theme_stylebox_override("panel", sb)
		var why := "" if usable else (Loc.t(" (đã dùng)") if used[i] else Loc.t(" (chưa dùng được)"))
		_ammo_labels[i].text = Loc.t(AMMO_NAMES[i]) + why
		_ammo_labels[i].add_theme_color_override("font_color", COL_TEXT if usable else Color(1, 1, 1, 0.35))


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.043, 0.125, 0.153, 0.66)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)


func _build_menu_card() -> void:
	var box := _make_card("menu", 900)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	box.add_child(cols)

	# left: identity
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	left.add_child(_label(Loc.t("BẮN ROCKET · XẾP %d Ô") % Rules.WIN_LEN, 11, COL_ACCENT))
	left.add_child(_label("Rocket Caro", 54))
	left.add_child(_para(Loc.t("Bàn cờ %d×%d khổng lồ giữa hai bờ sông. Bắn rocket vào ô trống để đặt dấu; gió và trọng lực sẽ làm rocket lệch khỏi tâm ngắm.") % [Rules.N, Rules.N], COL_MUTED, 15, 330))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(_label(Loc.t("TÊN CỦA BẠN"), 11, COL_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = Loc.t("Nhập tên hiển thị")
	_name_edit.text_changed.connect(func(_t: String) -> void: _commit_name())
	_style_edit(_name_edit)
	left.add_child(_name_edit)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 8)
	var how := _button(Loc.t("Cách chơi"), false)
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.pressed.connect(func() -> void: _show_card("howto"))
	var cfg := _button(Loc.t("Cài đặt"), false)
	cfg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cfg.pressed.connect(func() -> void: show_settings("menu"))
	small.add_child(how)
	small.add_child(cfg)
	left.add_child(small)

	# right: pick a mode
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 460
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	right.add_child(_label(Loc.t("ĐỘ KHÓ"), 11, COL_DIM))
	_build_picker(right, 460)
	right.add_child(_label(Loc.t("CHỌN CHẾ ĐỘ CHƠI"), 11, COL_DIM))
	_menu_msg = _para("", Color("ffb199"), 14, 460)
	right.add_child(_menu_msg)
	# Every mode goes through the skin screen first.
	var lan := _mode_button(Loc.t("Chơi mạng LAN"), Loc.t("Vào sảnh phòng, đấu với bạn bè cùng Wi-Fi."), true)
	lan.pressed.connect(func() -> void:
		_commit_name()
		show_loadout("lan"))
	right.add_child(lan)
	var bot := _mode_button(Loc.t("Chơi với Bot"), Loc.t("Luyện tập một mình. Bot biết dùng cả đạn đặc biệt."), false)
	bot.pressed.connect(func() -> void:
		_commit_name()
		show_loadout("bot"))
	right.add_child(bot)
	var local := _mode_button(Loc.t("2 người · cùng máy"), Loc.t("Hai người thay phiên nhau trên một màn hình."), false)
	local.pressed.connect(func() -> void:
		_commit_name()
		show_loadout("local"))
	right.add_child(local)


## Skins chosen before a match. Everything is saved at once (Prefs.skins) and the board behind
## the menu changes as you pick.
func _build_loadout_card() -> void:
	var box := _make_card("loadout", 760)
	box.add_theme_constant_override("separation", 8)
	(_cards["loadout"] as PanelContainer).get_theme_stylebox("panel").content_margin_top = 24
	(_cards["loadout"] as PanelContainer).get_theme_stylebox("panel").content_margin_bottom = 24
	_header(box, Loc.t("Chọn skin"), Loc.t("Quay lại"), func() -> void: show_menu())
	box.add_child(_para(Loc.t("Bàn cờ chỉ mình bạn nhìn thấy. Dấu trên bàn, hiệu ứng nổ và vệt đường bay thì đối thủ cũng thấy (dấu của hai đội cùng kiểu nhưng khác màu)."), COL_MUTED, 13, 688))
	for kind in Skins.KINDS:
		box.add_child(_label(Loc.t(Skins.KIND_NAMES[kind]).to_upper(), 11, COL_DIM))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var entries: Array = []
		for s: Dictionary in Skins.list(kind):
			var b := _button("", false)
			b.custom_minimum_size = Vector2(0, 80)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var inner := VBoxContainer.new()
			inner.set_anchors_preset(Control.PRESET_FULL_RECT)
			inner.offset_left = 8
			inner.offset_right = -8
			inner.offset_top = 8
			inner.offset_bottom = -6
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_theme_constant_override("separation", 4)
			var sw := SkinSwatch.new(kind, s["id"])
			sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
			inner.add_child(sw)
			var l := _label(Loc.t(s["name"]), 13)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_constant_override("outline_size", 0)
			inner.add_child(l)
			b.add_child(inner)
			var id: String = s["id"]
			b.pressed.connect(func() -> void:
				Prefs.skins[kind] = id
				Prefs.save()
				_refresh_skin_buttons()
				skins_changed.emit())
			row.add_child(b)
			entries.append({"id": id, "button": b, "label": l})
		_skin_buttons[kind] = entries
		box.add_child(row)
	_loadout_go = _button(Loc.t("Bắt đầu trận"))
	_loadout_go.custom_minimum_size = Vector2(0, 54)
	_loadout_go.add_theme_font_size_override("font_size", 18)
	_loadout_go.pressed.connect(func() -> void:
		if _loadout_next == "lan":
			show_join()
		elif _loadout_next == "local":
			local_requested.emit()
		else:
			bot_requested.emit())
	box.add_child(_loadout_go)
	_refresh_skin_buttons()


func _refresh_skin_buttons() -> void:
	for kind: String in _skin_buttons:
		for e: Dictionary in _skin_buttons[kind]:
			var on: bool = Prefs.skins[kind] == e["id"]
			_style_button(e["button"], on)
			(e["label"] as Label).add_theme_color_override("font_color", Color("20382c") if on else COL_TEXT)


func _commit_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "":
		Net.player_name = n
		Prefs.player_name = n
		Prefs.save()


func _build_join_card() -> void:
	var box := _make_card("join", 620)
	_header(box, Loc.t("Chơi mạng LAN"), Loc.t("Quay lại"), func() -> void: show_menu())
	if Net.on_itch():
		box.add_child(_para(Loc.t("Trang itch.io chỉ lưu file game, không có máy chủ trận đấu. Để chơi mạng, nhập địa chỉ một máy chủ Rocket Caro có HTTPS, dạng wss://ten-mien.com (xem README). Không có máy chủ thì hãy chơi với Bot hoặc 2 người cùng máy."), Color("ffd9a0"), 14, 548))
	else:
		box.add_child(_para(Loc.t("Nhập địa chỉ máy chủ, là máy đang chạy ./play_lan.sh. Nếu bạn mở game từ trang web của máy chủ thì địa chỉ đã được điền sẵn."), COL_MUTED, 14, 548))
	box.add_child(_label(Loc.t("ĐỊA CHỈ MÁY CHỦ"), 11, COL_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.23"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_edit(_ip_edit)
	var go := _button(Loc.t("Kết nối"))
	var connect_now := func() -> void:
		var addr := _ip_edit.text.strip_edges()
		if addr != "":
			join_requested.emit(addr)
	go.pressed.connect(connect_now)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: connect_now.call())
	row.add_child(_ip_edit)
	row.add_child(go)
	box.add_child(row)
	_join_status = _para("", COL_ACCENT, 14, 548)
	box.add_child(_join_status)


func _build_rooms_card() -> void:
	var box := _make_card("rooms", 560)
	_header(box, Loc.t("Chọn phòng"), Loc.t("Thoát"), func() -> void: disconnect_requested.emit())
	_rooms_status = _para("", Color("ffb199"), 14, 488)
	_rooms_status.visible = false
	box.add_child(_rooms_status)

	# The one thing most people want: get into a game right now.
	var quick := _button(Loc.t("Chơi ngay"), true)
	quick.custom_minimum_size = Vector2(0, 58)
	quick.add_theme_font_size_override("font_size", 18)
	quick.pressed.connect(func() -> void: quick_join_requested.emit())
	box.add_child(quick)
	box.add_child(_para(Loc.t("Tự ghép với người đang chờ, hoặc mở phòng mới (theo độ khó chọn bên dưới) nếu chưa có ai."), COL_DIM, 12, 488))

	box.add_child(_label(Loc.t("PHÒNG ĐANG MỞ"), 11, COL_DIM))
	_rooms_empty = _para(Loc.t("Chưa có phòng nào."), COL_DIM, 14, 488)
	box.add_child(_rooms_empty)
	_rooms_scroll = ScrollContainer.new()
	_rooms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_room_list = VBoxContainer.new()
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list.add_theme_constant_override("separation", 8)
	_rooms_scroll.add_child(_room_list)
	box.add_child(_rooms_scroll)

	box.add_child(_label(Loc.t("HOẶC TẠO PHÒNG RIÊNG · ĐỘ KHÓ"), 11, COL_DIM))
	_build_picker(box, 488)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_room_name_edit = LineEdit.new()
	_room_name_edit.placeholder_text = Loc.t("Tên phòng (không bắt buộc)")
	_room_name_edit.max_length = 24
	_room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_edit(_room_name_edit)
	var create := _button(Loc.t("Tạo"), false)
	create.custom_minimum_size = Vector2(84, 42)
	var do_create := func() -> void:
		create_room_requested.emit(_room_name_edit.text)
		_room_name_edit.text = ""
	create.pressed.connect(do_create)
	_room_name_edit.text_submitted.connect(func(_t: String) -> void: do_create.call())
	row.add_child(_room_name_edit)
	row.add_child(create)
	box.add_child(row)


func _build_howto_card() -> void:
	var box := _make_card("howto", 720)
	_header(box, Loc.t("Cách chơi"), Loc.t("Quay lại"), func() -> void: show_menu())
	var sections := [
		[Loc.t("MỤC TIÊU"), Loc.t("Bắn rocket vào ô trống để đặt dấu của bạn. Ai xếp được %d dấu liên tiếp (ngang, dọc hoặc chéo) trước thì thắng.") % Rules.WIN_LEN],
		[Loc.t("MỖI LƯỢT"), Loc.t("Có %d giây và một phát bắn. Bắn hụt, trúng cây/đá, trúng ô đã có dấu hoặc hết giờ đều mất lượt.") % int(Rules.TURN_TIME)],
		[Loc.t("GIÓ, TRỌNG LỰC, ĐỘ DỐC"), Loc.t("Bảng ở giữa trên cho biết điều kiện lượt này theo màn hình của bạn: mũi tên vàng là gió, mũi tên đỏ là trọng lực, hình bàn nghiêng là độ dốc. Hãy ngắm bù ngược lại: gió đẩy sang phải thì ngắm lệch sang trái, và ngắm cao hơn một chút.")],
		[Loc.t("ĐỘ KHÓ"), Loc.t("Bình thường: không gió, không trọng lực.\nKhó: có gió và trọng lực.\nRất khó: bàn cờ nghiêng (dốc) và xoay, đổi mỗi lượt, còn bạn bị đưa đi vòng quanh bàn cờ liên tục trong lúc ngắm: có lúc thấy bàn chính diện, có lúc chỉ thấy cạnh bàn hoặc mặt sau. Chờ bàn dừng rồi mới bắn được.\nSiêu khó: gió, trọng lực, và bàn cờ lật, quay liên tục rất nhanh. Rocket bay mất khoảng 1 giây nên phải bắn đón đầu: hãy nhìn hình bàn quay trên bảng điều kiện và chọn lúc ô muốn bắn sắp tới đúng chỗ.")],
		[Loc.t("ĐẠN ĐẶC BIỆT (mỗi loại 1 lần mỗi ván)"), Loc.t("Phím 2, đạn tẩy: bắn trúng dấu của đối thủ để xóa nó.\nPhím 3, đạn đuổi: sau khi bắn, di chuột để lái rocket về ô muốn trúng.\nPhím 4, đạn băng (chỉ ở Siêu khó): trúng bàn cờ là bàn đứng yên ngay tại tư thế lúc trúng trong %d lượt, không đặt dấu. Chọn đúng lúc bắn: bàn có thể đông cứng ở góc rất khó bắn.\nPhím 1 quay về đạn thường.") % Rules.FREEZE_TURNS],
		[Loc.t("ĐIỀU KHIỂN"), Loc.t("Chuột ngắm · click hoặc Space bắn · chuột phải hoặc Z zoom · 1-4 chọn đạn · Esc tạm dừng. Bạn không tự di chuyển được.")],
	]
	for sec in sections:
		box.add_child(_label(sec[0], 11, COL_ACCENT))
		box.add_child(_para(sec[1], COL_TEXT, 14, 648))


func _build_settings_card() -> void:
	var box := _make_card("settings", 560)
	_header(box, Loc.t("Cài đặt"), Loc.t("Quay lại"), func() -> void:
		Prefs.save()
		if _settings_back == "pause":
			_show_card("pause")
		else:
			show_menu())
	box.add_child(_label(Loc.t("NGÔN NGỮ"), 11, COL_DIM))
	_language_row(box)
	box.add_child(_label(Loc.t("ĐỘ NHẠY CHUỘT"), 11, COL_DIM))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 12)
	_sens_slider = _slider(0.3, 2.5, 0.05)
	_sens_label = _label("", 15)
	_sens_label.custom_minimum_size.x = 56
	_sens_slider.value_changed.connect(func(v: float) -> void:
		Prefs.sensitivity = v
		_sens_label.text = "%.2f×" % v)
	r1.add_child(_sens_slider)
	r1.add_child(_sens_label)
	box.add_child(r1)
	box.add_child(_label(Loc.t("ÂM LƯỢNG"), 11, COL_DIM))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 12)
	_vol_slider = _slider(0.0, 1.0, 0.05)
	_vol_label = _label("", 15)
	_vol_label.custom_minimum_size.x = 56
	_vol_slider.value_changed.connect(func(v: float) -> void:
		Prefs.volume = v
		Prefs.apply_volume()
		_vol_label.text = "%d%%" % roundi(v * 100.0))
	r2.add_child(_vol_slider)
	r2.add_child(_vol_label)
	box.add_child(r2)
	box.add_child(_para(Loc.t("Cài đặt được lưu trên máy này."), COL_DIM, 12, 488))
	var warn := _button(Loc.t("Xem lại cảnh báo sức khỏe"), false)
	warn.pressed.connect(func() -> void: show_warning("settings"))
	box.add_child(warn)


## Two-way language chooser; picking one rebuilds the interface in that language.
func _language_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for code: String in Loc.LANGS:
		var b := _button(Loc.LANG_NAMES[code], code == Prefs.language)
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			if code != Prefs.language:
				Prefs.language = code
				Prefs.save()
				rebuild(_current))
		row.add_child(b)
	parent.add_child(row)


## Shown when the game starts (unless switched off) and from Settings: this game can make
## people dizzy, so say so before they play.
func _build_warning_card() -> void:
	var box := _make_card("warning", 720)
	_language_row(box)
	box.add_child(_label(Loc.t("Cảnh báo sức khỏe"), 34, Color("ffd9a0")))
	box.add_child(_para(Loc.t("Rocket Caro là game góc nhìn thứ nhất với nhiều chuyển động mạnh: ở độ khó Rất khó chính bạn bị đưa đi vòng quanh bàn cờ liên tục, và ở độ khó Siêu khó bàn cờ lật, quay liên tục rất nhanh. Những hiệu ứng này có thể gây chóng mặt, buồn nôn, mỏi mắt hoặc đau đầu, đặc biệt với người dễ say tàu xe, người có vấn đề về tiền đình hoặc rối loạn thăng bằng."), COL_TEXT, 15, 648))
	box.add_child(_label(Loc.t("ĐỂ CHƠI AN TOÀN HƠN"), 11, COL_ACCENT))
	for tip in [
		Loc.t("Bắt đầu với độ khó Bình thường hoặc Khó. Rất khó và Siêu khó gây chóng mặt nhiều nhất."),
		Loc.t("Ngồi cách màn hình một khoảng vừa phải, phòng đủ sáng, chơi từng đợt ngắn và nghỉ giữa các ván."),
		Loc.t("Nếu thấy chóng mặt, buồn nôn, hoa mắt hoặc khó chịu, hãy dừng chơi ngay (nhấn Esc), nhìn ra xa và nghỉ ngơi."),
		Loc.t("Nếu bạn có bệnh lý tiền đình, tiền sử động kinh hoặc bệnh lý khác, hãy hỏi ý kiến bác sĩ trước khi chơi."),
	]:
		box.add_child(_para("•  " + tip, COL_MUTED, 14, 648))
	_hide_check = CheckBox.new()
	_hide_check.text = Loc.t("Không hiện lại màn hình này")
	_hide_check.add_theme_font_size_override("font_size", 14)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_hide_check.add_theme_color_override(key, COL_MUTED)
	_hide_check.toggled.connect(func(on: bool) -> void:
		Prefs.hide_warning = on
		Prefs.save())
	box.add_child(_hide_check)
	var go := _button(Loc.t("Tôi đã hiểu, tiếp tục"))
	go.pressed.connect(func() -> void:
		if _warning_back == "settings":
			show_settings(_settings_back)
		else:
			show_menu())
	box.add_child(go)
	if not OS.has_feature("web"):
		var quit := _button(Loc.t("Thoát game"), false)
		quit.pressed.connect(func() -> void: get_tree().quit())
		box.add_child(quit)


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 28)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("29454b")
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = COL_ACCENT
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	return sl


func _build_wait_card() -> void:
	var box := _make_card("wait", 560)
	_header(box, Loc.t("Phòng chơi"), Loc.t("Rời phòng"), func() -> void: leave_requested.emit())
	_wait_text = _para("", COL_TEXT, 16, 488)
	box.add_child(_wait_text)
	box.add_child(_para(Loc.t("Trận sẽ tự bắt đầu khi có người thứ hai vào phòng."), COL_DIM, 13, 488))


func _build_pause_card() -> void:
	var box := _make_card("pause", 460)
	box.add_child(_label(Loc.t("Tạm dừng"), 36))
	var sub := _para("", COL_MUTED, 15, 388)
	box.add_child(sub)
	_cards["pause"].set_meta("sub", sub)
	var resume := _button(Loc.t("Tiếp tục"))
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)
	var cfg := _button(Loc.t("Cài đặt"), false)
	cfg.pressed.connect(func() -> void: show_settings("pause"))
	box.add_child(cfg)
	var leave := _button(Loc.t("Rời trận"), false)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)


func _build_over_card() -> void:
	var box := _make_card("over", 460)
	_over_title = _label("", 40)
	box.add_child(_over_title)
	_over_sub = _para("", COL_MUTED, 15, 388)
	box.add_child(_over_sub)
	_rematch_btn = _button(Loc.t("Chơi lại"))
	_rematch_btn.pressed.connect(func() -> void: rematch_requested.emit())
	box.add_child(_rematch_btn)
	var leave := _button(Loc.t("Rời trận"), false)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)
