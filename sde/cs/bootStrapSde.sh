#!/bin/bash
#
# [ This script is expected to be in /root/cs folder of SDE VM ]
#
# Script used to bootstrap a SDE (which has CSD/Influx on it too)
# Expectation is for this to be run in /etc/rc.d/rc.local
#    (note, one must make sure the execute bit of rc.local are on). 
#
# This script, while run as part of initialization in rc.local, will wake up
# and run in "auto-detect" mode.  It will check it's eth1 ip, then check 
# the DPI1.mapping, DPI2.mapping, moreSDE.mapping, moreSPB.mapping  and 
# customer.mapping files (which might exist in mappings sub-folder in git, but should
# end up existing in /root/cs folder of SPB), to figure out what the
# corresponding sde and spb IPs are and which dpi blade this VM is to live on.
# Then the SDE will self-configure itself (csd.conf, rc.conf, etc.).
#
# Manual mode:  This script can be run manually whilst specifying specific
#               items that this script would normally auto detect. See
#				optional arguments below for more details.
#
#

scriptName=$(basename "$0")

# Optional Arguments:
# --pts1-ip=<ip of PTS being managed on blade 1>
# --pts2-ip=<ip of PTS being managed on blade 2>
# --spb-ip=<ip of spb>
# --revert    ... this causes configs to be reverted to defaults
pts1Ip=""
pts2Ip=""
spbIp=""
for i in "$@"
do
case $i in
        --spb-ip=*)
                spbIp="${i#*=}"
                shift
                ;;
        --pts1-ip=*)
                pts1ip="${i#*=}"
                shift
                ;;
        --pts2-ip=*)
                pts2ip="${i#*=}"
                shift
                ;;
        --revert)

## We check if various backup files (that this script intends to modify) exist, and revert them...

revertHappened=0
#(1) csd config:
csdConf=/etc/csd.conf
csdConfBackup=/etc/csd.conf.bootstrap
if [[ -e $csdConfBackup ]]; then
    echo "Found file <$csdConfBackup>. Reverting this into <$csdConf>."
	mv $csdConfBackup $csdConf
	revertHappened=1
fi

#(2) Diameter peer config:
diamPeerConfig=/usr/local/sandvine/etc/diam_peer_config.xml
diamPeerConfigBackup=/usr/local/sandvine/etc/diam_peer_config.xml.bootstrap
if [[ -e $diamPeerConfigBackup ]]; then
    echo "Found file <$diamPeerConfigBackup>. Reverting this into <$diamPeerConfig>."
	mv $diamPeerConfigBackup $diamPeerConfig
	revertHappened=1
fi

# (3) rc.conf (for spb and cc spb configs):
rcConfFile=/usr/local/sandvine/etc/rc.conf
rcConfFileBackup=/usr/local/sandvine/etc/rc.conf.bootstrap
if [[ -e $rcConfFileBackup ]]; then
	echo "Found file <$rcConfFileBackup>. Reverting this into <$rcConfFile>."
	mv $rcConfFileBackup $rcConfFile
	revertHappened=1
fi

if (( revertHappened == 1 )); then
	echo "Reverting finished."
else
	echo "There is nothing to revert."
fi

exit 0
;;

esac
done

# Redirect stderr to bit bucket
exec 2>/dev/null

# Change into the root directory of this script
scriptDir=/root/cs
cd $scriptDir

# svreload
function svreloadNoError () {
        svreload
}

# Logging errors
logPrefix="CloudServices SDE Bootstrap: "
function printErrorExit () {

	# Send logs to svlog and screen...
	echo "$logPrefix: $(date): FATAL ERROR: $@" | tee -a /var/log/svlog
	exit 1
}

## Main part of script starts here:

# Check that interface eth1 exists
ifconfig eth1 1> /dev/null || printErrorExit "Cannot find eth1 using ifconfig."

# Attempt to find our ip address (v4)
echo "Will attempt to find eth1 interface, and the v4 ip it was assigned..."
ipAddress=$(ifconfig eth1 | grep -v inet6 | grep inet | awk '{print $2}' | cut -d: -f2  )
if (( $? !=0 )); then
	printErrorExit "Cannot find ip address for eth1. Expectation was for DHCP broadcast to be used to assign ip to this interface"
fi

# Check that IP is well-defined...
if [[ ! $ipAddress =~ [0-9]+.[0-9]+.[0-9]+.[0-9]+ ]] ; then
	printErrorExit "The extracted v4 ip on eth1 <$ipAddress> seems to be malformed or incorrect."
fi
echo "Successfully found eth1 interface v4 ip <$ipAddress>"

# Determine customer VPN FNN number
ipLineInMappingFile=$(egrep -h "$ipAddress($|\t| )" more*.mapping)

if [[ -z $ipLineInMappingFile ]] || (( $(echo "$ipLineInMappingFile" | wc -l ) != 1 )); then
	printErrorExist "Cannot seem to find ip address in the SDE/SPB mapping files. Grep in these files for up came up with <$ipLineInMappingFile>"
fi

# Extract VPNFNN from the line extracted from mapping file
VPNFNN=$(echo "$ipLineInMappingFile" | awk '{print $1}' )
if [[ ! $VPNFNN =~ N[0-9]+R ]]; then
        printErrorExit "Extracted VPNFNN from ip line in mapping file <$ipLineInMappingFile> was <$VPNFNN>, which looks malformed"
fi

# If user did not provide pts1 ip to this script...
if [[ -z $pts1Ip ]]; then
	echo "Ip for PTS1 was not provided as an argument to this script. Will attempt to determine this automaticall"

	# PTS1's ip lives in this file
	dpi1MappingFile=DPI1.mapping

	# Extract the PTS IP
	pts1Ip=$(grep "$VPNFNN" "$dpi1MappingFile" | awk '{print $4}')

	# Check that IP is well-defined...
	if [[ ! $pts1Ip =~ [0-9]+.[0-9]+.[0-9]+.[0-9]+ ]] ; then
	    printErrorExit "The extracted PTS1 ip <$pts1Ip> seems to be malformed or incorrect."
	fi
	echo "Successfully found PTS1 ip <$pts1Ip>"

fi

# If user did not provide pts2 ip to this sript...
if [[ -z $pts2Ip ]]; then
    echo "Ip for PTS2 was not provided as an argument to this script. Will attempt to determine this automatically"

    # PTS1's ip lives in this file
    dpi2MappingFile=DPI2.mapping

    # Extract the PTS IP
    pts2Ip=$(grep "$VPNFNN" "$dpi2MappingFile" | awk '{print $4}')

    # Check that IP is well-defined...
    if [[ ! $pts2Ip =~ [0-9]+.[0-9]+.[0-9]+.[0-9]+ ]] ; then
        printErrorExit "The extracted PTS2 ip <$pts2Ip> seems to be malformed or incorrect."
    fi
    echo "Successfully found PTS2 ip <$pts2Ip>"

fi

if [[ -z $spbIp ]]; then
	echo "Ip for SPB(stats) was not provided as an argument to this script. Will attempt ot determin this automatically."

	spbIp=$(grep -h "$VPNFNN" more*.mapping | egrep -v "$ipAddress($|\t| )" | awk '{print $4}')

	# Check that IP is well-define...	
    if [[ ! $spbIp =~ [0-9]+.[0-9]+.[0-9]+.[0-9]+ ]] ; then
        printErrorExit "The extracted PTS2 ip <$spbIp> seems to be malformed or incorrect."
    fi
    echo "Successfully found SPB ip <$spbIp>"
fi

echo -e "Will now attempt to self configure for:\nSPB with service ip <$spbIp> and\nPTS1,PTS2 with service IPs <$pts1Ip>, <$pts2Ip>."

csdConf=/etc/csd.conf
csdConfBackup=/etc/csd.conf.bootstrap
if [[ -e $csdConfBackup ]]; then
	cp $csdConfBackup $csdConf
fi
cp $csdConf $csdConfBackup

# Modify default qcow SPB and SDE Ips in csd.conf
sed -i -e "s/192.168.192.130/$spbIp/g" -e "s/192.168.192.140/$ipAddress/g" $csdConf

echo "Modified csd.conf to account for spb ip and local ip"

rcConfFile=/usr/local/sandvine/etc/rc.conf
rcConfFileBackup=/usr/local/sandvine/etc/rc.conf.bootstrap
if [[ -e $rcConfFileBackup ]]; then
	cp $rcConfFileBackup $rcConfFile
fi
cp $rcConfFile $rcConfFileBackup

# Replace the spb (subs/stats) ip that's in rc.conf
sed -i -e "s/192.168.192.130/$spbIp/g" $rcConfFile

echo "Modified rc.conf to account for stats/subs spb ip <$spbIp>"

# Configure SDE IPs (for svsde, csd, ga diam peers) in diam_peer_config.xml
diamPeerConfig=/usr/local/sandvine/etc/diam_peer_config.xml
diamPeerConfigBackup=/usr/local/sandvine/etc/diam_peer_config.xml.bootstrap
if [[ -e $diamPeerConfigBackup ]]; then
    cp $diamPeerConfigBackup $diamPeerConfig
fi
cp $diamPeerConfig $diamPeerConfigBackup
sed -i -e "s/192.168.192.140/$ipAddress/g" $diamPeerConfig
sed -i -e "s/192.168.192.150/$pts1Ip/g" $diamPeerConfig
sed -i -e "s/192.168.192.151/$pts2Ip/g" $diamPeerConfig

echo "Modified <$diamPeerConfig> to account for CSD(sde), PTS1, and PTS2 IPs"

svreloadNoError || printErrorExit "svreload failed... please investigate."

service csd restart || printErrorExit "csd restart failed... please investigate."
