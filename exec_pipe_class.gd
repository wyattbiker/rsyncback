@tool
# Sets up and executes the OS command
# using threads and OS.execute_with_pipe(bin, args)
class_name ExecPipeClass

var pipe: FileAccess
var stderr: FileAccess
var pid: int
var thread: Thread
var info
signal pipe_in_progress

func exec_using_pipe(bin: String, args: PackedStringArray):
#func init_exec_with_pipe(bin: String, args: PackedStringArray):
	var info = OS.execute_with_pipe(bin, args)
	pipe = info["stdio"]
	stderr=info["stderr"]
	pid=info["pid"]
	thread = Thread.new()
	
func start():
	thread.start(_thread_func)
	
func _thread_func():
	# read stdin and report to log.
	var line:=""
	var pipe_err
	var std_err
	var count=0
	if !pipe.is_open():
		pipe_in_progress.emit.call_deferred("Error opening rsync.", pipe.get_error())
	
	while pipe.is_open():
		pipe_err=pipe.get_error() 
		if pipe_err == OK:
			line=pipe.get_line()
			count+=1
			pipe_in_progress.emit.call_deferred(line)
			pass
		else:
			line=stderr.get_line()
			if line!="":
				pipe_in_progress.emit.call_deferred(line)
			else:
				break
	pipe_in_progress.emit.call_deferred(null)

func clean_thread():
	if thread.is_alive():
		thread.wait_to_finish()
	pipe.close()
	OS.kill(pid)
