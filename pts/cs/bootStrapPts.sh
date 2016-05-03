#!/bin/bash
#
# [ This script is expected to be in /root/cs folder of PTS VM ]
#
# Script used to bootstrap a PTS.
# Expectation is for this to be run in /etc/rc.d/rc.local
#    (note, one must make sure the execute bit of rc.local are on). 
#
# This script, while run as part of initialization in rc.local, will wake up
# and run in "auto-detect" mode.  It will check it's eth1 ip, then check 
# the DPI1.mapping, DPI2.mapping, moreSDE.mapping, moreSPB.mapping  and 
# customer.mapping files (which might exist in mappings sub-folder in git, but should
# end up existing in /root/cs folder of PTS), to figure out what the
# corresponding sde and spb IPs are and which dpi blade this VM is to live on.
# Then the PTS will self-configure itself (policy files, rc.conf, etc.).
#
# Note, the default control centre SPB IP is set directly in this script below
# and does not come from mapping files.
#
# Manual mode:  This script can be run manually whilst specifying specific
#               items that this script would normally auto detect. See
#				optional arguments below for more details.
#
#

DEFAULT_CC_IP=192.168.122.250

scriptName=$(basename "$0")

# Optional Arguments:
# --dpi-num=<the number 1 or 2> to denote which blade we're on
# --sde-ip=<ip of sde>
# --spb-ip=<ip of spb>
# --cc-ip=<ip of control centre spb>
# --revert    ... this causes configs to be reverted to defaults
sdeIp=""
spbIp=""
ccIp=""
dpiNum=""
for i in "$@"
do
case $i in
        --dpi-num=*)
                dpiNum="${i#*=}"
                shift
                ;;
        --sde-ip=*)
                sdeIp="${i#*=}"
                shift
                ;;
        --spb-ip=*)
                spbIp="${i#*=}"
                shift
                ;;
        --cc-ip=*)
                ccIp="${i#*=}"
                shift
                ;;
        --revert)

## We check if various backup files (that this script intends to modify) exist, and revert them...

revertHappened=0
#(1) Diameter peer config:
diamPeerConfig=/usr/local/sandvine/etc/diam_peer_config.xml
diamPeerConfigBackup=/usr/local/sandvine/etc/diam_peer_config.xml.bootstrap
if [[ -e $diamPeerConfigBackup ]]; then
    echo "Found file <$diamPeerConfigBackup>. Reverting this into <$diamPeerConfig>."
	mv $diamPeerConfigBackup $diamPeerConfig
	revertHappened=1
fi

# (2) Diameter policy config file:
diamConfig=/usr/local/sandvine/etc/policy.pts.cs.diameter_config.conf
diamConfigBackup=/usr/local/sandvine/etc/policy.pts.cs.diameter_config.conf.bootstrap
if [[ -e $diamConfigBackup ]]; then
	echo "Found file <$diamConfigBackup>. Reverting this into <$diamConfig>."
	mv $diamConfigBackup $diamConfig
	revertHappened=1
fi

# (3) Policy file:
policyFile=/usr/local/sandvine/etc/policy.conf
policyFileBackup=/usr/local/sandvine/etc/policy.conf.bootstrap
if [[ -e $policyFileBackup ]]; then
	echo "Found file <$policyFileBackup>. Reverting this into <$policyFile>."
	mv $policyFileBackup $policyFile
    revertHappened=1
fi

# (4) rc.conf (for spb and cc spb configs):
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

# Bug with record generator reload script.  Workaround, do svreload from sandvine etc dir.
function svreloadNoError () {
        cd /usr/local/sandvine/etc
        svreload
        cd -
}

# Logging errors
logPrefix="CloudServices PTS Bootstrap: "
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
ipAddress=$(ifconfig eth1 | grep -v inet6 | grep inet | awk '{print $2}' )
if (( $? !=0 )); then
	printErrorExit "Cannot find ip address for eth1. Expectation was for DHCP broadcast to be used to assign ip to this interface"
fi

# Check that IP is well-defined...
if [[ ! $ipAddress =~ [0-9]+.[0-9]+.[0-9]+.[0-9]+ ]] ; then
	printErrorExit "The extracted v4 ip on eth1 <$ipAddress> seems to be malformed or incorrect."
fi
echo "Successfully found eth1 interface v4 ip <$ipAddress>"

# If user did not provide dpi blade number to script, attempt to determine it...
if [[ -z $dpiNum ]]; then
    echo "A dpi number was not provided as an argument to this script.  Will attempt to determine this automatically"

	# Check both DPI1.mapping and DPI2.mapping to see which file the ip address lives in
	DPI=$(egrep "$ipAddress($| |\t)" DPI*.mapping | cut -f1 -d: | cut -f1 -d\.)

	if [[ ! $DPI =~ DPI[12] ]] ; then
		printErrorExit "Cannot seem to determine dpi blade number from eth1 ip address and mapping files"
	fi

	if [[ $DPI == DPI1 ]]; then
		dpiNum=1
	else
		dpiNum=2
	fi

	echo "Auto determined the dpi blade number to be <$dpiNum>"
fi

# Now that we know blade number, we know which DPI1.mapping vs. DPI2.mapping
dpiMappingFile=DPI${dpiNum}.mapping

echo "Will attempt to find the VPNFNN for customer from the dpi blade mapping file <$dpiMappingFile>"

# Find VPNFNN number for the customer this PTS manages
VPNFNN=$(egrep -h "$ipAddress($| |\t)" $dpiMappingFile | awk '{print $1}')
if [[ ! $VPNFNN =~ N[0-9]+R ]]; then
        printErrorExit "Extracted VPNFNN from mapping file <$dpiMappingFile> was <$VPNFNN>, which looks malformed"
fi
echo "Auto-determined the VPNFNN to be <$VPNFNN>"

# Find the VLANS this PTS is supposed to manage
echo "Will attempt to find the VLANs associated with VPNFNN for this customer."
managedVlans=$(grep "$VPNFNN" customer.mapping | awk '{print $2}' | xargs)
if [[ -z $managedVlans ]]; then
        printErrorExist "Could not determine vlans.  Came up with an empty list. Please investigate."
fi
echo "Determined that the vlans for customer are <$managedVlans>"

vlanFNNs=$(grep "$VPNFNN" customer.mapping | awk '{print $5}' | xargs)
if [[ -z $vlanFNNs ]]; then
    printErrorExist "Could not determine vlans FNNs.  Came up with an empty list. Please investigate."
fi
echo "Above list of vlans corresponding to VLANFFNs <$vlanFNNs>"

# If user did not supply a sde ip with script argument, try to auto determine this...
if [[ -z $sdeIp ]]; then
	echo "Since a sde ip was not provided as argument to this script, attempting to determine this automatically..."
	sdeIp=$(grep -h "$VPNFNN" moreSDE.mapping moreSPB.mapping | grep SDE | awk '{print $4}')
	echo "Determined that sde ip is <$sdeIp>"
fi

# If usre did not supply a spb ip with script argument, try to auto determine this...
if [[ -z $spbIp ]]; then
	echo "Since a spb ip was not provided as argument to this script, attempting to determine this automatically..."
	spbIp=$(grep -h "$VPNFNN" moreSDE.mapping moreSPB.mapping | grep SPB | awk '{print $4}')
	echo "Determined that spb ip is <$spbIp>"
fi

echo -e "Will now attempt to self configure for:\nSDE with service ip <$sdeIp> and SPB with service ip <$spbIp>"

# Configure SDE IPs (for svsde, csd, ga diam peers) in diam_peer_config.xml
diamPeerConfig=/usr/local/sandvine/etc/diam_peer_config.xml
diamPeerConfigBackup=/usr/local/sandvine/etc/diam_peer_config.xml.bootstrap
if [[ -e $diamPeerConfigBackup ]]; then
	cp $diamPeerConfigBackup $diamPeerConfig
fi
cp $diamPeerConfig $diamPeerConfigBackup
sed -i -e "s/192.168.192.140/$sdeIp/g" $diamPeerConfig
echo "Modified <$diamPeerConfig> to account for sde ip <$sdeIp>"

# Configure PTS name in diameter config policy file
diamConfig=/usr/local/sandvine/etc/policy.pts.cs.diameter_config.conf
diamConfigBackup=/usr/local/sandvine/etc/policy.pts.cs.diameter_config.conf.bootstrap
if [[ -e $diamConfigBackup ]]; then
	cp $diamConfigBackup $diamConfig
fi
cp $diamConfig $diamConfigBackup
sed -i -e "s/pts/pts${dpiNum}/g" $diamConfig
echo "Modified <$diamConfig> policy file to change pts name to <pts${dpiNum}>"

# Create policy.conf
newPolicyFile=policy.conf.new
touch $newPolicyFile

{
echo "classifier \"LinkData\" type string"
echo
echo -e "PolicyGroup\n{\n"
IFS=$' '
for vlanFNN in $vlanFNNs; do

	vlan=$(grep "$vlanFNN" customer.mapping | awk '{print $2}')

	echo -e "\t# Link/site will be <VPNFNN>-<VLANFNN> with 1 or 2 suffix to denote dpi blade"
	echo -e "\tif expr((Flow.Subscriber.Tx.Vlan=$vlan) or (Flow.Subscriber.Rx.Vlan=$vlan)) then set Classifier.LinkData = \"$VPNFNN-$vlanFNN${dpiNum}\""
	echo
done

echo -e "\t# Unexpected VLAN tags will be labelled with this link/site ..."
echo -e "\tif true then set Classifier.LinkData = \"Default\""
echo
echo -e "}"
echo

echo "include \"/usr/local/sandvine/etc/policy.pts.cs.main.conf\""
echo "include \"/usr/local/sandvine/etc/policy.pts.cs.custom_policies.conf\""
echo "include \"/usr/local/sandvine/etc/policy.pts.cs.telstra.conf\""

} > $newPolicyFile

# Back up original policy file and put the new one in its place
policyFile=/usr/local/sandvine/etc/policy.conf
policyFileBackup=/usr/local/sandvine/etc/policy.conf.bootstrap
if [[ -e $policyFileBackup ]]; then
	cp $policyFileBackup $policyFile
fi
cp $policyFile $policyFileBackup
mv $newPolicyFile $policyFile

echo "Created a new policy.conf file customized for the vlans this PTS will see"

if [[ -z $ccIp ]]; then
    echo "Since a cc spb ip was not provided as argument to this script, using default one set at top of script <$DEFAULT_CC_IP>"
	ccIp=$DEFAULT_CC_IP
else
   echo "You passed in cc ip of <$ccIp>.  Using this to configure rc.conf."
fi

rcConfFile=/usr/local/sandvine/etc/rc.conf
rcConfFileBackup=/usr/local/sandvine/etc/rc.conf.bootstrap
if [[ -e $rcConfFileBackup ]]; then
	cp $rcConfFileBackup $rcConfFile
fi
cp $rcConfFile $rcConfFileBackup

# Replace the spb (subs/stats) ip that's in rc.conf
sed -i -e "s/192.168.192.130/$spbIp/g" $rcConfFile

echo "Modified rc.conf to account for stats/subs spb ip <$spbIp>"

# We also need to first append CC spb ip into rc.conf
cat <<EOF >>$rcConfFile

cluster_name="PTS$VPNFNN-$vlanFNN${dpiNum}"

spb_domains="spbDomainsControlCenterSPB"
spbDomainsControlCenterSPB__domain="Control_Center_SPB"
spbDomainsControlCenterSPB__servers="$ccIp"
spbDomainsControlCenterSPB__roles="control"
EOF

echo "Appended configs into rc.conf to point to control centre spb with ip <$ccIp>"

svreloadNoError || printErrorExit "svreload failed... please investigate."
