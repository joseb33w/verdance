class_name TitleScreen extends CanvasLayer
## VERDANCE title screen — two ways to play (FREE ROAM / CAMPAIGN) + CONTINUE when a save
## exists. Built entirely from anchors + containers so it fills any phone aspect. Sits under
## the AudioManager tap-to-start overlay (layer 200) and above the HUD.

signal mode_chosen(mode: String)      # "campaign" | "free" | "continue"

var _vbox: VBoxContainer
var _continue_btn: Button = null
var _status: Label

const TEAL := Color(0.42, 0.93, 0.85)
const PARCH := Color(0.93, 0.95, 0.9)


func _ready() -> void:
	layer = 30
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.075, 0.065)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# soft vignette band behind the title column
	var band := ColorRect.new()
	band.color = Color(0.05, 0.13, 0.11, 0.75)
	band.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	band.offset_top = -270.0
	band.offset_bottom = 270.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 14)
	center.add_child(_vbox)

	var glyph := Label.new()
	glyph.text = "*"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 34)
	glyph.add_theme_color_override("font_color", TEAL)
	_vbox.add_child(glyph)
	var beat := glyph.create_tween().set_loops()
	beat.tween_property(glyph, "modulate:a", 0.35, 1.1)
	beat.tween_property(glyph, "modulate:a", 1.0, 1.1)

	var title := Label.new()
	title.text = "VERDANCE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", PARCH)
	_vbox.add_child(title)

	var sub := Label.new()
	sub.text = "W A R D E N   O F   T H E   F O U R   R E A C H E S"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", TEAL)
	_vbox.add_child(sub)

	_vbox.add_child(_spacer(26))

	var camp := _menu_button("THE WARDEN'S CAMPAIGN", "Relight the four Beacons")
	camp.pressed.connect(func() -> void: _choose("campaign"))
	_vbox.add_child(camp)
	var free := _menu_button("FREE ROAM", "The whole world, wide open")
	free.pressed.connect(func() -> void: _choose("free"))
	_vbox.add_child(free)

	_vbox.add_child(_spacer(18))
	_status = Label.new()
	_status.text = "Move: left side / WASD    Look: drag right side    JUMP + USE on screen"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.62, 0.72, 0.68))
	_vbox.add_child(_status)


## A save exists — surface CONTINUE above the new-game modes.
func enable_continue(label: String) -> void:
	if _continue_btn != null:
		return
	_continue_btn = _menu_button("CONTINUE  -  " + label, "Resume where you left off")
	_continue_btn.pressed.connect(func() -> void: _choose("continue"))
	_vbox.add_child(_continue_btn)
	_vbox.move_child(_continue_btn, 4)   # right under the subtitle spacer


func set_status(t: String) -> void:
	if _status != null:
		_status.text = t


func _choose(mode: String) -> void:
	AudioManager.play_sfx("ui")
	mode_chosen.emit(mode)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _menu_button(txt: String, hint: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = hint
	b.custom_minimum_size = Vector2(460, 84)
	b.add_theme_font_size_override("font_size", 27)
	b.add_theme_color_override("font_color", PARCH)
	b.add_theme_color_override("font_hover_color", TEAL)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.17, 0.15, 0.92)
	sb.border_color = Color(0.25, 0.55, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.09, 0.25, 0.22, 0.96)
	sbh.border_color = TEAL
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	return b
