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
declare -A devices     # Create an associative array (aa)
red='\033[1;31m'
green='\033[1;32m'
nc='\033[0m' # no color
west1a="not set" #"eu-west-1a"
west1b="not set" #"eu-west-1b"
west1c="not set" #"eu-west-1c"
sshKey=$shrederKey #the path to key-file that must be set in your environment
KEY=$(printf $shrederKey |gawk -F/ '{print $NF}'|gawk -F. '{print $1}')
isVolumeLive (){
	# function parameters:  volume ids from command line.
	# This function returns 0 if volume is attached to stopped instance, 1 is returned otherwise.
	instanceID=$(aws ec2 describe-volumes --volume-ids $1 | gawk '/ATTACHMENTS/ {print $5}')
	if [[ "$instanceID" != "" ]]; then
		instanceState=$(aws ec2 describe-instances --instance-ids $instanceID | gawk '/^STATE[	 ]/ {print $3}')
		[[ $instanceState = "stopped" ]] && state="${green}stopped${nc}" || state="${red}running${nc}"
		printf "$1 belongs to instance $instanceID which is in $state state. "
	else
		instanceState="";
		printf "${green}Volume $1 is not attached to any instances.${nc}"
	fi
	[[ $instanceState = "stopped" || $instanceState = "" ]] && return 0 || return 1 

}

instanceStartHelper (){ # function parameters: $1 AWS zone availability suffix, e.g. A,B,C  
	shrederTagName="shreder$1"
	shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|sort -n|head -1)
			[[ $shrederState = "" || $shrederState = "terminated" ]] && shrederState="${red}does not exist. ${nc}" || : ; 
			printf "$shrederTagName state: $shrederState\n"
			if [[ "$shrederState" = "stopped" ]]; then
				shrederId=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/INSTANCES.*/{print $8}')
				printf "Starting $shrederTagName.\n"
				aws ec2 start-instances --instance-ids $shrederId
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|sort -n|head -1)
					printf "."
					sleep 5 # move this "while" loop out so it is not blocking the script
				done
				printf "\n $shrederTagName state: $shrederState\n"
			elif [[ "$shrederState" = "" || "$shrederState" = "${red}does not exist. ${nc}" ]]; then
				printf "Creating new shreder instance $shrederTagName \n"
				shrederId=$(aws ec2 run-instances --image-id ami-d75bd5a0 --instance-type t1.micro --key-name $KEY --count 1 --security-groups shreder-group --placement AvailabilityZone=$availabilityZone|gawk '/INSTANCES/ {print $8}')
				aws ec2 create-tags --resources $shrederId --tags Key=Name,Value=$shrederTagName
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=$shrederTagName|gawk '/STATE[	 ]/ {print $3}'|sort -n|head -1)
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

attachVolumeToShreder (){ # function parameters: $1 shreder instance Id, $2 volume Id to attach
	blockPrefix="xvd"
	blocksCount=$(aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*$blockPrefix/"|wc -l)
	blockSuffixOrdinal=$((99 + $blocksCount))
	blockSuffix=\\$(printf "%o" $blockSuffixOrdinal)
	blockSuffix=$(printf $blockSuffix)
	blockName="$blockPrefix$(printf $blockSuffix)"
	blockSuffixOrdinal=99 #reset counter
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
	volumeStatus=$(aws ec2 describe-volumes --volume-ids $2|gawk '/VOLUMES/ {print $8}')
	
	# aws returns the vol in-use, but the vol is not visble in the os for another 5 1-3 seconds
	sleep 5 #the volume is attaching ans we must wait, need to add check when attaching 
	# while [ "$volumeStatus" != "in-use" ]; do
	# 	volumeStatus=$(aws ec2 describe-volumes --volume-ids $2|gawk '/VOLUMES/ {print $8}')
	# 	printf "$volumeStatus."
	# 	sleep 5 # move this "while" loop out so it is not blocking the script
	# done
}


detachVolume (){ # funtion parameters: $1 volume-id
	# # This function will detach volume from not running instance, 
	# 1. get a mount device
	# 2. remember it in associative array / consider write it to file later
	# 3. detach and reattach with  
	volumeState=$(aws ec2 describe-volumes --volume-ids $1|gawk '/VOLUMES/ {print $8}')
	if [[ "$volumeState" != "available" ]]; then 
		devicesMountDevice=$(aws ec2 describe-volumes --volume-ids $1 |gawk '/ATTACHMENTS/ { print $4 }')
		devicesInstanceId=$(aws ec2 describe-volumes --volume-ids $1 |gawk '/ATTACHMENTS/ { print $5 }')
		devices[$1]=$devicesMountDevice
		devices[$1Instance]=$devicesInstanceId
		echo "Detaching volume $1 from ${devices[$1Instance]} mounted as $devicesMountDevice device"
		aws ec2 detach-volume --volume-id $1
	fi
}

reattachVolume(){ # funtion parameters: $1 volume-id
	# This function will rettach volume to proper instance under correct device name. 
	# 1. get mount device and instance from "devices" associative array  
	# 2. reattach
	# 3. clear the record in "devices" associative array 
	
	# echo "${!devices[@]}" #print all keys in the associative array
	# for e in "${!devices[@]}"; do echo $e -> ${devices[$e]}; done # iterate through aa
	
	echo "Reattaching volume $1 to instance ${devices[$1Instance]} as ${devices[$1]} device."
	aws ec2 attach-volume --volume-id $1 --instance-id ${devices[$1Instance]} --device ${devices[$1]}
	[[ "$?" -eq 0 ]] && { unset devices["$1"]; unset devices["$1Instance"]; } # Clear record from array 
}

runCommandOnShreder(){ 
	# ssh to shreder
	sshOpts="-q -o StrictHostKeyChecking=no -i $sshKey"
	shrederIp=$(aws ec2 describe-instances --instance-ids $shrederId |gawk '/INSTANCES/ {print $16}')
	ssh $sshOpts ubuntu@$shrederIp $*
}

listVolumeContent(){
	# get logical disks on the volume
	volumeBlockNamesCount=$(runCommandOnShreder "ls -l /dev/|grep \"$blockName\""|wc -l)

	echo "$volumeBlockNamesCount"
	if [[ "$volumeBlockNamesCount" -eq 1 ]]; then
		echo "volume_blockSuffix ${volume}_${blockSuffix}"
		echo "blockSuffix $blockSuffix"
		echo "volume $volume"
		runCommandOnShreder "sudo mkdir /${volume}_${blockSuffix};sudo mount $blockDevice /${volume}_${blockSuffix}; sudo ls -laR /${volume}_${blockSuffix} > ${volume}${blockName}_$(date +%Y%m%d:%H%M%S) && sudo umount /${volume}_${blockSuffix};" 
		runCommandOnShreder "test \"$(ls -A /${volume}_${blockSuffix} 2>/dev/null)\" || sudo rm -rf /${volume}_${blockSuffix}"
	fi 
	# create mount points for logical disks
	# runCommandOnShreder "sudo mkdir -p /$volume"
	# mount logical disks
	# list its contents
	# save it to aws S3 bucket
	# umount logical disks
	# delete the mount points   
}

volumes=$*
for volume in ${volumes} ; do
	isVolumeLive $volume
	if [[ $? -eq 0 ]]; then
		printf "${green}The content on the $volume volume can be listed ${nc}\n"
		volumeZone=$(aws ec2 describe-volumes --volume-ids $volume|gawk '/VOLUMES/ {print $2}')
		# detach volume from stopped instance if attached to stopped instance
		detachVolume $volume
		startOrCreateShreder $volumeZone
		attachVolumeToShreder $shrederId $volume
		listVolumeContent
		# list content / shred volume
		# detach from shreder
		#reattach / dispose
	else 
		printf "${red}The content on $volume volume can not be listed ${nc}\n"
	fi
done;
