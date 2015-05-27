#!/usr/bin/env bash
	# 1. Check if EC2 volumes ar not attached to a running instance. 
	# 2. if volume is attached to stopped instance then can be attached to a shreder
	#  - we need volume's availability region
	#  - we need to know if shreder exists in the proper region, otherwise it must be created (micro machine)
	#  - we need detach volume from stopped instance and reattach it back to it.
	# 3. once the volume is attached we need to mount it and list its content 
	#  - check volumes logical partitions
	#  - create mount points volumeId+logical  

# $0 - script name
# $# - total number of arguments
# $@, $* - return all arguments

# Global variables
declare -A devices     # Create an associative array
red='\033[1;31m'
green='\033[1;32m'
nc='\033[0m' # no color
west1a="not set" #"eu-west-1a"
west1b="not set" #"eu-west-1b"
west1c="not set" #"eu-west-1c"

isVolumeLive (){
	# This function returns 0 if volume is attached to stopped instance, 1 is returned otherwise.
	# The function takes one argument ($1 in bash) wich is EC2 volume's id.
	instanceID=$(aws ec2 describe-volumes --volume-ids $1 | gawk '/ATTACHMENTS/ {print $5}')
	if [[ instanceID != "" ]]; then
		instanceState=$(aws ec2 describe-instances --instance-ids $instanceID | gawk '/^STATE[	 ]/ {print $3}')
	else
		instanceState="";
	fi
	[[ $instanceState = "stopped" ]] && state="${green}stopped${nc}" || state="${red}running${nc}"
	printf "$1 belongs to instance $instanceID which is in $state state. "
	[[ $instanceState = "stopped" || $instanceState = "" ]] && return 0 || return 1 

}

instanceStartHelper (){
	# this function take one parameter ($1) which is the AWS zone availability suffix, e.g. A,B,C  
	shrederTagName="shreder$1"
	shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|head -1)
			[[ $shrederState = "" || $shrederState = "terminated" ]] && shrederState="${red}does not exist. ${nc}" || : ; 
			printf "$shrederTagName state: $shrederState\n"
			if [[ "$shrederState" = "stopped" ]]; then
				shrederId=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/INSTANCES.*/{print $8}')
				printf "Starting $shrederTagName.\n"
				aws ec2 start-instances --instance-ids $shrederId
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|head -1)
					printf "."
					sleep 5 # move this "while" loop out so it is not blocking the script
				done
				printf "\n $shrederTagName state: $shrederState\n"
			elif [[ "$shrederState" = "" || "$shrederState" = "${red}does not exist. ${nc}" ]]; then
				printf "Creating new shreder instance $shrederTagName \n"
				shrederId=$(aws ec2 run-instances --image-id ami-d75bd5a0 --instance-type t1.micro --key-name VPN-key --count 1 --security-groups shreder-group --placement AvailabilityZone=$availabilityZone|gawk '/INSTANCES/ {print $8}')
				aws ec2 create-tags --resources $shrederId --tags Key=Name,Value=$shrederTagName
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|head -1)
					printf "."
					sleep 5 # move this "while" loop out so it is not blocking the script
				done	
			fi
		shrederId=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/INSTANCES.*/{print $8}')
}

startOrCreateShreder (){
	availabilityZone=$1
	case $availabilityZone in
		'eu-west-1a')
			instanceStartHelper "A"
			;;
		'eu-west-1b')
			instanceStartHelper "B"
			;;
		'eu-west-1c')
			instanceStartHelper "C"
			;;
		*)  printf "Availability zone $availabilityZone is not supported ATM\n"
			;;
	esac

}

attachVolumeToShreder (){ # $1 parameter is a shreder instance Id, $2 is a vloume to attach
	blockPrefix="xvd"
	blocksCount=$(aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*$blockPrefix/"|wc -l)
	blockSuffixOrdinal=$((97 + $blocksCount))
	blockSuffix=\\$(printf "%o" $blockSuffixOrdinal)
	blockName="$blockPrefix$(printf $blockSuffix)"
	blockSuffixOrdinal=96 #reset counter
	isBlockNameInUse=$(aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*\/dev\/$blockName/"|wc -l)
	while [ "$isBlockNameInUse" -eq 1 -a "$blockSuffixOrdinal" -le 121 ]; do #if 0 returned then the blocke name is in use already 
		let "blockSuffixOrdinal++"
		blockSuffix=\\$(printf "%o" $blockSuffixOrdinal)
		blockName="$blockPrefix$(printf $blockSuffix)"
		isBlockNameInUse=$(aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*\/dev\/$blockName/"|wc -l)
	done
	blockDevice="/dev/${blockName}"
	printf "Attaching volume $2 to $1 as $blockDevice device.\n"
	aws ec2 attach-volume --volume-id $2 --instance-id $1 --device "$blockDevice"
}


detachVolume (){ # funtion parameters: $1 volume-id
	# # This function will detach volume from not running instance, 
	# 1. get a mount device
	# 2. remember it / consider write it to file later
	# 3. detach and reattach with  
	
	devicesMountDevice=$(aws ec2 describe-volumes --volume-ids $1 |gawk '/ATTACHMENTS/ { print $4 }')
	devicesInstanceId=$(aws ec2 describe-volumes --volume-ids $1 |gawk '/ATTACHMENTS/ { print $5 }')
	devices[$1]=$devicesMountDevice
	devices[$1Instance]=$devicesInstanceId
	echo "Detaching volume $1 from ${devices[$1Instance]} mounted as $devicesMountDevice device"
	aws ec2 detach-volume --volume-id $1
}

reattachVolume(){ # funtion parameters: $1 volume-id
	# This function will rettach volume to proper instance as a proper device instance, 
	# 1. get mount device, and instance from "devices" associative array  
	# 2. reattach
	# 3. clear the record in "devices" associative array 
	
	# echo "${!devices[@]}"
	# for e in "${!devices[@]}"; do echo $e -> ${devices[$e]}; done
	
	echo "Reattaching volume $1 to instance ${devices[$1Instance]} as ${devices[$1]} device."
	aws ec2 attach-volume --volume-id $1 --instance-id ${devices[$1Instance]} --device ${devices[$1]}
}

volumes=$*
for volume in ${volumes} ; do
	isVolumeLive $volume
	if [[ $? -eq 0 ]]; then
		printf "${green}The content on the $volume volume can be listed ${nc}\n"
		volumeZone=$(aws ec2 describe-volumes --volume-ids $volume|gawk '/VOLUMES/ {print $2}')
		startOrCreateShreder $volumeZone
		# detach from running instances
		attachVolumeToShreder $shrederId $volume
		# list content / shred the volume
		# detach from shreder
		#reattach / dispose
	else 
		printf "${red}The content on $volume volume can not be listed ${nc}\n"
	fi
done;

# instanceStartHelper ZoneA