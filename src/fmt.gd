class_name Fmt
## Formatting shared by the UI: sizes, times and versions.


static func bytes(n: int) -> String:
	if n < 1000:
		return "%d B" % n
	if n < 1_000_000:
		return "%.0f KB" % (n / 1e3)
	if n < 1_000_000_000:
		return "%.1f MB" % (n / 1e6)
	return "%.2f GB" % (n / 1e9)


## RFC 3339 UTC ("2026-11-03T10:03:45Z") to unix seconds, or 0.
static func unix(iso: String) -> int:
	if iso.is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))


static func now() -> int:
	return int(Time.get_unix_time_from_system())


static func ago(t: int) -> String:
	if t <= 0:
		return "never"
	var s := now() - t
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % floori(s / 60.0)
	if s < 86400:
		return "%d hr ago" % floori(s / 3600.0)
	if s < 86400 * 30:
		var days := floori(s / 86400.0)
		return "%d day%s ago" % [days, "" if days == 1 else "s"]
	return Time.get_date_string_from_unix_time(t)


## "v0.2.0-15-g147ceb5" -> "v0.2.0+15", short enough for a card. Stable tags pass through.
static func short_version(v: String) -> String:
	var parts := v.split("-")
	if parts.size() == 3:
		return "%s+%s" % [parts[0], parts[1]]
	return v
