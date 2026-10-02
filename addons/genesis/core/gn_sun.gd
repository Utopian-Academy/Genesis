@tool
extends RefCounted

# Where the sun really is: NOAA's solar position algorithm (the one behind
# NOAA's own solar calculator), accurate to a fraction of a degree, which is
# far more than shadow studies need. Given a place, a date and a local clock
# time it returns the sun's compass bearing and height.

# A few places, so a user can pick "London" rather than look up coordinates.
const PLACES := {
	"London": [51.507, -0.128, 0.0],
	"New York": [40.713, -74.006, -5.0],
	"Los Angeles": [34.052, -118.244, -8.0],
	"Chicago": [41.878, -87.630, -6.0],
	"Toronto": [43.653, -79.383, -5.0],
	"Paris": [48.857, 2.352, 1.0],
	"Berlin": [52.520, 13.405, 1.0],
	"Madrid": [40.417, -3.704, 1.0],
	"Dubai": [25.205, 55.271, 4.0],
	"Mumbai": [19.076, 72.878, 5.5],
	"Singapore": [1.352, 103.820, 8.0],
	"Tokyo": [35.676, 139.650, 9.0],
	"Sydney": [-33.869, 151.209, 10.0],
	"Cape Town": [-33.925, 18.424, 2.0],
	"São Paulo": [-23.551, -46.633, -3.0],
}


# azimuth: degrees clockwise from north. elevation: degrees above the horizon.
static func position(lat: float, lon: float, day_of_year: int, hours_local: float,
		utc_offset: float, year := 2026) -> Dictionary:
	var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
	var days := 366.0 if leap else 365.0
	var hour_utc := hours_local - utc_offset
	# Fractional year, radians.
	var g := TAU / days * (day_of_year - 1 + (hour_utc - 12.0) / 24.0)
	var eqtime := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
		- 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) \
		+ 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
	var time_offset := eqtime + 4.0 * lon - 60.0 * utc_offset
	var tst := hours_local * 60.0 + time_offset  # true solar time, minutes
	var ha := deg_to_rad(tst / 4.0 - 180.0)      # hour angle
	var phi := deg_to_rad(lat)
	var cos_zen := sin(phi) * sin(decl) + cos(phi) * cos(decl) * cos(ha)
	var zen := acos(clampf(cos_zen, -1.0, 1.0))
	var elevation := 90.0 - rad_to_deg(zen)
	# NOAA: cos(180° - az) = -(sin φ cos zen - sin δ) / (cos φ sin zen), with
	# az clockwise from north. Before solar noon the sun is east of the
	# meridian (az below 180), after it west, so the afternoon is mirrored.
	# Checked against London in June: north-east at dawn, due south at
	# solar noon at 61.9 degrees, north-west at dusk.
	var az := 180.0
	var denom := cos(phi) * sin(zen)
	if absf(denom) > 1e-6:
		var x := (sin(phi) * cos(zen) - sin(decl)) / denom
		az = rad_to_deg(acos(clampf(-x, -1.0, 1.0)))
		if ha > 0.0:
			az = 360.0 - az
	return {"azimuth": az, "elevation": elevation}


# Day of the year for a month (1-12) and day.
static func day_of_year(month: int, day: int) -> int:
	var starts := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	return starts[clampi(month, 1, 12) - 1] + day


static func date_label(doy: int) -> String:
	var names := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var starts := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
	for m in 12:
		if doy <= starts[m + 1]:
			return "%d %s" % [doy - starts[m], names[m]]
	return "31 Dec"


# The direction toward the sun in Genesis's world: north is -Z, east +X.
static func direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
