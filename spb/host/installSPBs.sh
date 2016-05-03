#!/bin/bash

if [[ -z "$1" ]]; do
        echo "Needs an argument for number of SPBs."
        exit 1
done
NumSpbs=$1
NumVcpus=2
RamMb=4096

for j in $(seq $NumSpbs); do 

	i=$((j-1)) 

	virt-install \
		--name=SPB-$i \
		--disk path=/mnt/qcows/SPB-$i.qcow2c \
		--vcpus=$NumVcpus \
		--ram=$RamMb--cpu host-passthrough \
		--boot hd \
		--network bridge=control,model=virtio \
		--network bridge=service,model=virtio \
		--noautoconsole 
done

