class_name AtlasIcons
extends RefCounted
## Original line icons, rasterized once per process. No external assets.
static var _cache: Dictionary = {}

static func get_icon(name: String) -> Texture2D:
	if _cache.has(name): return _cache[name]
	var paths := {
		"atlas": '<path d="M3 5l6-2 6 2 6-2v16l-6 2-6-2-6 2zM9 3v16m6-14v16"/>',
		"search": '<circle cx="10" cy="10" r="6"/><path d="M15 15l6 6"/>',
		"chronicle": '<path d="M5 3h14v18H5zM8 7h8M8 11h8M8 15h5"/>',
		"home": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c-5 5-5 13 0 18 5-5 5-13 0-18z"/>',
		"focus": '<path d="M3 8V3h5m8 0h5v5M3 16v5h5m8 0h5v-5"/><circle cx="12" cy="12" r="3"/>',
		"back": '<path d="M14 5l-7 7 7 7"/>',
		"forward": '<path d="M10 5l7 7-7 7"/>',
		"close": '<path d="M6 6l12 12M6 18L18 6"/>',
		"play": '<path d="M7 4l13 8-13 8z"/>',
		"pause": '<path d="M8 4v16m8-16v16"/>',
		"step": '<path d="M5 5l11 7-11 7zM20 5v14"/>',
		"menu": '<path d="M4 6h16M4 12h16M4 18h16"/>',
		"people": '<circle cx="9" cy="8" r="3"/><path d="M3 20v-3a6 6 0 0112 0v3m2-15a3 3 0 010 6m2 3a5 5 0 012 6"/>',
		"state": '<path d="M5 3h14v9c0 5-7 9-7 9s-7-4-7-9zM8 8h8M12 5v11"/>',
		"city": '<path d="M3 21V10h6v11m0 0V4h6v17m0 0V8h6v13M1 21h22M11 8h2m-2 4h2m-2 4h2"/>'
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#d7bb80" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % paths.get(name, paths["atlas"])
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK: return null
	var texture := ImageTexture.create_from_image(image)
	_cache[name] = texture
	return texture
