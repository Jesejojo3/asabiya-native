extends SceneTree
## Render the actual dialog at desktop resolutions and logical DPI scales.
## Software rendering checks layout; it does not measure the user's GPU.
class Observer extends Node:
	var source := BridgeSource.new()
	var world := WorldData.new()
	var current_frame := HistoryFrame.new()
	var current_year := -100
	var selection := {"kind":"","id":-1}
	func select_entity(_kind: String,_id: int,_fly: bool) -> void: pass
	func focus_selection() -> void: pass
	func _request_close() -> void: pass
var failures := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.gui_embed_subwindows=true
	var observer:=Observer.new()
	observer.source.connected=true
	root.add_child(observer)
	var hud:=Hud.new()
	root.add_child(hud)
	hud.build(observer)
	var output:=ProjectSettings.globalize_path("res://../../artifacts/deep-throughput/dialog")
	DirAccess.make_dir_recursive_absolute(output)
	for resolution:Vector2i in [Vector2i(1366,768),Vector2i(1600,900),Vector2i(1920,1080)]:
		for scale:float in [1.0,1.25,1.5]:
			hud.fast_dialog.queue_free()
			hud._build_fast_dialog() # Test first opening at every scale.
			root.size=resolution
			root.content_scale_factor=scale
			await process_frame
			hud.fast_dialog.popup_centered_clamped(Vector2i(440,260),0.75)
			for i in 3: await process_frame
			var dialog:=hud.fast_dialog
			var viewport:=root.get_visible_rect()
			var bounds:=Rect2(Vector2(dialog.position),Vector2(dialog.size))
			check(viewport.encloses(bounds),"dialog inside viewport %s scale %s" % [resolution,scale])
			for button:Button in [dialog.get_ok_button(),dialog.get_cancel_button()]:
				check(button.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(dialog.size)).encloses(button.get_global_rect()),"confirmation button visible and inside dialog")
			var name:="%dx%d-%d.png" % [resolution.x,resolution.y,int(scale*100)]
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(name))
			print("DIALOG ",name," viewport=",viewport," bounds=",bounds," ok=",dialog.get_ok_button().get_global_rect())
			dialog.hide()
	hud.queue_free();observer.queue_free()
	await process_frame
	print("Fast dialog visual: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
