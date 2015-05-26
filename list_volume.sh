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

# Global variables
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
	instanceState=$(aws ec2 describe-instances --instance-ids $instanceID | gawk '/^STATE[	 ]/ {print $3}')
	[[ $instanceState = "stopped" ]] && state="${green}stopped${nc}" || state="${red}running${nc}"
	printf "$1 belongs to instance $instanceID which is in $state state.\n"
	[[ $instanceState = "stopped" ]] && return 0 || return 1 
}



startOrCreateShreder (){
	availabilityZone=$1
	case $availabilityZone in
		'eu-west-1a')
			shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederA|gawk '/STATE[	 ]/ {print $3}')
			printf "ShrederA state: $shrederState\n"
			if [[ "$shrederState" = "stopped" ]]; then
				shrederAid=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederA|gawk '/INSTANCES.*/{print $8}')
				# aws ec2 describe-instances --instance-ids $shrederAid
				printf "Starting shrederA.\n"
				aws ec2 start-instances --instance-ids $shrederAid
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederA|gawk '/STATE[	 ]/ {print $3}')
					printf "."
					sleep 5 # move this "while" loop so it is not blocking the script
				done
				printf "\nShrederA state: $shrederState\n"
			elif [[ "$shrederState" = "" ]]; then
					newInstance=$(aws ec2 run-instances --image-id ami-d75bd5a0 --instance-type t1.micro --key-name VPN-key --count 1 --security-groups shreder-group --placement AvailabilityZone=$availabilityZone|gawk '/INSTANCES/ {print $8}')
					aws ec2 create-tags --resources $newInstance --tags Key=Name,Value=shrederA
			fi
			;;
		'eu-west-1b')
			shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederB|gawk '/STATE[	 ]/ {print $3}')
			printf "ShrederB state: $shrederState\n"
			if [[ "$shrederState" = "stopped" ]]; then
				shrederBid=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederB|gawk '/INSTANCES.*/{print $8}')
				# aws ec2 describe-instances --instance-ids $shrederBid
				printf "Starting shrederB.\n"
				aws ec2 start-instances --instance-ids $shrederBid
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederB|gawk '/STATE[	 ]/ {print $3}')
					printf "."
					sleep 5 # move this "while" loop so it is not blocking the script
				done
				printf "\nShrederB state: $shrederState\n"
			elif [[ "$shrederState" = "" ]]; then
				aws ec2 run-instances --image-id ami-d75bd5a0 --instance-type t1.micro --key-name VPN-key --count 1 --security-groups shreder-group --placement AvailabilityZone=$availabilityZone 
				aws ec2 create-tags --resources $newInstance --tags Key=Name,Value=shrederB				
			fi
			;;
		'eu-west-1c')
			shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederC|gawk '/STATE[	 ]/ {print $3}')
			printf "ShrederC state: $shrederState\n"
			if [[ "$shrederState" = "stopped" ]]; then
				shrederCid=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederC|gawk '/INSTANCES.*/{print $8}')
				# aws ec2 describe-instances --instance-ids $shrederCid
				printf "Starting shrederC.\n"
				aws ec2 start-instances --instance-ids $shrederCid
				while [ "$shrederState" != "running" ]; do
					shrederState=$(aws ec2 describe-instances --filter Name=tag:Name,Values=shrederC|gawk '/STATE[	 ]/ {print $3}')
					printf "."
					sleep 5 # move this "while" loop so it is not blocking the script
				done
				printf "\nShrederC state: $shrederState\n"

			elif [[ "$shrederState" = "" ]]; then
				aws ec2 run-instances --image-id ami-d75bd5a0 --instance-type t1.micro --key-name VPN-key --count 1 --security-groups shreder-group --placement AvailabilityZone=$availabilityZone 
				aws ec2 create-tags --resources $newInstance --tags Key=Name,Value=shrederC
			fi
			;;
		*)  printf "Availability zone $availabilityZone is not supported ATM\n"
			;;
	esac

	# aws ec2 describe-instances --filter Name=tag:Name,Values=shrederC
}


volumes=$*
for volume in ${volumes} ; do
	isVolumeLive $volume
done;

# startOrCreateShreder "eu-west-1a"
# startOrCreateShreder "eu-west-1b"
# startOrCreateShreder "eu-west-1c"
# startOrCreateShreder "saseu-west-1c"
# b=$([ "a" == "b" ])
# printf "$b"
