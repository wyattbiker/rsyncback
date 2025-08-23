@tool
class_name Utils

# Use this class when you want to return either a value or an error code/description.
class Result:
	var code: int=0   # Error Code
	var description: String="" # Error Message
	var value: Variant # Value if no error

# Use this class to verify version format and minimums.
class Version:
	var res: Result=Result.new()
	enum {VERSION=0, MAJOR=1, MINOR=2, PATCH=3}
	#const pattern=r" (?:(\d+)\.)?(?:(\d+)\.)?(\*|\d+) "
	const pattern=r" (\d+)\.(\d+)\.(\d+) "	
	var version: String
	var major: int
	var minor: int
	var patch: int

	func get_version_components(ver: String) -> Version:
		var regex = RegEx.new()
		regex.compile(pattern)
		var version_match=regex.search(ver)
		if !version_match:
			res.code=-1
			res.description="Invalid formatted %s version. Must be must be n.n.n . Please verify" % ver
			return self
		res.code=0
		version=version_match.get_string(Version.VERSION)
		major=version_match.get_string(Version.MAJOR).to_int()
		minor=version_match.get_string(Version.MINOR).to_int()
		patch=version_match.get_string(Version.PATCH).to_int()
		return self

	func version_minimum_check(min_ver:Version)->Version:
		res.code=-1
		res.description="Current_version is %s, minimum version must be %s " % [self.version, min_ver.version]
		# Convert to a dec string for compare
		var this_ver_num = "%04d%04d%04d" % [self.major,self.minor,self.patch]
		var min_ver_num = "%04d%04d%04d" % [min_ver.major,min_ver.minor,min_ver.patch]
		if this_ver_num < min_ver_num:
			#print("Version FAIL This: ",self.version, " Min: ",min_ver.version)
			return self
		res.code=0
		res.description=""
		return self


# Converts and array to a string using the String object.
static func array_to_string(arr:Array) -> String:
	var s_str=""
	for i in arr:
		s_str+=String(i)
	return s_str

static func save_to_file(file_path: String, content: String):
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

static func load_from_file(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	return content

static func open_file_manager(path):
	OS.shell_open(path)
