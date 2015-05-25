#!/usr/bin/env bash
	# 1. Check if EC2 volumes ar not attached to a running instance. 
	# 2. if volume is attached to stopped instance then can be attached to a shreder
	#  - we need volume's availability region
	#  - we need to know if shreder exists in the proper region, otherwise it must be created (micro machine)
	# 3. once the volume is attached we need to mount it and list its content 
	#  - check volumes logical partitions
	#  - create mount points volumeId+logical  

# $0 - script name
# $# - total number of arguments
# $@, $* - return all arguments

red='\033[1;31m'
green='\033[1;32m'
nc='\033[0m' # no color

isVolumeLive (){
	# This function returns 0 if volume is attached to stopped instance, 1 is returned otherwise.
	# The function takes one argument ($1 in bash) wich is EC2 volume's id.
	instanceID=$(aws ec2 describe-volumes --volume-ids $1 | gawk '/ATTACHMENTS/ {print $5}')
	instanceState=$(aws ec2 describe-instances --instance-ids $instanceID | gawk '/^STATE[	 ]/ {print $3}')
	[[ $instanceState = "stopped" ]] && state="${green}stopped${nc}" || state="${red}running${nc}"
	printf "$1 belongs to instance $instanceID which is in $state state.\n"
	[[ $instanceState = "stopped" ]] && return 0 || return 1 
}

# findOrCreateShreder (){
	
# }

volumes=$*
for volume in ${volumes} ; do
	isVolumeLive $volume
done;