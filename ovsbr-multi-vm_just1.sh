#! /bin/bash

ip link set dev p1p1 up
ip link set dev p1p2 up

# IXIA simulating LAN side
ovs-vsctl add-br subscriber-br
ovs-vsctl add-port subscriber-br p1p1

# IXIA simulating WAN side
ovs-vsctl add-br internet-br
ovs-vsctl add-port internet-br p1p2


# Bring it up (not sure if needed)
ip link set dev subscriber-br up
ip link set dev internet-br up


for (( X = 1650; X <= 1650; X++)); do

	echo Customer $X...

    ip tuntap add dev pts-"$X"-sub mode tap
    ip tuntap add dev pts-"$X"-int mode tap

	# Customer A DPDK Ports
	ovs-vsctl --may-exist add-port subscriber-br pts-"$X"-sub
	ovs-vsctl --may-exist add-port internet-br pts-"$X"-int
	
	# Customer A VLAN tags
	ovs-vsctl set port pts-"$X"-sub trunks=$X
	ovs-vsctl set port pts-"$X"-int trunks=$X

	echo Done.

done

