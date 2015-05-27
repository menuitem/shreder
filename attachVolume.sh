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

attachVolumeToShreder "i-ca23312c" "vol-108c2b0f"