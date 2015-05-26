attachVolumeToShreder (){ # $1 parameter is a shreder instance Id, $2 is a vloume to attach
	blockPrefix="xvd"
	blocksCount=$(aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*$blockPrefix/"|wc -l)
	blockSuffixOrdinal=$((97 + $blocksCount))
	# blockSuffix="\\$(printf '%03o' "$blockSuffixOrdinal")"
	blockSuffix=\\$(printf "%o" $blockSuffixOrdinal)
	blockName="$blockPrefix$blockSuffix"
	printf "\nblocksCount $blocksCount"
	printf "\nblockSuffix $blockSuffix"
	printf "\nblockSuffixOrdinal $blockSuffixOrdinal"
	printf "\nblockPrefix $blockPrefix"
	printf "\nblockName $blockName\n"

	blockSuffixOrdinal=96 #reset counter
	aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*$blockName/"
	while [ "$?" = 0 -a "$blockSuffixOrdinal" -le 121 ]; do
		let "blockSuffixOrdinal++"
		blockSuffix=\\$(printf "%o" $blockSuffixOrdinal)
		blockName="$blockPrefix$blockSuffix"
		aws ec2 describe-instances --instance-ids $1|gawk "/BLOCKDEVICEMAPPINGS.*$blockName/"
	done
		printf "\nblockName _$blockName-\n"
		blockDevice=$(printf "/dev/${blockName}")
		echo "blockDevice $blockDevice"
	aws ec2 attach-volume --volume-id $2 --instance-id $1 --device ${blockDevice}
}

attachVolumeToShreder "i-ca23312c" "vol-108c2b0f"
