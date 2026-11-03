extends ColorRect
## A game's cover art (see cover.gdshader). Games without art get a placeholder tinted by
## their id, so each still looks like itself.

const SHADER := preload("res://src/ui/cover.gdshader")

var mat := ShaderMaterial.new()


func _init() -> void:
	mat.shader = SHADER
	material = mat
	mat.set_shader_parameter("zoom", 1.0)  # tweens need the parameters to exist first
	mat.set_shader_parameter("shade", 1.0)
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(func() -> void: mat.set_shader_parameter("rect_size", size))


func show_game(g: Library.Game) -> void:
	var tex := g.cover
	mat.set_shader_parameter("has_cover", tex != null)
	if tex:
		mat.set_shader_parameter("cover", tex)
		mat.set_shader_parameter("cover_aspect", float(tex.get_width()) / tex.get_height())
		# small covers are pixel art; keep them crisp when scaled up
		texture_filter = TEXTURE_FILTER_NEAREST if tex.get_width() < 640 else TEXTURE_FILTER_LINEAR
	mat.set_shader_parameter("tint", Color.from_hsv(absi(hash(g.id)) % 1000 / 1000.0, 0.5, 0.9))


func tween_param(tw: Tween, param: String, to: float, time: float) -> void:
	tw.tween_property(mat, "shader_parameter/" + param, to, time)
