#!/bin/bash

echo "Will attempt to shutdown all running VMs (this is a graceful shutdown)"
for i in $(virsh list | egrep -v 'Id|---|^$' | awk '{print $1}' | xargs ); do 
	set -x
	virsh shutdown $i
	set +x
done
