@tool
extends RefCounted

# Small builders shared by the dock pages, so every page lays out its labels,
# sliders and buttons the same way.


static func heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	parent.add_child(l)
	return l


static func note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(pressed)
	parent.add_child(b)
	return b


# A labelled slider showing its value. `changed` receives the new value.
# `fmt` turns the value into what the user reads ("10:30", "+0.5 EV").
static func slider(parent: Control, text: String, lo: float, hi: float, step: float,
		changed: Callable, fmt: Callable) -> HSlider:
	var row := VBoxContainer.new()
	var top := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	top.add_child(name_label)
	top.add_child(value_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(func(v): value_label.text = fmt.call(v))
	# Refreshes use show_value, which fires nothing, so any signal is the user.
	s.value_changed.connect(changed)
	s.set_meta("value_label", value_label)
	s.set_meta("fmt", fmt)
	row.add_child(top)
	row.add_child(s)
	parent.add_child(row)
	return s


# Moves a slider to show a stored value without firing its callbacks.
static func show_value(s: HSlider, v: float) -> void:
	s.set_value_no_signal(v)
	(s.get_meta("value_label") as Label).text = (s.get_meta("fmt") as Callable).call(v)


static func option(parent: Control, text: String, items: Array, chosen: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var o := OptionButton.new()
	for item in items:
		o.add_item(str(item))
	o.item_selected.connect(func(i): chosen.call(o.get_item_text(i)))
	row.add_child(l)
	row.add_child(o)
	parent.add_child(row)
	return o


static func select_text(o: OptionButton, text: String) -> void:
	for i in o.item_count:
		if o.get_item_text(i) == text:
			o.select(i)
			return
