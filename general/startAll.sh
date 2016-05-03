#!/bin/bash

echo "Will attempt to start all defined, non-running VMs"
for i in $(virsh list --all | egrep -v 'Id|---|^$' |  awk '$3!="running"' | awk '{print $2}' | xargs ); do
	set -x
	virsh start $i
	set +x
done

