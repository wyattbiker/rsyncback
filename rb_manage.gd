@tool
class_name RsyncManage

# Looks for an existing backup folder formatted as YYYY-MM-DDTHHMMSS
#const regex_time_pattern: String = "^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T(2[0-3]|[01][0-9])_[0-5][0-9]_[0-5][0-9]$"
const regex_time_pattern: String = "^\\[[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])\\]\\[(2[0-3]|[01][0-9])_[0-5][0-9]_[0-5][0-9]\\]$"

## See rb_utils
## Alias for Utils.Result class
class Result extends Utils.Result:
	pass
# Alias for Utils.Version class
class Version extends Utils.Version:
	pass

# rsync arguments structure.
class RsyncArgs:
	var current_datetime: String
	var time_stamp_format: String
	var project_name: String
	var source_path: String
	var dest_path: String
	var exclude_file_path: String
	var prev_backup: String
	var log_file_path: String
	var log_file_suffix: String
	var dry_run_argument: String

# Configurations including rsync arguments
class ConfigArgs extends RsyncManage:
	var rsync_args := RsyncArgs.new()
	var res: Utils.Result
	var rsync_cmd_path: String
	var rsync_version: Version
	var rsync_template: String
	var rsync_min_version: String
	var rsync_plugin_path: String
	var conf: DefaultConfig
	var dry_run_enabled: String
	var cfg_error_messages: Array[Variant]
	var load_conf: bool = true
	var config_dirty: bool = false

	# Real init() must be called after instancing COnfigArgs
	func init(plugin_path: String, conf_resource: DefaultConfig):
		rsync_plugin_path = plugin_path
		conf = conf_resource
		res = Result.new()
		rsync_version = Version.new()
		if load_conf: rsync_cmd_path = conf.rsync_cmd_path
		if load_conf: rsync_min_version = conf.rsync_min_version
		pass


	func load_config(conf: DefaultConfig, load_conf: bool):
		# Load configuration file parameters from conf resource
		rsync_args.time_stamp_format = conf.time_stamp_format
		if load_conf: rsync_args.dest_path = conf.dest_path
		if load_conf: rsync_args.exclude_file_path = conf.exclude_file_path
		rsync_args.log_file_suffix = conf.log_file_suffix
		rsync_args.log_file_path = conf.log_file_path
		rsync_template = conf.rsync_template


	func update_config(conf_resource: DefaultConfig) -> DefaultConfig:
		# Only destination path changed by UI
		conf_resource.dest_path = rsync_args.dest_path
		conf_resource.rsync_cmd_path = rsync_cmd_path
		conf.dest_path = rsync_args.dest_path
		conf.rsync_cmd_path = rsync_cmd_path
		return conf


	# Gather rsync configuration arguments. Check them for missing or incorrect values
	# Return error meesage.
	func prepare_rsync_arguments(load_conf: bool) -> ConfigArgs:
		var res = Result.new()
		#if load_conf: rsync_cmd_path=conf.rsync_cmd_path
		#if load_conf: rsync_min_version=conf.rsync_min_version

		# Load configuration parameters for processing

		load_config(conf, load_conf)
		# Parse and verify the config file

		# Get a project name from res:// and also source path
		rsync_args.project_name = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file() + "-rsync"
		rsync_args.source_path = ProjectSettings.globalize_path("res://")

		# If empty, no exclude file in use.
		if rsync_args.exclude_file_path == "":
			rsync_args.exclude_file_path = "\"\""
		else:
			# If exclude is filename only, check if it exists in plugin path and if does not exist create empty file.
			# if full path then file MUST exist or give an error
			var err = 0

			if rsync_args.exclude_file_path.get_file() == rsync_args.exclude_file_path:
				rsync_args.exclude_file_path = rsync_plugin_path.path_join(rsync_args.exclude_file_path)
				if FileAccess.file_exists(rsync_args.exclude_file_path):
					var _file = FileAccess.open(rsync_args.exclude_file_path, FileAccess.READ_WRITE)
				else:
					var _file = FileAccess.open(rsync_args.exclude_file_path, FileAccess.WRITE)
				err = FileAccess.get_open_error()

			# Make sure exclude file exists
			rsync_args.exclude_file_path = ProjectSettings.globalize_path(rsync_args.exclude_file_path)
			if err != 0 or !FileAccess.file_exists(rsync_args.exclude_file_path):
				res.code = -1
				res.description = "Exclude file " + rsync_args.exclude_file_path + \
								" does not exist or could not be created"
				push_error_message(res)

		# Fix if already dest_path is same as project name.
		# We dont want to create another project backup folder inside the
		# an existing one.
		if rsync_args.dest_path.get_file() == rsync_args.project_name:
			rsync_args.dest_path = rsync_args.dest_path.get_base_dir()

		# Generate backup folder name based on time stamp
		if rsync_args.time_stamp_format == "":
			#                               [%04d-%02d-%02d][%02d_%02d_%02d]
			rsync_args.time_stamp_format = "[%04d-%02d-%02d][%02d_%02d_%02d]"
		var sys_time: Dictionary = Time.get_datetime_dict_from_system()
		rsync_args.current_datetime = rsync_args.time_stamp_format % \
			 [sys_time.year, sys_time.month, sys_time.day, sys_time.hour, sys_time.minute, sys_time.second];

		# Backup cannot be inside the same project folder
		var dir := DirAccess.open(rsync_args.dest_path)
		if rsync_args.dest_path == "" || dir == null:
			res.code = -1
			res.description = "Destination %s backup folder does not exist or is not available. Please choose one that exists.\nNote: Choose Backup Path outside your Godot Project Source Path." %\
					[rsync_args.dest_path]
			push_error_message(res)
			return self

		var cd = dir.get_current_dir().path_join("")
		if cd.find(rsync_args.source_path.path_join("")) == 0:
			res.code = -1
			res.description = "Backup Destination Path [b]%s[/b] cannot be inside the Project Source Path [b]%s[/b] project folder.\n Choose a Destination Path outside the project folder." %\
					[cd, rsync_args.source_path]
			push_error_message(res)
			return self

		# If dest path does not exist, print error
		# else get lates backup (if any) and create log files folder
		res = check_dest_path(rsync_args.dest_path)
		if res.code != 0:
			push_error_message(res)
			rsync_args.dest_path = ""
			rsync_args.prev_backup = ""
			rsync_args.log_file_path = ""
		else:
			## Get the latest backup project folder, if it exists, for use with incremental backup.
			res = get_latest_backup(rsync_args.dest_path, rsync_args.project_name)
			if res.code != 0:
				push_error_message(res)
			else:
				# Absolute path of latest backup
				rsync_args.prev_backup = res.value

			# Figure ot the log file path
			if rsync_args.log_file_suffix == "":
				rsync_args.log_file_suffix = "_log.txt"

			if rsync_args.log_file_path == "":
				rsync_args.log_file_path = rsync_args.dest_path.path_join(rsync_args.project_name)\
										.path_join("logfiles")

		return self

	# Verify the rsync binary and version
	# Compare the minimum config version with the current running version
	# Return 0 or error code and description in Result
	func verify_rsync_version() -> Version:
		var version = Version.new()
		version.res = Result.new()
		version.res.value = []

		# Use which to identify rsync path.
		if rsync_cmd_path == "":
			rsync_cmd_path = "rsync"
		version.res.code = OS.execute("which", [rsync_cmd_path], version.res.value, true, true)
		if version.res.code != 0:
			version.res.code = -1
			version.res.description = "which %s: Rsync Command Path does not exist. Select rsync you wish to run." % rsync_cmd_path
			push_error_message(version.res)
			# Cannot continue
			return version
		else:
			rsync_cmd_path = version.res.value[0].strip_edges(true, true)

		# Does binary exist
		if !FileAccess.file_exists(rsync_cmd_path):
			version.res.code = -1
			version.res.description = "Rsync Command Path " + rsync_cmd_path + " does not exist. Select rsync path you wish to run."
			push_error_message(version.res)
			# Cannot continue
			return version

		# Execute it to get version
		version.res.value = []
		version.res.code = OS.execute(rsync_cmd_path, ["--version"], version.res.value, true, true)
		if version.res.code != 0:
			var s = "OS Error: %d. Not valid rsync. Verify using your shell that %s is an rsync executable.\n" \
				% [version.res.code, rsync_cmd_path]
			version.res.description = s #+version.res.value[0]
			push_error_message(version.res)
			return version

		# Check if it's the rsync binary
		if version.res.value[0].left(5) != "rsync":
			version.res.code = -1
			version.res.description = "RSync Cmd Path: Not an rsync binary at %s " % rsync_cmd_path
			push_error_message(version.res)
			return version

		# Extract --version from execute result
		var current_ver = Version.new().get_version_components(version.res.value[0])
		if current_ver.res.code != 0:
			current_ver.res.description = "Rsync " + current_ver.res.description
			push_error_message(current_ver.res)
			return current_ver

		# Get minimum version from passed parameter into object
		#var min_ver=Version.new()
		var min_ver = Version.new().get_version_components(" " + rsync_min_version + " ")
		if min_ver.res.code != 0:
			min_ver.res.description = "Rsync Config " + min_ver.res.description
			push_error_message(min_ver.res)
			return min_ver

		current_ver = current_ver.version_minimum_check(min_ver)
		if current_ver.res.code != 0:
			current_ver.res.description = "Rsync " + current_ver.res.description
			push_error_message(current_ver.res)

		return current_ver

	##
	## Get latest backup path to use to compare against this backup.
	static func check_dest_path(dest_path: String) -> Result:
		var result := Result.new()
		result.code = 0
		result.value = ""
		if dest_path == "" || !DirAccess.dir_exists_absolute(dest_path):
			result.code = -1
			result.description = "Destination Path folder %s does not exist. Please select existing or create one!" % dest_path
		return result

	##
	## Get latest backup path to use to compare against this backup.
	static func get_latest_backup(backup_path: String, project_name: String) -> Result:
		var result := Result.new()

		if !DirAccess.dir_exists_absolute(backup_path):
			#result.code=DirAccess.make_dir_absolute(backup_path)
			result.code = -1
			result.description = "OS Error %s ! Destination Path folder %s does not exist. " % [result.error, backup_path]
			return result

		var prev_backup := ""
		var dir := DirAccess.open(backup_path.path_join(project_name))
		if dir != null:
			dir.list_dir_begin()
			var dir_name = dir.get_next()
			while dir_name != "":
				if dir.current_is_dir():
					# Create a regex to match datetime pattern directories
					var patt: String = regex_time_pattern
					var regex = RegEx.new()
					regex.compile(patt) # Negated whitespace character class.
					# Get directory names with matched time patterm
					for d in regex.search_all(dir_name):
						if d.get_string() > prev_backup:
							prev_backup = dir_name

				dir_name = dir.get_next()
			result.value = prev_backup
		else:
			result.value = prev_backup
		return result

	# Convert/cleanup all rsync_args into a formatted string for display purposes
	func rsync_args_to_template() -> String:

		if dry_run_enabled == "Y":
			if load_conf: rsync_args.dry_run_argument = conf.dry_run_argument
		else:
			rsync_args.dry_run_argument = ""

		# Populate arguments to string using the template
		var dict_args: Dictionary = get_props(rsync_args)
		var sarguments = rsync_template.format(dict_args)
		return sarguments

	# Push configuration error message to end of list.
	# Must be Result class formatted
	func push_error_message(result: Variant):
		cfg_error_messages.append(result)
		pass

	func clear_error_message():
		cfg_error_messages.clear()
		pass

# Get rsync_args key/values into a Dictionary
# To be used by OS.execute()
static func get_props(rsync_args: Variant) -> Dictionary:
	var props = {}
	var flags = PROPERTY_USAGE_SCRIPT_VARIABLE
	for prop in rsync_args.get_property_list():
		if(prop.usage & flags > 0):
			props[prop.name] = rsync_args.get(prop.name)
	return props

##
## Execute rsync command, write output to log_file
## Preparses the rsync command to be executed using
## OS.execute_with_pipe().
## Return value is an ExecPipeClass object in Result.value but only of Result.code is 0
## and must be started by the UI using execpipe.thread.start()
static func exec_rsync(cmgr: ConfigArgs) -> Result:
	# Populate the template and transfer to sarguments
	var sarguments: String = cmgr.rsync_args_to_template()
	# Create a log file header with info about the backup
	var log_heading: String = ""
	var log_time := Time.get_datetime_string_from_system()
	if cmgr.dry_run_enabled.to_upper() == "Y":
		log_heading = "---- DRY RUN ---- DRY RUN ----\n"
	log_heading = log_heading + "Backup rsync log: " + cmgr.rsync_args.log_file_path + " @ " + log_time + \
			"\n\nCommand Used:\n" + cmgr.rsync_cmd_path + " " + sarguments + "\n\nRsync output: " + log_heading + "\n\n"

	# Clean up whitespaces using regex pattern to make it single line
	var ws_patt := r"\s+|\\"
	var regex = RegEx.new()
	regex.compile(ws_patt)
	# Replace whitespaces with single space
	sarguments = regex.sub(sarguments, ' ', true)

	var arguments = []
	arguments = parse_rsync_arguments(sarguments)
	#prints("\n",sarguments)
	#print(arguments)
	#print("\n\n")
	#for arg in arguments:
		#print(arg)

	var res := Result.new()
	res = save_output_log(cmgr.rsync_args.log_file_path, cmgr.rsync_args.current_datetime + "_log.txt", log_heading)
	if res.code != OK:
		res.description = "rsync Backup LOG FILE failure %s" % res.code
		cmgr.push_error_message(res.description)
		return res

	var value = []
	var code: int = 0
	code = OS.execute(cmgr.rsync_cmd_path, arguments, value, true, false )

	#var execpipe:=ExecPipeClass.new()
	#execpipe.exec_using_pipe(cmgr.rsync_cmd_path, arguments)
	#res.value=execpipe

	res.code = code
	res.value = value
	res.value[0] = log_heading + res.value[0]
	if code != OK:
		res.description = "Error in rsync %s" % [res.code]
	return res

static func parse_rsync_arguments(sarguments: String) -> Array:
	# Parse rsync styled options
	var ws_patt=r'(?<!\S)--?(?<option>[^\s-][^\s=]*)(?:\s*=\s*(?<value>"[^"]*"|\S+))?|[^\s"]+|"([^"]*)"'
	var regex1 = RegEx.new()
	regex1.compile(ws_patt)
	# Get any quoted strings
	var regex2 = RegEx.new()
	regex2.compile(r'(".+?")')
	#
	var send = 0
	var arguments = []
	var arg = regex1.search(sarguments, send, - 1)
	var arg2
	var sstart2=0
	var send2= -1
	var val
	var val2
	while arg != null:
		send = arg.get_end()
		val = arg.strings[0]

		# escape blanks inside quoted strings of each parameter
		# e.g. file names/paths
		arg2=regex2.search(val, 0, - 1)
		if arg2 != null:
			send2=arg2.get_end()
			sstart2=arg2.get_start()
			val2 = arg2.strings[0]
			# if quoted string has blank, than add a \
			val = fix_blanks(sstart2, send2, val, val2)
			pass
		arguments.append(val)
		arg = regex1.search(sarguments, send, - 1)
	return arguments


# Escape by adding \ to blanks in a string. But not if there is already a \
static func fix_blanks(sstart: int, send: int, val: String, val2: String) -> String:
	#prints(sstart, send, val,",String=",val2)
	var si = val2.find(" ")
	if si < 0:
		return val
	val2 = val2.replace(r"\ ", r" ")
	val2 = val2.replace(r" ", r"\ ")
	val2 = val2.replace(r"\'", r"'")
	val2 = val2.replace(r"'", r"\'")
	val = val.substr(0, sstart) + val2
	return val
#
# write tho logfile to a log file
static func save_output_log(log_file_path: String, log_file_name: String, data: String) -> Result:
	var res := Result.new()
	var file: FileAccess

	# If log file path does not exist, create it
	if !DirAccess.open(log_file_path):
		res.code = DirAccess.make_dir_recursive_absolute(log_file_path)
		if res.code == null:
			res.code = DirAccess.get_open_error()
			res.description = "Error %s Could not create log file at %s " % [res.code, res.description]
			return res

	if FileAccess.file_exists(log_file_path.path_join(log_file_name)):
		file = FileAccess.open(log_file_path.path_join(log_file_name), FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(log_file_path.path_join(log_file_name), FileAccess.WRITE)

	if file != null:
		file.seek_end()
		file.store_string(data)
		file.close()
		res.code = OK
	else:
		res.code = FileAccess.get_open_error()
		res.description = "Error {} Could not create log file at {} ".format(res.code, res.description)
	return res
