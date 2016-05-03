#!/bin/bash

echo "Will attempt to destroy all running VMs (this is a non-graceful shutdown)"
for i in $(virsh list | egrep -v 'Id|---|^$' | awk '{print $1}' | xargs ); do 
	set -x
	virsh destroy $i 
	set +x
done
