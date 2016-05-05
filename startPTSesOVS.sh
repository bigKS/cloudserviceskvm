#!/bin/bash

TEMPLATE_LOCATION=/root/ovsOnly.template.xml

for (( X = 1650; X <= 1695; X++)); do

		# Let i go from 1 ... 25 while X loops over VLANS
		i=$((X-1649))

		controlPortName=pts-ctl-$X
		servicePortName=pts-srv-$X
		subPortName=pts-"$X"-sub
		intPortName=pts-"$X"-int

		imagePath=/var/lib/libvirt/images
		qcowName=svpts-7.30-${i}.qcow2

		echo "Creating xml domain definition for pts $i"
		domainXml=svpts-7.30-${i}.xml
		vmname=svpts-$i

		cat $TEMPLATE_LOCATION | sed -e "s/PTS_NAME/$vmname/g" \
									 -e "s/SUB_PORT_NAME/$subPortName/g" \
									 -e "s/INT_PORT_NAME/$intPortName/g" \
									 -e "s/CONTROL_PORT_NAME/$controlPortName/g" \
									 -e "s/SERVICE_PORT_NAME/$servicePortName/g" \
									 -e "s:IMAGE_PATH:$imagePath:g" \
									 -e "s/QCOW_NAME/$qcowName/g" > $domainXml

        # Customer A DPDK Ports
        #ovs-vsctl add-port subscriber-br pts-"$X"-sub
        #ovs-vsctl add-port internet-br pts-"$X"-int

        # Customer A VLAN tags
        #ovs-vsctl set port pts-"$X"-sub trunks=$X 
        #ovs-vsctl set port pts-"$X"-int trunks=$X

		echo "Attempting to define pts $i"
		virsh define $domainXml || (echo "Failed to define pts"; exit 1)

		echo "Attempting to start pts $i"
		virsh start $vmname || (echo "Failed to start pts"; exit 1)


        echo Done.

done




