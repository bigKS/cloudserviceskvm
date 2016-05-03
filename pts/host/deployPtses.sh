#!/bin/bash

scriptName=$(basename "$0")
## This script takes a master PTS C.S. QCOW and makes slave ones for every PTS to be run on this blades

# Control bridge... we prefer that this is a fake bridge connected to nowhere..
controlBridge=control

# Service bridge... 
serviceBridge=service

## Arguments
# Arg1:  Full path to master images
# Arg2:  Full path to location where the slave images should be created
# Arg3:  The number 1 or number 2 
# Arg4:  The number of PTSes to create
numArgs=4

# Each PTS image name will be "dpiY-ptsX" where Y is 1 or 2 (denoting dpi blade number) and X is PTS number (starting with number 1)
function printUsageExit ()
{
	{
	echo
	echo "Usage:"
	echo "$scriptName <directory with pts images> <number 1 or 2 for dpi blade> <sub bridge> <int bridge> <number of PTSes>"
	echo
	echo "Synopsis:"
	echo "Will create PTS qcow disk images from a master qcow with the filenames dpiY-ptsX.qcow2c" 
	echo "where Y is 1 or 2 to denote blade, and X is a number starting from 1 and going upto the number of PTS images to create"
	echo 
	} >&2

	exit 1
}


function printErrorExit () {
    echo -e "\nERROR: $@" >&2
	printUsageExit
}


[[ $# == $numArgs ]] || printErrorExit "Number of arguments to script must be <$numArgs> but only <$#> were supplied"

masterImagePath=$1
slaveImageDirectory=$2
dpiNum=$3
numPts=$4

# Error check on master image argument
[[ -e $masterImagePath ]] || printErrorExit "The path to master image <$masterImagePath> supplied does not seem to correlate to a file."
[[ $(basename $masterImagePath) =~ .*pts.*cs.*\.qcow2c ]]  || printErrorExit "The master image <$masterImagePath> does not see to have reasonable file name of a pts c.s. qcow image."

# Error check on slave image argument
[[ -d $slaveImageDirectory ]] || printErrorExit "Directory path to store slave images suppled <$slaveImageDirectory> does not seem to exist."
ls "$slaveImageDirectory"/dpi*-pts*.qcow2c &> /dev/null  &&
	printErrorExit "Directory path to store slave images already has pts slave qcows in it. Please rectify this."

# Error check on dpi number
[[ $dpiNum == "1" ]] || [[ $dpiNum == "2" ]] || printErrorExit "The third argument should be number 1 or 2 to denote dpi blade. You supplied <$dpiNum>"

# Error check on num pts
[[ $numPts =~ [1-9][0-9]* ]] || printErrorExit "Fourth argument should be a positive integer to denote the number of PTS slave images to create. You supplied <$numPts>"

echo "You have supplied what seem like reasonable arguments to this script, will attempt to create slave pts images in location specified..."
echo 

# Create the pts slave images
for iter in $(seq $numPts); do

	ptsImageFilename="dpi${dpiNum}-pts${iter}.qcow2c"

	echo "Attempting to create pts slave image <$ptsImageFilename>...	"

	set -x
	qemu-img convert -f qcow2 -O qcow2 "$masterImagePath" "$slaveImageDirectory/$ptsImageFilename"
	status=$?
	set +x

	(( $? == 0 )) || printErrorExit "Creating of <iter>-th pts slave image seems to have failed. Please investiagte"

	echo "Slave image creation seems to have succeeded."
done

echo "It seems that all slave images have been created successfully.  Please do a sanity look over of <$slaveImageDirectory> before deploying the PTSes..."

virt-install --name=DPI2-PTS1 --disk path=/mnt/qcows/DPI2-PTS1.qcow2c --vcpus 3 --ram 3072 --cpu host-passthrough --boot hd --network bridge=control,model=virtio --network bridge=service,model=virtio,mac=52:54:00:00:11:01 --network bridge=sub100,model=virtio --network bridge=int100,model=virtio --noautoconsole
