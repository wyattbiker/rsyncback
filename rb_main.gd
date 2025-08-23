@tool
@icon("assets/folder_up.svg")

extends Control
class_name RsyncMain

var rsync_back_version: String

const custom_tooltip = "tooltip_custom/tooltip.tscn"

var default_conf_file: String = "resource/default_config.tres"
var conf_file: String = "resource/config.tres"

class Result extends RsyncManage.Result:
	pass

class Version extends RsyncManage.Version:
	pass

class ConfigArgs extends RsyncManage.ConfigArgs:
	pass

var cmgr: ConfigArgs

var alert_dialog_scene = preload("scene/alert_dialog.tscn")
var messages_window = preload("scene/messages_window.tscn")
var file_dialog_scene = preload("scene/file_dialog.tscn")
var textedit_scene = preload("scene/textedit_dialog.tscn")


# Default config. Must exist
var default_conf_resource: DefaultConfig
# Create copy of default_conf_resource if it does not exist
var conf_resource: DefaultConfig

var plugin_path: String
var user_data_path: String
var rsync_command_text: String

# used to initialize hover over for clickable RichTextLabels
@onready var richtext: Array[RichTextLabel] = \
	[
%SourcePathClick, %RsyncCmdPathClick, %DestPathClick, %PrevBackupClick,
%LogFilePathClick, %ExcludeFilePathClick, %ConfigFileClick, %OpenFileManagerClicked
	]

func _enter_tree():
	$StatusMessage.visible = false
	rsync_command_text = %RSyncCommand.text

func _ready():
	_on_highlight_meta_hover_connect(richtext)
	var variation = 0
	variation = randf_range( - 0.25, 0.25)
	plugin_path = ""
	if OS.has_feature("editor"):
		plugin_path = (get_script() as Script).resource_path.get_base_dir()
		plugin_path = ProjectSettings.globalize_path(plugin_path)
		user_data_path = plugin_path
	else:
		show_alert("Plugin Cannot be run as an executable.")
		return

func _ready_plugin():
	# Load config file.
	# Create config file from default
	var res: Result = open_conf_resource()
	if res.code != 0:
		show_alert(res.description)
		return

	# Must be initialized after new()
	cmgr = ConfigArgs.new()
	
	cmgr.init(plugin_path, conf_resource)

	if verify_arguments():
		return false


func verify_arguments() -> bool:
	# seperate check for rsync version
	var version = cmgr.verify_rsync_version()
	cmgr.rsync_version = version

	# 2nd pass to validate arguments and show any error messages
	# in the cmgr.res result object
	cmgr.prepare_rsync_arguments(true)
	refresh_ui()
	if cmgr.cfg_error_messages.is_empty():
		return true
	else:
		return false

# Open config.tres configuration file.
# If missing, create copy of the default_config.tres.
# return Result code
func open_conf_resource(reset_conf: bool = false) -> Result:
	var res = Result.new()
	var def_conf_path = plugin_path.path_join(default_conf_file)
	if ResourceLoader.exists(def_conf_path):
		default_conf_resource = load(def_conf_path)
	else:
		res.code = -1
		res.description = "Default Config file %s does not exist Error: %s " % [def_conf_path, res.code]
		return res

	var conf_path = user_data_path.path_join(conf_file)
	var conf_folder = conf_path.get_base_dir()

	if !ResourceLoader.exists(conf_path) or reset_conf:
		res.code = DirAccess.make_dir_recursive_absolute(conf_folder)
		if res.code != 0:
			res.description = "Could not create resource folder %s creation Error: %s " % [conf_folder, res.code]
			return res
		res.code = ResourceSaver.save(default_conf_resource, conf_path)
		if res.code != 0:
			res.description = "Config file %s creation Error: %s " % [conf_path, res.code]
			return res

	var eng_ver: int = Engine.get_version_info().hex
	if eng_ver >= 0x040300:
		conf_resource = ResourceLoader.load(conf_path, "Resource", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	else:
		conf_resource = ResourceLoader.load(conf_path, "Resource", ResourceLoader.CACHE_MODE_REPLACE)
	res.value = conf_resource
	return res

# Run the backup. Running it asyncronously
func _on_run_backup_pressed():
	$StatusMessage.visible = true
	$StatusMessage.text = "[pulse freq=0.5 color=red ease=2.0]Backing up. Please Wait...[/pulse]"
	#$StatusMessage.text="Backing up. Please Wait..."
	if cmgr.config_dirty:
		conf_resource = cmgr.update_config(conf_resource)
		ResourceSaver.save(conf_resource)
		cmgr.config_dirty=false
		
	if !verify_arguments():
		show_alert("There is a problem with the configuration! View Messages")
		return

	print("RSync Backup Started: ", Time.get_unix_time_from_system())
	# Wait for result
	var res := await _exec_rsync(cmgr)
	print("RSync Backup Ended: ", Time.get_unix_time_from_system())

	cmgr.dry_run_enabled = ""
	%RunBackup/DryRun.button_pressed = false

	var args: ConfigArgs.RsyncArgs = cmgr.rsync_args

	$StatusMessage.visible = true
	if res.code != 0:
		$StatusMessage.visible = false
		$StatusMessage.text = "[color=red]Backup Errors. [url=%s]Check Log File[/url][/color]" % [args.dest_path.path_join(args.project_name)]
		cmgr.push_error_message($StatusMessage.text)
	else:
		$StatusMessage.text = "[color=red]Backup Done. [hint=%s][url=%s]Click to view.[/url][/hint][/color]" % [args.dest_path.path_join(args.project_name), args.dest_path.path_join(args.project_name)]
	await get_tree().create_timer(2).timeout.connect(func():
		_ready_plugin()
	)
	pass # Replace with function body.

# Excute the backup synchronously (blocking)
func _exec_rsync(cmgr: ConfigArgs) -> Variant:
	# Open a text_edit window and get handle
	var text_edit = await display_log("\nBacking Up Has Started. Please Wait\n")
	await get_tree().create_timer(1).timeout
	# Run backup. This is a blocking call
	var res = RsyncManage.exec_rsync(cmgr)
	# Check result and display report or error
	if res.code == 0:
		text_edit.get_node("%TextEditContent").text = res.value[0]
		# Scroll to bottom
		#text_edit.get_node("%TextEditContent").scroll_vertical = \
					#text_edit.get_node("%TextEditContent").get_line_count() + 1
	else:
		text_edit.get_node("%TextEditContent").text = "(%s), %s, %s," % [res.code, res.description, res.value]
	return res

# popup a window to display report.
func display_log(content: String) -> Window:
	var text_edit: Window = textedit_scene.instantiate() \
		.with_data(content, "Backup Log", messages_default_color)
	text_edit.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				text_edit.queue_free()
			_:
				text_edit.queue_free()
		)
	text_edit.get_node("%TextEditContent").editable=false
	text_edit.size = size * 1.0
	var tscene = $"."
	var tpos = tscene.position + tscene.global_position + (tscene.size - Vector2(text_edit.size)) * 0.5
	text_edit.position = tpos
	text_edit.get_node("%OKButton").text = "Close"
	add_child(text_edit)
	return text_edit

# Display arguments of the loaded config file.
func refresh_ui():
	$RSyncBackupVesion.text = "Ver: " + rsync_back_version
	$VBoxContainer/RsyncCmdPath.text = cmgr.rsync_cmd_path + " ( Version:" + cmgr.rsync_version.version + " )"
	$VBoxContainer/RsyncCmdPath/RsyncCmdPathClick.tooltip_text = "Click to choose the [u]rsync[/u] executable or binary. Minimum Version: " \
		+cmgr.rsync_min_version + "\nFor more information about rsync visit " + \
		"[url=https://download.samba.org/pub/rsync/rsync.1]https://download.samba.org/pub/rsync/rsync.1[/url]"
	$VBoxContainer/SourcePath.text = cmgr.rsync_args.source_path

	$VBoxContainer/DestPath.text = ""
	if cmgr.rsync_args.dest_path != "":
		$VBoxContainer/DestPath.text = cmgr.rsync_args.dest_path.path_join(cmgr.rsync_args.project_name) #.path_join(cmgr.rsync_args.current_datetime)

	$VBoxContainer/DestPath/DestPathClick.tooltip_text = "Click to choose a backup destination folder. This project's backups will be created in the main folder [color=lightblue][u]" + cmgr.rsync_args.project_name + "[/u][/color] and subfolders with the current datetime."
	$VBoxContainer/LogFilePath.add_theme_color_override("font_uneditable_color", Color("#00d3d0"))
	if cmgr.rsync_args.log_file_path != "":
		$VBoxContainer/LogFilePath.text = "./" + cmgr.rsync_args.log_file_path.get_file() #.path_join(cmgr.rsync_args.current_datetime+cmgr.rsync_args.log_file_suffix)
	else:
		$VBoxContainer/LogFilePath.add_theme_color_override("font_uneditable_color", Color.RED)
		$VBoxContainer/LogFilePath.text = "No Log File Path yet."

	$VBoxContainer/ExcludeFilePath.text = cmgr.rsync_args.exclude_file_path
	$VBoxContainer/ExcludeFilePath/ExcludeFilePathClick.tooltip_text = set_exclude_file_view_tooltip()

	$VBoxContainer/PrevBackup.text = ""
	$VBoxContainer/PrevBackup.add_theme_color_override("font_uneditable_color", Color("#00d3d0"))
	if cmgr.rsync_args.prev_backup != "":
		$VBoxContainer/PrevBackup.text = "./" + cmgr.rsync_args.dest_path.path_join(cmgr.rsync_args.project_name).path_join(cmgr.rsync_args.prev_backup).get_file()
	else:
		$VBoxContainer/PrevBackup.add_theme_color_override("font_uneditable_color", Color.RED)
		$VBoxContainer/PrevBackup.text = "No Previous Backup yet " # + cmgr.rsync_args.dest_path.path_join(cmgr.rsync_args.project_name)

	$VBoxContainer/ConfigFile.text = ProjectSettings.globalize_path(user_data_path.path_join(conf_file))
	$VBoxContainer/ConfigFile/ConfigFileClick.tooltip_text = set_config_view_tooltip()

	if cmgr.cfg_error_messages.is_empty():
		$RSyncCommand.text = cmgr.rsync_cmd_path + " " + cmgr.rsync_args_to_template()
	else:
		$RSyncCommand.text = rsync_command_text #"[b]Check Configuration. Click View Messages button for more info.[/b]"

	if cmgr.cfg_error_messages.is_empty():
		%RunBackup.disabled = false
		%ViewMessages.disabled = true
	else:
		%RunBackup.disabled = true
		%ViewMessages.disabled = false

	%RunBackup/DryRun.tooltip_text = %RunBackup/DryRun/Label.tooltip_text

# Called by _make_custom_tooltip() in each individual control
# to display custom tooltips. See the path value in custom_tooltip
func make_custom_tooltip(for_text: String, tooltip_name: String, ctrl: Control):
	# Uncomment line below to disable custom tooltip
	# return null
	var tooltip_scene: PackedScene = load(plugin_path.path_join(custom_tooltip))
	var tooltip = tooltip_scene.instantiate() as Control
	var tooltip_type = tooltip.get_node(tooltip_name)
	return tooltip.make_custom_tooltip(tooltip_type, ctrl)

# Disable plugin.  Can only be enabled from Project Settings.
func _on_cancel_pressed():
	disable_plugin()

func _on_dry_run_toggled(toggled_on):
	var tc = %RunBackup/DryRun/Label.get_theme_color("font_color")
	if toggled_on:
		cmgr.dry_run_enabled = "Y"
		tc = Color.ORANGE
		%RunBackup/DryRun/Label.add_theme_color_override("font_color", tc)
		show_alert("Dry Run is enabled. This will only test the backup and generate a log file. \nNO BACKUP is created! Uncheck Dry Run if you want to perform real backup.", "Warning!", Color.BLACK)
	else:
		cmgr.dry_run_enabled = ""
		tc = Color.WHITE
		%RunBackup/DryRun/Label.add_theme_color_override("font_color", tc)
	refresh_ui()
	pass # Replace with function body.

# Must be called as a coroutine if you want it to pause
# and await user to click OK or X
# E.g. await show_alert(...).confirmed
func show_alert(messg := "Alert", title := "Alert!", color := Color.BLACK) -> AcceptDialog:
	var alert_dialog: AcceptDialog = alert_dialog_scene.instantiate() \
		.with_data(messg, title, color)
	# If canceled emit a confirmed
	alert_dialog.canceled.connect(func():
		alert_dialog.emit_signal("confirmed")
		)
	alert_dialog.confirmed.connect(func():
		alert_dialog.queue_free()
		)
	add_child(alert_dialog)
	return alert_dialog

# Displays a message window with OK button
# return the window node and you can add additional buttons
# using add_action() methods. See examples in this code
const messages_default_color = 0x2e4972

func show_messages(messg := "Messages!", title: String = "Messages", color: Color = Color.hex(messages_default_color)) -> Window:
	var messages: Window = messages_window.instantiate() \
		.with_data(messg, title, color)
	var mscene = $"."
	var mpos = mscene.position + mscene.global_position + (mscene.size - Vector2(messages.size)) * 0.5
	messages.position = mpos
	add_child(messages)
	return messages

func show_textedit(txt := "ABC", title: String = "Text Edit", color: Color = Color.hex(messages_default_color)) -> Window:
	var text_edit: Window = textedit_scene.instantiate() \
		.with_data(txt, title, color)
	var tscene = $"."
	var tpos = tscene.position + tscene.global_position + (tscene.size - Vector2(text_edit.size)) * 0.5
	text_edit.position = tpos
	text_edit.get_node("%TextEditContent").editable=true
	add_child(text_edit)
	return text_edit


func _on_view_messages_pressed():
	var s := ""
	for res in cmgr.cfg_error_messages:
		s += "[ul] " + res.description + "[/ul]\n________________________\n[p]"
	var msg = show_messages(s, "Configuration Error Messages")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				msg.queue_free()
			_:
				msg.queue_free()
		)

func _on_clipboard_button_pressed():
	DisplayServer.clipboard_set($RSyncCommand.text)
	$ClipboardButton/Label.visible = true
	await get_tree().create_timer(3).timeout
	$ClipboardButton/Label.visible = false
	pass # Replace with function body.

# Prompt user for backup destination file using file picker dialog
func _on_dest_path_click_meta_clicked(_meta):
	var file_dialog: FileDialog = file_dialog_scene.instantiate()
	file_dialog.title = "Select A Backup Destination Folder"
	file_dialog.current_dir = cmgr.rsync_args.dest_path
	file_dialog.connect("canceled", \
		func():
			file_dialog.queue_free()
	)
	file_dialog.connect("dir_selected", \
		func(dir_selected):
			cmgr.rsync_args.dest_path = dir_selected
			cmgr.clear_error_message()
			cmgr.prepare_rsync_arguments(false)
			cmgr.config_dirty=true
			refresh_ui()
			file_dialog.queue_free()
	)
	var s = DisplayServer.window_get_size() * 0.8
	file_dialog.size = s
	#var p=DisplayServer.window_get_position()
	#file_dialog.position=p

	add_child(file_dialog)

# Prompt user for rsync file using file picker dialog
func _on_rsync_cmd_path_click_meta_clicked(meta):
	var file_dialog: FileDialog = file_dialog_scene.instantiate()

	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Select RSync Executable"
	file_dialog.current_file = cmgr.rsync_cmd_path.get_file()
	file_dialog.current_path = cmgr.rsync_cmd_path
	file_dialog.connect("canceled", \
		func():
			file_dialog.queue_free()
	)
	file_dialog.connect("file_selected", \
		func(file_selected):
			cmgr.rsync_cmd_path = file_selected
			cmgr.clear_error_message()
			cmgr.rsync_version = cmgr.verify_rsync_version()
			if cmgr.cfg_error_messages.size() == 0:
				cmgr.prepare_rsync_arguments(false)
				cmgr.config_dirty=true
			else:
				cmgr.rsync_version.version = "Not Valid Version. View Messages"
			refresh_ui()
			file_dialog.queue_free()
	)
	var s = DisplayServer.window_get_size() * 0.8
	file_dialog.size = s
	#var p=DisplayServer.window_get_position()
	#file_dialog.position=p

	add_child(file_dialog)

# Create tooltip string for Config label on main screen
func set_config_view_tooltip() -> String:
	var s := "Click to view, edit or reset the configuration file:\n%s" % [conf_resource.resource_path]
	return s

# Display and allow user to select reset or edit config.tres resource
func _on_config_view_meta_clicked(_meta):
	# Create a description messages for popup window when Config is clicked
	var s: String = "[center]Reset or manually edit RsyncBack [b]config.tres[/b] configuration[/center].

[b]Reset Config[/b] sets it back to the same values as in [b]default_config.tres[/b].

[b]Edit In Inspector[/b] allows you to edit the data using the Inspector tab in the Dock. [color=red]" \
+"You must save[/color] and restart plugin in Project Settings > Plugins for the changes to take effect.

NOTE: No backups are deleted or altered with Reset or Edit"

	var messages: Window = show_messages(s, "Configuration config.tres file actions")
	# Add extra action buttons to popup and handle actions
	var btn = messages.add_action("Reset Config", "CONFIRM", false)
	messages.add_action("Edit in Inspector", "INSPECTOR", false)

	messages.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON", "CLOSE", "ESCAPE", "CANCEL":
				messages.queue_free()
			"CONFIRM":
				reset_config()
				messages.queue_free()
			"INSPECTOR":
				var edi: EditorInspector = EditorInterface.get_inspector()
				edi.resource_selected.emit(conf_resource, conf_resource.resource_path)
				messages.queue_free()
			_:
				messages.queue_free()
		)

# Reset resource config.tres file to default_config.tres.
func confirm_config_reset():
	var s: String = "Clicking Accept, will reset the Configuration file. You must then choose a new Destination Path.
NOTE: Your existing backups will not be affected nor deleted."
	var msg: Window = show_messages(s, "Confirm Configuration File Reset", Color.RED)
	msg.add_action("Accept", "ACCEPT")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON", "CLOSE", "ESCAPE", "CANCEL":
				msg.queue_free()
			"ACCEPT":
				reset_config()
				msg.queue_free()
			_:
				msg.queue_free()
		)
	pass

# Message
func confirm_edit_in_inspector():
	var s: String = r"""Manually Edit Configuration resource %s in Inspector.
Click the Save Currently Resources button when done.
You must restart RsyncBack plugin from Project Settings > Plugins """ % [conf_resource.resource_path]
	var msg: Window = show_messages(s, "Edit Configuration Resource " + conf_resource.resource_path, Color.RED)
	msg.add_action("Proceed", "ACCEPT")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON", "CLOSE", "ESCAPE", "CANCEL":
				msg.queue_free()
			"ACCEPT":
				reset_config()
				msg.queue_free()
			_:
				msg.queue_free()
		)
	pass

func reset_config():
	conf_resource = null
	open_conf_resource(true)
	_ready_plugin()
	# Show message and accept confirmed event
	show_alert("Config File has been reset. Click OK to continue")
	pass

func disable_plugin():
	var s: String = "Clicking Accept, will disable the RsyncBack plugin. To re-enable go to Project Settings > Plugins."
	var msg: Window = show_messages(s, "Disable Plugin")
	msg.add_action("Accept", "ACCEPT")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON", "CLOSE", "ESCAPE", "CANCEL":
				msg.queue_free()
			"ACCEPT":
				EditorInterface.set_plugin_enabled(plugin_path.get_file(), false)
				msg.queue_free()
			_:
				msg.queue_free()
		)
	pass

func set_exclude_file_view_tooltip() -> String:
	var s := "Click to view exclude file %s.\nList the file patterns using filenames, directory names or wildcard patterns that will be excluded from rsync backup.
For rules visit [url=https://download.samba.org/pub/rsync/rsync.1#FILTER_RULES]https://download.samba.org/pub/rsync/rsync.1[/url]
	" % [cmgr.rsync_args.exclude_file_path]
	return s

func _on_exclude_file_view_click_meta_clicked(meta):
	var s: String = Utils.load_from_file(cmgr.rsync_args.exclude_file_path)
	var txt = show_textedit(s, "Exclude Files Editor")
	txt.add_action("Save Changes", "SAVE")
	txt.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				#if txt.text_changed:
					#show_alert("Changes were made to the exclude file. Exit without saving?")
				#else:
				txt.queue_free()
			"SAVE":
				txt.queue_free()
				s = txt.get_textedit_content()
				Utils.save_to_file(cmgr.rsync_args.exclude_file_path, s)
			_:
				txt.queue_free()
		)
	pass

func textedit_exclude():
	var s: String = Utils.load_from_file(cmgr.rsync_args.exclude_file_path)
	var txt = show_textedit(s, "Exclude Files Editor")
	txt.add_action("Save", "SAVE")
	txt.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				txt.queue_free()
			"SAVE":
				txt.queue_free()
			_:
				txt.queue_free()
		)
	pass

func _on_log_file_path_click_meta_clicked(meta):
	var args = cmgr.rsync_args
	var err
	if args.log_file_path != "" and DirAccess.dir_exists_absolute(args.log_file_path):
		err = OS.shell_open(args.log_file_path)
	else:
		err = -1
	if err != OK:
		show_alert("No Logfiles yet. Logfiles are created after a backup.")

	return

# Open File Manager in Destination Path if one is present
func _on_open_file_manager_meta_clicked(meta):
	var args = cmgr.rsync_args
	var err
	if DirAccess.dir_exists_absolute(args.dest_path.path_join(args.project_name)):
		err = OS.shell_open(args.dest_path.path_join(args.project_name))
	else:
		err = -1
	if err != OK:
		show_alert("No Backup Destination Path Selected. Please choose one.")

	pass # Replace with function body.

func _on_status_message_meta_clicked(meta):
	OS.shell_open(meta)
	pass # Replace with function body.

func _on_source_path_meta_clicked(meta):
	var args = cmgr.rsync_args
	var err
	if DirAccess.dir_exists_absolute(args.source_path):
		err = OS.shell_open(args.source_path)
	else:
		err = -1
	if err != OK:
		show_alert("No Source Path Found. Check your project.")

	pass # Replace with function body.

func _on_prev_backup_click_meta_clicked(meta):
	var args = cmgr.rsync_args
	var err
	if DirAccess.dir_exists_absolute(args.dest_path.path_join(args.project_name).path_join(args.prev_backup)):
		err = OS.shell_open(args.dest_path.path_join(args.project_name).path_join(args.prev_backup))
	else:
		err = -1
	if err != OK:
		show_alert("No Previous Backups. Will be avaible after you create your first backup.")

	pass # Replace with function body.

# Highlight when mouse hovers
var default_color = Color.WHITE

func _on_highlight_meta_hover_connect(richtext: Array[RichTextLabel]):
	var n:NodePath
	for rt in richtext:
		n=rt.get_path()
		rt.meta_hover_started.connect(_on_highlight_meta_hover_started.bind(n))
		rt.meta_hover_ended.connect(_on_highlight_meta_hover_ended.bind(n))
	pass

func _on_highlight_meta_hover_started(meta, unique_name: NodePath):
	default_color = get_node(unique_name).get_theme_color("default_color")
	get_node(unique_name).add_theme_color_override("default_color", Color.LIGHT_BLUE)

func _on_highlight_meta_hover_ended(meta, unique_name: NodePath):
	get_node(unique_name).add_theme_color_override("default_color", default_color)
	pass # Replace with function body.

func _on_information_pressed():
	var msg = show_messages($Information.tooltip_text, "Quick Start")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				msg.queue_free()
			_:
				msg.queue_free()
		)

func _notification(what):
	# Not used. But can be enabled to set defaults for
	# all gui variables
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		pass


func _on_help_pressed():
	var msg = show_messages(%Help.tooltip_text, "Quick Start")
	msg.action_selected.connect(func(action: String):
		match action:
			"OKBUTTON":
				msg.queue_free()
			_:
				msg.queue_free()
		)
	pass # Replace with function body.
