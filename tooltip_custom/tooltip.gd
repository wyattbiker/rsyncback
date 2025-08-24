@tool
extends Control

class_name TooltipCustom

# Time delay before showing
const TI_SHOW_DELAY="T1ShowDelay" #Just a label for debug
var t1_show: Timer
var t1_show_delay = 0.5

# Time delay befor closing
const T2_CLOSE_DELAY = "T2CloseDelay" #Just a label for debug
var t2_close: Timer
var t2_close_delay = 0.5

# Tooltip Scene Object
var tooltip=self

var host_ctrl=Control	# The control that initiated the tooltop
var tooltip_type: Control # Type of tooltip in use, e.g. RichTextLabel, TexturRect

var tooltip_entered: bool #Tracks whether the mouse entered over

# Called by the host control virtual method make_custom_tooltip()
func make_custom_tooltip(tooltip_type:Control, host_ctrl: Control):
	self.host_ctrl=host_ctrl # Copy parameters to tooltip object
	self.tooltip_type=tooltip_type
	tooltip.hide()
	
	# Keep only the participating tooltip in memory
	# by checking the class tooltip_type
	for tt in tooltip.get_children():
		if tt.get_class() != tooltip_type.get_class():
			tooltip.remove_child(tt)
			
	# Add tooltip to the scene
	host_ctrl.owner.add_child(tooltip)
	
	# Get class of the tooltip
	# And set default tooltip text from host_ctrl
	host_ctrl.tooltip_text=host_ctrl.tooltip_text.strip_edges(true,true)
	match tooltip_type.get_class():
		"TextureRect": # Get texture file path from tooltip_text
			# texture must be a path to an png or jpeg set in the tooltip
			# of the control. E.g. tooltip_text -> somefile.png
			tooltip_type.texture=load(host_ctrl.tooltip_text)
		"RichTextLabel","TextEdit","Label":
			tooltip_type.text=host_ctrl.tooltip_text
		"TextureButton":
			# texture must be a path to an png or jpeg set in the tooltip
			# of the control. E.g. tooltip_text -> somefile.png
			tooltip_type.texture_normal=load(host_ctrl.tooltip_text)
		_:
			return null

	# Call default additional customizing
	tooltip_type.position=Vector2(0,0)
	tooltip.calculate_position()
	
	# Optionally call host control customizing
	# Requires presense of _customize_tooltip(tooltip_type) method
	# in host control script
	if Callable(host_ctrl, "_customize_tooltip").is_valid():
		host_ctrl._customize_tooltip(tooltip)

	tooltip.show_tooltip_with_delay()
	# Return an empty panel node as tooltip. Required by
	# godot _make_custom_tooltip()
	return Panel.new()

func show_tooltip_with_delay():
	# Show tooltip after certain delay
	# Create timer delay before tooltip is shown
	t1_show = Timer.new()
	tooltip.add_child(t1_show)
	tooltip_entered=false
	
	# if mouse exits host control, free tooltip if not visible
	host_ctrl.mouse_exited.connect(func():
		if !tooltip.visible:
			t1_show.stop()
			t1_show.queue_free()
			tooltip.queue_free()
		,CONNECT_ONE_SHOT)	
	
	# Display tooltip after certain amount of time over host control.
	t1_show.name=TI_SHOW_DELAY
	t1_show.one_shot = true
	t1_show.timeout.connect(func():
		t1_show.stop()
		t1_show.queue_free()
		show_tooltip()
		,CONNECT_ONE_SHOT)
	t1_show.start(t1_show_delay)

func show_tooltip():
	tooltip_entered=false
	tooltip.show()
	tooltip_type.show()
	
	tooltip_type.mouse_exited.connect(func():
		tooltip_entered=false
		var clip=tooltip_type.get_selected_text()
		if clip.length()>0 and tooltip_type.selection_enabled:
			DisplayServer.clipboard_set(clip)
		tooltip_type.queue_free()
		,CONNECT_ONE_SHOT)	
		
	tooltip_type.mouse_entered.connect(func():
		tooltip_entered=true
		,CONNECT_ONE_SHOT)
	
	# Delay before closing tooltip once exiting the
	# host control
	host_ctrl.mouse_exited.connect(func():
		t2_close = Timer.new()
		host_ctrl.add_child(t2_close)
		t2_close.name=T2_CLOSE_DELAY
		t2_close.one_shot = true
		t2_close.timeout.connect(func():
			t2_close.stop()
			t2_close.queue_free()
			if !tooltip_entered:
				tooltip.hide()
				tooltip.queue_free()
			,CONNECT_ONE_SHOT)
		t2_close.start(t2_close_delay)
		,CONNECT_ONE_SHOT)
	
# Calculate tooltip position with respect to host control. 
func calculate_position():
	# Move tooltip above the host control
	tooltip.global_position = host_ctrl.global_position
	tooltip.global_position.y -= tooltip_type.size.y
	
	# if tooltip is outside screen boundaries, adjust so its visible
	# y falls above screen. adjust tooltip to be below host control
	if tooltip.global_position.y < host_ctrl.owner.global_position.y:
		tooltip.global_position.y = host_ctrl.global_position.y + host_ctrl.size.y
	
	# If tooltip is wider than the right of the screen, move tooltip to the left
	if tooltip.global_position.x + tooltip_type.size.x > host_ctrl.owner.global_position.x + host_ctrl.owner.size.x:
		tooltip.global_position.x = host_ctrl.owner.global_position.x +  host_ctrl.owner.size.x - tooltip_type.size.x
		
	return

#If tooltip contains URL tags, then open it with default application
# usually the browser
func _on_rich_text_label_meta_clicked(meta):
	if get_url_scheme(meta) == "":
		var absolute_path = ProjectSettings.globalize_path("res://")
		print(absolute_path.path_join(meta))
	print(meta)
	OS.shell_open(str(meta))
	pass # Replace with function body.

func get_url_scheme(url_string: String) -> String:
	var colon_index = url_string.find(":")
	if colon_index != -1:
		return url_string.substr(0, colon_index)
	return "" # Return an empty string if no scheme is found
