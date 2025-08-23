@tool
extends EditorPlugin

var MainPanel: PackedScene
var mainpanel_instance: Control

var plugin_cfg_name = 'plugin.cfg'
var mainpanel_name = 'rb_main.tscn'
var plugin_descriptive_name = "RSyncBack"
var plugin_path
var plugin_verion
var godot_engine_version: int = 0x040201
var godot_engine_version_string: String = "4.2.1"

func _init():
	if Engine.get_version_info().hex > godot_engine_version:
		plugin_path = get_script().get_path().get_base_dir()
		MainPanel = load(plugin_path.path_join(mainpanel_name))
	else:
		print("This plugin supports godot engine version %s or higher " % [godot_engine_version_string])
		return

func _enter_tree() -> void:
	mainpanel_instance = MainPanel.instantiate()
	plugin_verion = get_plugin_version()
	mainpanel_instance.rsync_back_version = plugin_verion
	EditorInterface.get_editor_main_screen().add_child(mainpanel_instance)
	# Required to be able to get the vertical height of the plugin scene
	mainpanel_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_make_visible(false)


func _exit_tree():
	if mainpanel_instance:
		EditorInterface.get_editor_main_screen().remove_child(mainpanel_instance)
		mainpanel_instance.queue_free()

func _has_main_screen():
	return true

func _make_visible(visible):
	if mainpanel_instance:
		mainpanel_instance.visible = visible
		if visible:
			hide_bottom_panel()
			mainpanel_instance._ready_plugin()

func _get_plugin_name():
	return plugin_descriptive_name

func _get_plugin_icon():
	# Must return some kind of Texture2D for the icon.
	return load(plugin_path.path_join("assets/folder_up.svg"))
	#return EditorInterface.get_base_control().get_theme_icon("Node", "EditorIcons")
