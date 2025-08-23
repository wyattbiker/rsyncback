extends Resource

# Default config.
class_name DefaultConfig

@export_category("Rsync Configuration Arguments")

## The backup folder path. 
## The backup will be in {dest_path}/{project_name}/{current_datetime}
@export_global_dir var dest_path=""
	
## Filename of rsync exclude file found in same 
## folder as the rsyncback plugin.
## If left empty nothing will be excluded.
@export var  exclude_file_path="exclude.txt"

## Format of {current_datetime} .
## If empty will use "%d-%02d-%02dT%02d_%02d_%02d" 
@export var  time_stamp_format="[%04d-%02d-%02d][%02d_%02d_%02d]"

## Minimum rsync version. [i][color=green]Must be in x.x.x format.
@export var rsync_min_version="3.2.4"

## Add this to the end of the generated logfile name
## So in effect the logfile name will be
## {current_datetime}{log_file_suffix}
@export var  log_file_suffix="_log.txt"	

## Log files will be stored in this path 
## as {current_datetime}_log.txt files. If left empty
## the folder path will be {dest_path}/logfiles/
@export_global_dir var  log_file_path=""	

## rsync arguments and place holders to use in rsync template command
## rsync command. Uses "which" to find full path
@export_global_dir var rsync_cmd_path="rsync"		

## --dry-run rsync argument. [b]Do not change[/b]. Will only be used if 
## explictily checked before running.				
@export var  dry_run_argument="--dry-run"		


@export_category("Rsync Arguments Template")

##rsync command template populated with cfg keys.
##You may customize it, but do verify using preview option.
##Arguments must be inside quotes.
@export_multiline var rsync_template = r"""{dry_run_argument} -avih --mkpath --stats  \
 --out-format="%M %15'l %5f"  \
 --exclude-from="{exclude_file_path}" \
 --link-dest="{dest_path}/{project_name}/{prev_backup}" \
 --log-file-format="%M %15'l %5f" \
 --log-file="{log_file_path}/{current_datetime}{log_file_suffix}" \
 "{source_path}" \
 "{dest_path}/{project_name}/{current_datetime}" """

#@export_category("Calculated Arguments. Leave Empty")
## Project name place holder, joined to dest_path.[br]
## Leave empty will use current project name
var project_name=""								
																				
## Generated new backup folder name. leave empty.
## Uses time_stamp_format.
var current_datetime=""								
												
## Path to your project source files. Leave empty
## to grab your current project folder res://.
var  source_path=""									
																							
## Link to the latest backup place holder. Leave blank 
## Calculated at runtime. 
var  prev_backup=""

# Comments
#  ssh example
#  rsync -azhv -e "ssh -p 2212" --dry-run /home/user1/test_200719 --delete-after 
#         --dry-run root@5x.136.xxx.121:/home/user1/test_200719

		
