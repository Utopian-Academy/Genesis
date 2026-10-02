@tool
extends VBoxContainer

# One slider, and the building immediately looks better. Everything here
# writes through GnEnvironment, which owns the mapping to Godot.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnSun := preload("res://addons/genesis/core/gn_sun.gd")
const GnWeather := preload("res://addons/genesis/core/gn_weather.gd")

var _controls := {}
var _real: CheckBox
var _real_box: VBoxContainer
var _place: OptionButton
var _weather: OptionButton
var _weather_amount: HSlider
var _wet: HSlider
var _puddles: HSlider
var _season: OptionButton
var _hint: Label
var _body: VBoxContainer


func _init() -> void:
	name = "Environment"
	_hint = GnUi.note(self, "Add sun, sky and ground on the Scene tab first.")
	_body = VBoxContainer.new()
	add_child(_body)
	GnUi.heading(_body, "Sun")
	_controls.time_of_day = GnUi.slider(_body, "Time of day", 5.0, 21.0, 0.25,
		func(v): GnEnvironment.apply("time_of_day", v), _clock)
	_controls.heading = GnUi.slider(_body, "Sun direction", -180.0, 180.0, 1.0,
		func(v): GnEnvironment.apply("heading", v), func(v): return "%+d°" % int(v))
	_controls.sun_strength = GnUi.slider(_body, "Sun strength", 0.0, 3.0, 0.05,
		func(v): GnEnvironment.apply("sun_strength", v), func(v): return "%.2f" % v)
	_real = CheckBox.new()
	_real.text = "Real sun for a place and date"
	_real.toggled.connect(func(on): GnEnvironment.apply("real_sun", on); refresh())
	_body.add_child(_real)
	_real_box = VBoxContainer.new()
	_body.add_child(_real_box)
	_place = GnUi.option(_real_box, "Place", ["(custom)"] + GnSun.PLACES.keys(), func(t): _pick_place(t))
	_controls.latitude = GnUi.slider(_real_box, "Latitude", -66.0, 66.0, 0.001,
		func(v): GnEnvironment.apply("latitude", v), func(v): return "%.3f°" % v)
	_controls.longitude = GnUi.slider(_real_box, "Longitude", -180.0, 180.0, 0.001,
		func(v): GnEnvironment.apply("longitude", v), func(v): return "%.3f°" % v)
	_controls.utc_offset = GnUi.slider(_real_box, "Clock (UTC offset)", -12.0, 14.0, 0.5,
		func(v): GnEnvironment.apply("utc_offset", v), func(v): return "UTC%+.1f" % v)
	_controls.day_of_year = GnUi.slider(_real_box, "Date", 1.0, 365.0, 1.0,
		func(v): GnEnvironment.apply("day_of_year", int(v)), func(v): return GnSun.date_label(int(v)))
	GnUi.heading(_body, "Sky")
	_controls.sky = GnUi.option(_body, "Sky", GnEnvironment.sky_choices(),
		func(t): GnEnvironment.apply("sky", t))
	_controls.fog = GnUi.slider(_body, "Distance haze", 0.0, 1.0, 0.01,
		func(v): GnEnvironment.apply("fog", v), func(v): return "%d%%" % int(v * 100))
	_controls.haze = GnUi.slider(_body, "Stage haze (shows beams)", 0.0, 2.0, 0.01,
		func(v): GnEnvironment.apply("haze", v), func(v): return "off" if v <= 0.0 else "%d%%" % int(v * 100))
	_controls.cloudiness = GnUi.slider(_body, "Clouds", 0.0, 1.0, 0.01,
		func(v): GnEnvironment.apply("cloudiness", v), func(v): return "clear" if v < 0.05 else "%d%%" % int(v * 100))
	GnUi.heading(_body, "Weather")
	_weather = GnUi.option(_body, "Weather", GnWeather.KINDS, func(t): GnWeather.set_value("kind", t))
	_weather_amount = GnUi.slider(_body, "Heaviness", 0.05, 1.0, 0.01,
		func(v): GnWeather.set_value("amount", v), func(v): return "%d%%" % int(v * 100))
	_wet = GnUi.slider(_body, "Wet ground", 0.0, 1.0, 0.01,
		func(v): GnWeather.set_value("wet", v), func(v): return "dry" if v <= 0.0 else "%d%%" % int(v * 100))
	_puddles = GnUi.slider(_body, "Puddles", 0.0, 1.0, 0.01,
		func(v): GnWeather.set_value("puddles", v), func(v): return "none" if v <= 0.0 else "%d%%" % int(v * 100))
	_season = GnUi.option(_body, "Season", GnWeather.SEASONS, func(t): GnWeather.set_value("season", t))
	GnUi.heading(_body, "Light")
	_controls.exposure = GnUi.slider(_body, "Exposure", -2.0, 2.0, 0.05,
		func(v): GnEnvironment.apply("exposure", v), func(v): return "%+.1f EV" % v)
	_controls.ambient = GnUi.slider(_body, "Sky light", 0.0, 2.0, 0.05,
		func(v): GnEnvironment.apply("ambient", v), func(v): return "%.2f" % v)


func refresh() -> void:
	var ready := GnEnvironment.is_set_up()
	_hint.visible = not ready
	_body.visible = ready
	if not ready:
		return
	for key in _controls:
		var c = _controls[key]
		if c is HSlider:
			GnUi.show_value(c, GnEnvironment.value(key))
		elif c is OptionButton:
			GnUi.select_text(c, GnEnvironment.value(key))
	var w := GnWeather.state()
	GnUi.select_text(_weather, w.kind)
	GnUi.show_value(_weather_amount, float(w.amount))
	GnUi.show_value(_wet, float(w.wet))
	GnUi.show_value(_puddles, float(w.get("puddles", 0.0)))
	GnUi.select_text(_season, w.season)
	var real := bool(GnEnvironment.value("real_sun"))
	_real.set_pressed_no_signal(real)
	_real_box.visible = real
	# A photo sky fixes the time of day: the sun is where the photo's sun is.
	var photo := GnEnvironment.is_photo_sky()
	_controls.time_of_day.get_parent().modulate.a = 0.4 if photo else 1.0
	_controls.time_of_day.editable = not photo


func _pick_place(place: String) -> void:
	if not GnSun.PLACES.has(place):
		return
	var p: Array = GnSun.PLACES[place]
	GnEnvironment.apply("latitude", p[0])
	GnEnvironment.apply("longitude", p[1])
	GnEnvironment.apply("utc_offset", p[2])
	refresh()


static func _clock(hours: float) -> String:
	return "%d:%02d" % [int(hours), int(round(fmod(hours, 1.0) * 60.0))]
