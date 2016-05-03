#! /bin/bash

# Copyright 2016, Sandvine Incorporated.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


export LC_ALL=C


RELEASE="16.02"


SVPTS=cs-svpts-$RELEASE-centos7-amd64
SVSDE=cs-svsde-$RELEASE-centos6-amd64
SVSPB=cs-svspb-$RELEASE-centos6-amd64


BOXES="$SVPTS $SVSDE $SVSPB"


PTS_CTRL_IP=192.168.192.30
PTS_SRVC_IP=192.168.192.150

SDE_CTRL_IP=192.168.192.20
SDE_SRVC_IP=192.168.192.140

SPB_CTRL_IP=192.168.192.10
SPB_SRVC_IP=192.168.192.130


for i in "$@"
do
case $i in

	--kvm-install-server)

		KVM_INSTALL_SERVER="yes"
		shift
		;;

	--kvm-install-desktop)

		KVM_INSTALL_SERVER="yes"
		KVM_INSTALL_DESKTOP="yes"
		shift
		;;

	--libvirt-define)

		LIBVIRT_DEFINE="yes"
		shift
		;;

	--libvirt-undefine)

		LIBVIRT_UNDEFINE="YES"
		shift
		;;

	--download-images)

		DOWNLOAD_IMAGES="yes"
		shift
		;;

	--libvirt-install-images)

		LIBVIRT_INSTALL_IMAGES="yes"
		shift
		;;

	--sudo-without-pass)

		SUDO_SETUP="yes"
		shift
		;;

	--openstack-install)

		OS_INSTALL="yes"
		shift
		;;

        --openstack-project=*)

                OS_PROJECT="${i#*=}"
		OS_IMAGE_UPLOAD="yes"
                shift
                ;;

	--is-hostname-ok)

		IS_HOSTNAME_OK="yes"
		shift
		;;

esac
done


if [ "$IS_HOSTNAME_OK" == "yes" ]
then

	HOST_NAME=$(hostname)
	FQDN=$(hostname -f)
	DOMAIN=$(hostname -d)


	echo
	echo "The detected local configuration are:"
	echo
	echo "Hostname:" $HOST_NAME
	echo "FQDN:" $FQDN
	echo "Domain:" $DOMAIN


	# If the hostname and hosts file aren't configured according, abort.
	if [ -z $HOST_NAME ]; then
	        echo "Hostname not found... Configure the file /etc/hostname with your hostname. ABORTING!"
	        exit 1
	fi

	if [ -z $DOMAIN ]; then
	        echo "Domain not found... Configure the file /etc/hosts with your \"IP + FQDN + HOSTNAME\". ABORTING!"
	        exit 1
	fi

	if [ -z $FQDN ]; then
	        echo "FQDN not found... Configure your /etc/hosts according. ABORTING!"
	        exit 1
	fi

	echo
	echo "The /etc/hostname and /etc/hosts files meet configuration requirements."

	exit 0

fi


if [ "$LIBVIRT_UNDEFINE" == "YES" ]
then
	clear

	echo
	echo "WARNING!!!"
	echo
	echo "You are about to UNDEFINE your Network and Virtual Machine definitons!"
	echo
	echo "However, your QCoW2s will be left intact."
	echo
	echo "About to shutdown your Virtual Machines."
	echo
	echo "You have 10 seconds to hit CONTROL +C to cancel this operation."

	sleep 10

	virsh net-destroy subscriber
	virsh net-destroy service
	virsh net-destroy internet
	virsh net-destroy control

	virsh net-undefine internet
	virsh net-undefine subscriber
	virsh net-undefine control
	virsh net-undefine service


	virsh shutdown $SVPTS
	virsh shutdown $SVSDE
	virsh shutdown $SVSPB

	virsh undefine $SVPTS
	virsh undefine $SVSDE
	virsh undefine $SVSPB

	exit 0
fi


if [ "$DOWNLOAD_IMAGES" == "yes" ]
then

        echo
        echo "Enter your Sandvine's FTP (ftp.support.sandvine.com) account details:"
        echo

        echo -n "Username: "
        read FTP_USER

        echo -n "Password: "
        read -s FTP_PASS

	echo
	wget -c --user=$FTP_USER --password=$FTP_PASS ftp://ftp.support.sandvine.com/release/CloudServices/$RELEASE/$SVPTS-disk1.qcow2c
	wget -c --user=$FTP_USER --password=$FTP_PASS ftp://ftp.support.sandvine.com/release/CloudServices/$RELEASE/$SVSPB-disk1.qcow2c
	wget -c --user=$FTP_USER --password=$FTP_PASS ftp://ftp.support.sandvine.com/release/CloudServices/$RELEASE/$SVSDE-disk1.qcow2c

	exit 0
fi


if [ "$LIBVIRT_INSTALL_IMAGES" == "yes" ]
then
	echo
	echo "Deploying QCoW2 images into /var/lib/libvirt/images subdirectory..."

	echo "$SVPTS"
	sudo qemu-img convert -p -f qcow2 -O qcow2 -o preallocation=metadata $SVPTS-disk1.qcow2c /var/lib/libvirt/images/$SVPTS-disk1.qcow2

	echo "$SVSDE"
	sudo qemu-img convert -p -f qcow2 -O qcow2 -o preallocation=metadata $SVSDE-disk1.qcow2c /var/lib/libvirt/images/$SVSDE-disk1.qcow2

	echo "$SVSPB"
	sudo qemu-img convert -p -f qcow2 -O qcow2 -o preallocation=metadata $SVSPB-disk1.qcow2c /var/lib/libvirt/images/$SVSPB-disk1.qcow2

	echo "Done."

	exit 0
fi


if [ "$OS_IMAGE_UPLOAD" == "yes" ]
then

	if [ ! -f ~/$OS_PROJECT-openrc.sh ]
	then
	        echo
	        echo "OpenStack Credentials for "$OS_PROJECT" account not found, aborting!"
	        exit 1
	else
	        echo
	        echo "Loading OpenStack credentials for "$OS_PROJECT" account..."
	        source ~/$OS_PROJECT-openrc.sh
	fi


	if [ "$OS_PROJECT" == "admin" ]
	then

		echo
		echo "Uploading Cloud Services $RELEASE QCoWs into Glance as public images..."

		echo "$SVSDE"
		glance image-create --file $SVSDE-disk1.qcow2c --is-public true --disk-format qcow2 --container-format bare --name "$SVSDE"

		echo "$SVSPB"
		glance image-create --file $SVSPB-disk1.qcow2c --is-public true --disk-format qcow2 --container-format bare --name "$SVSPB"

		echo "$SVPTS"
		glance image-create --file $SVPTS-disk1.qcow2c --is-public true --disk-format qcow2 --container-format bare --name "$SVPTS"

		echo
		echo "You can launch a Cloud Services Stack now! For example, by running:"
		echo
		echo "source ~/demo-openrc.sh # Assuming that you have an OpenStack Project called \"demo\"..."
		echo "heat stack-create cs-stack-1 -f ~/cs/cloudservices-stack-$RELEASE-1.yaml"

	else

		echo
		echo "Uploading Cloud Services $RELEASE QCoWs into Glance of \"$OS_PROJECT\" account."

		echo "$SVSDE"
		glance image-create --file $SVSDE-disk1.qcow2c --disk-format qcow2 --container-format bare --name "$SVSDE"

		echo "$SVSPB"
		glance image-create --file $SVSPB-disk1.qcow2c --disk-format qcow2 --container-format bare --name "$SVSPB"

		echo "$SVPTS"
		glance image-create --file $SVPTS-disk1.qcow2c --disk-format qcow2 --container-format bare --name "$SVPTS"

		echo
		echo "You can launch a Cloud Services Stack now! For example, by running:"
		echo
		echo "source ~/"$OS_PROJECT"-openrc.sh"
		echo "heat stack-create cs-stack-1 -f ~/cs/cloudservices-stack-$RELEASE-1.yaml"

	fi

	exit 0
fi


if [ "$SUDO_SETUP" == "yes" ]
then
	echo
	echo "Configuring sudores, so, members of group \"sudo\" will not require to type passwords."
	echo "You'll need to type your password now (you need to be member of group sudo already):"

	sudo sed -i -e 's/%sudo.*/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

	exit 0
fi


if [ "$OS_INSTALL" == "yes" ]
then
	sudo apt update
	sudo apt -y install linux-generic-lts-wily software-properties-common ssh vim curl
	sudo update-alternatives --set editor /usr/bin/vim.basic
	sudo apt -y full-upgrade
	sudo update-grub

	echo
        echo "Installing OpenStack Liberty (all-in-one) on Ubuntu Trusty with Ansible:"

	bash <(curl -s https://raw.githubusercontent.com/sandvine/os-ansible-deployment-lite/liberty/misc/os-install-lbr.sh)

	exit 0
fi


if [ "$KVM_INSTALL_SERVER" == "yes" ]
then
	sudo apt update
	sudo apt -y install linux-generic-lts-wily software-properties-common ssh vim curl
	sudo update-alternatives --set editor /usr/bin/vim.basic
	sudo add-apt-repository -y cloud-archive:liberty
	sudo apt update
	sudo apt -y full-upgrade
	sudo update-grub

	# Instaling KVM Hypervisor and required tools to work with it
	if [ "$KVM_INSTALL_DESKTOP" == "yes" ]; then
		sudo apt -y install ubuntu-virt
	else
		sudo apt -y install ubuntu-virt-server
	fi

	exit 0
fi


if [ "$LIBVIRT_DEFINE" == "yes" ]
then

	echo
	echo "Defining Virtual Machines..."
	virsh define $SVPTS.xml
	virsh autostart $SVPTS

	virsh define $SVSDE.xml
	virsh autostart $SVSDE

	virsh define $SVSPB.xml
	virsh autostart $SVSPB


	echo
	echo "Finding Virtual Machine's MAC addresses..."
	SVPTS_MACS=$(virsh dumpxml $SVPTS | grep mac\ address | head -n 2 | awk -F\' '{print $2}' | xargs)
	SVSDE_MACS=$(virsh dumpxml $SVSDE | grep mac\ address | awk -F\' '{print $2}' | xargs)
	SVSPB_MACS=$(virsh dumpxml $SVSPB | grep mac\ address | awk -F\' '{print $2}' | xargs)


	VNIC=0

	for X in $SVPTS_MACS; do
		case $VNIC in
		        0)
				if grep "$X" libvirt-control-network.xml 2>&1 > /dev/null ; then
					echo "SVPTS CTRL Already configured, aborting..." 
				else
					sed -i -e '/ip=.*'"$PTS_CTRL_IP"'/d' libvirt-control-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVPTS\'' ip='\'$PTS_CTRL_IP\''/>' libvirt-control-network.xml
				fi
		                ;;
		        1)
			        if grep "$X" libvirt-service-network.xml 2>&1 > /dev/null ; then
			                echo "SVPTS SRVC Already configured, aborting..."
			        else
					sed -i -e '/ip=.*'"$PTS_SRVC_IP"'/d' libvirt-service-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVPTS\'' ip='\'$PTS_SRVC_IP\''/>' libvirt-service-network.xml
				fi
		                ;;
		esac
		let VNIC\+=1
	done


	VNIC=0

	for X in $SVSDE_MACS; do
		case $VNIC in
		        0)
				if grep "$X" libvirt-control-network.xml 2>&1 > /dev/null ; then
					echo "SVSDE CTRL Already configured, aborting..." 
				else
					sed -i -e '/ip=.*'"$SDE_CTRL_IP"'/d' libvirt-control-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVSDE\'' ip='\'$SDE_CTRL_IP\''/>' libvirt-control-network.xml
				fi
		                ;;
		        1)
			        if grep "$X" libvirt-service-network.xml 2>&1 > /dev/null ; then
			                echo "SVSDE SRVC Already configured, aborting..."
			        else
					sed -i -e '/ip=.*'"$SDE_SRVC_IP"'/d' libvirt-service-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVSDE\'' ip='\'$SDE_SRVC_IP\''/>' libvirt-service-network.xml
				fi
		                ;;
		esac
		let VNIC\+=1
	done


	VNIC=0

	for X in $SVSPB_MACS; do
		case $VNIC in
		        0)
	       			if grep "$X" libvirt-control-network.xml 2>&1 > /dev/null ; then
					echo "SVSPB CTRL Already configured, aborting..."
				else
					sed -i -e '/ip=.*'"$SPB_CTRL_IP"'/d' libvirt-control-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVSPB\'' ip='\'$SPB_CTRL_IP\''/>' libvirt-control-network.xml
	       			fi
		                ;;
		        1)
			        if grep "$X" libvirt-service-network.xml 2>&1 > /dev/null ; then
			                echo "SVSPB SRVC Already configured, aborting..."
				else
					sed -i -e '/ip=.*'"$SPB_SRVC_IP"'/d' libvirt-service-network.xml
					sed -i -e '/range\ start/a\ \ \ \ \ \ <host mac='\'$X\'' name='\'$SVSPB\'' ip='\'$SPB_SRVC_IP\''/>' libvirt-service-network.xml
			        fi
		                ;;
		esac
		let VNIC\+=1
	done

	echo
	echo "Defining Networks..."
	virsh net-define libvirt-control-network.xml
	virsh net-autostart control
	virsh net-start control

	virsh net-define libvirt-service-network.xml
	virsh net-autostart service
	virsh net-start service

	virsh net-define libvirt-subscriber-network.xml
	virsh net-autostart subscriber
	virsh net-start subscriber

	virsh net-define libvirt-internet-network-nat.xml
	virsh net-autostart internet
	virsh net-start internet

	exit 0
fi


# Hello!
echo
echo "Extracting Libvirt XML files and OpenStack Heat Templates here: `pwd`"
echo

# Searches for the line number where finish the script and start the tar.gz.
SKIP=`awk '/^__TARFILE_FOLLOWS__/ { print NR + 1; exit 0; }' $0`

# Remember our file name.
THIS=`pwd`/$0

# Take the tarfile and pipe it into tar.
tail -n +$SKIP $THIS | tar -xv

# Any script here will happen after the tar file extract.
echo
echo "Finished"
exit 0

# NOTE: Don't place any newline characters after the last line below.
__TARFILE_FOLLOWS__
cloudservices-stack-16.02-1.yaml                                                                    0000664 0001750 0001750 00000037217 12670461151 016166  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 heat_template_version: 2013-05-23

description: >

  HOT template to create Sandvine Stack, it have an Instance acting as a L2 Bridge between two VXLAN networks.

  We have 3 Instances:

  * PTS - CentOS 7.2
  * SDE - CentOS 6.7
  * SPB - CentOS 6.7


  We want to wire them as:

  -------|ctrl_subnet|------------- Control Network (with Internet access via router_i0)
      |        |        |
     ---      ---      ---
     | |      | |      | |      --|Android|     --|Windows|
     | |      | |      | |      |               |
     | |      | |      | |    --------------------------
     | |      | |      | |----|data_real_subnet1 + dhcp|---|CentOS|
     |S|      |S|      |P|    --------------------------
     |B|      |D|      |T|     |            |      |
     |P|      |E|      |S|     |            |      --|Mac|
     | |      | |      | |     --|Ubuntu|   |
     | |      | |      | |                  --|Debian|
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |------------|data_int_subnet1|----|Internet via router_i1|
     | |      | |      | |
     ---      ---      - -
      |        |        |
      --|service_subnet|------  <-- Service Network (not routed - no gateway)

parameters:
  ssh_key:
    type: string
    label: "Your SSH keypair name (pre-create please!)"
    description: |
        If you have not created your key, please go to
        Project/Compute/Access & Security, and either import
        one or create one. If you create it, make sure you keep
        the downloaded file (as you don't get a second chance)
    default: default

  public_network:
    type: string
    label: Public External Network
    description: Public Network with Floating IP addresses
    default: "ext-net"

  pts_image:
    type: string
    label: "PTS L2 Bridge Image (default 'cs-svpts-16.02-centos7-amd64')"
    description: "PTS Image"
    default: "cs-svpts-16.02-centos7-amd64"

  sde_image:
    type: string
    label: "SDE Image (default 'cs-svsde-16.02-centos6-amd64')"
    description: "SDE Image"
    default: "cs-svsde-16.02-centos6-amd64"

  spb_image:
    type: string
    label: "SPB Image (default 'cs-svspb-16.02-centos6-amd64')"
    description: "SPB Image"
    default: "cs-svspb-16.02-centos6-amd64"

resources:
  rtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-rtr' } }
      external_gateway_info:
        network: { get_param: public_network }

  router_i0:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: ctrl_subnet }

  router_i1:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: data_int_subnet1 }

  floating_ip_1:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_2:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_3:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  subscriber_default_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscriber-default-sec' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443
        - protocol: tcp
          port_range_min: 3389
          port_range_max: 3389

  sde_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443

  sde_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  spb_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  spb_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  pts_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  pts_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  ctrl_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }

  ctrl_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: ctrl_net }
      enable_dhcp: True
      cidr: 192.168.192/25
      allocation_pools:
        - start: 192.168.192.50
          end: 192.168.192.126

  service_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }

  service_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: service_net }
      enable_dhcp: True
      cidr: 192.168.192.128/25
      gateway_ip: ""

  data_sub_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ns1' } }

  data_real_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ss1' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: data_sub_net1 }
      enable_dhcp: True
      cidr: 10.192/16
      gateway_ip: 10.192.0.1
      allocation_pools:
        - start: 10.192.0.50
          end: 10.192.255.254

  data_int_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ni1' } }

  data_int_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-si1' } }
      network: { get_resource: data_int_net1 }
      enable_dhcp: False
      cidr: 10.192/16
      allocation_pools:
        - start: 10.192.0.2
          end: 10.192.0.49

  spb_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.10
      security_groups:
        - { get_resource: spb_ctrl_sec }

  spb_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_3 }
      port_id: { get_resource: spb_ctrl_port }

  sde_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.20
      security_groups:
        - { get_resource: sde_ctrl_sec }

  sde_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_2 }
      port_id: { get_resource: sde_ctrl_port }

  pts_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.30
      security_groups:
        - { get_resource: pts_ctrl_sec }

  pts_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_1 }
      port_id: { get_resource: pts_ctrl_port }

  spb_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.130

  sde_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
       - ip_address: 192.168.192.140
 
  pts_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.150

  pts_port_int_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-i1-port"]]}
      network: { get_resource: data_int_net1 }
      port_security_enabled: False

  pts_port_sub_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-s1-port"]]}
      network: { get_resource: data_sub_net1 }
      port_security_enabled: False

  pts:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'pts_image' }
      flavor: "m1.small"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: pts_ctrl_port }
        - port: { get_resource: pts_srvc_port }
        - port: { get_resource: pts_port_sub_net1 }
        - port: { get_resource: pts_port_int_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  spb:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'spb_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: spb_ctrl_port }
        - port: { get_resource: spb_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  sde:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'sde_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: sde_ctrl_port }
        - port: { get_resource: sde_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

outputs:
  pts_floating_ip:
    description: The IP address of the deployed PTS instance
    value: { get_attr: [floating_ip_1, floating_ip_address] }

  sde_floating_ip:
    description: The IP address of the deployed SDE instance
    value: { get_attr: [floating_ip_2, floating_ip_address] }

  spb_floating_ip:
    description: The IP address of the deployed SPB instance
    value: { get_attr: [floating_ip_3, floating_ip_address] }
                                                                                                                                                                                                                                                                                                                                                                                 cloudservices-stack-16.02-flat-1.yaml                                                               0000664 0001750 0001750 00000037505 12670461151 017112  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 heat_template_version: 2013-05-23

description: >

  HOT template to create Sandvine Stack, it have an Instance acting as a L2 Bridge between two VXLAN networks.

  We have 3 Instances:

  * PTS - CentOS 7.2
  * SDE - CentOS 6.7
  * SPB - CentOS 6.7


  We want to wire them as:

  -------|ctrl_subnet|------------- Control Network (with Internet access via router_i0)
      |        |        |
     ---      ---      ---
     | |      | |      | |      --|Android|     --|Windows|
     | |      | |      | |      |               |
     | |      | |      | |    --------------------------
     | |      | |      | |----|data_real_subnet1 + dhcp|---|CentOS|
     |S|      |S|      |P|    --------------------------
     |B|      |D|      |T|     |            |      |
     |P|      |E|      |S|     |            |      --|Mac|
     | |      | |      | |     --|Ubuntu|   |
     | |      | |      | |                  --|Debian|
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |------------|data_int_subnet1|----|Internet via router_i1|
     | |      | |      | |
     ---      ---      - -
      |        |        |
      --|service_subnet|------  <-- Service Network (not routed - no gateway)

parameters:
  ssh_key:
    type: string
    label: "Your SSH keypair name (pre-create please!)"
    description: |
        If you have not created your key, please go to
        Project/Compute/Access & Security, and either import
        one or create one. If you create it, make sure you keep
        the downloaded file (as you don't get a second chance)
    default: default

  public_network:
    type: string
    label: Public External Network
    description: Public Network with Floating IP addresses
    default: "ext-net"

  pts_image:
    type: string
    label: "PTS L2 Bridge Image (default 'cs-svpts-16.02-centos7-amd64')"
    description: "PTS Image"
    default: "cs-svpts-16.02-centos7-amd64"

  sde_image:
    type: string
    label: "SDE Image (default 'cs-svsde-16.02-centos6-amd64')"
    description: "SDE Image"
    default: "cs-svsde-16.02-centos6-amd64"

  spb_image:
    type: string
    label: "SPB Image (default 'cs-svspb-16.02-centos6-amd64')"
    description: "SPB Image"
    default: "cs-svspb-16.02-centos6-amd64"

resources:
  rtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-rtr' } }
      external_gateway_info:
        network: { get_param: public_network }

  router_i0:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: ctrl_subnet }

  router_i1:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: data_int_subnet1 }

  floating_ip_1:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_2:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_3:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  subscriber_default_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscriber-default-sec' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443
        - protocol: tcp
          port_range_min: 3389
          port_range_max: 3389

  sde_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443

  sde_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  spb_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  spb_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  pts_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  pts_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  ctrl_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }

  ctrl_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: ctrl_net }
      enable_dhcp: True
      cidr: 192.168.192/25
      allocation_pools:
        - start: 192.168.192.50
          end: 192.168.192.126

  service_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }

  service_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: service_net }
      enable_dhcp: True
      cidr: 192.168.192.128/25
      gateway_ip: ""

  data_sub_net1:
    type: OS::Neutron::ProviderNet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ns1-lan' } }
      network_type: flat
      physical_network: physvlan1
      shared: false

  data_real_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ss1' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: data_sub_net1 }
      enable_dhcp: True
      cidr: 10.192/16
      gateway_ip: 10.192.0.1
      allocation_pools:
        - start: 10.192.0.50
          end: 10.192.255.254

  data_int_net1:
    type: OS::Neutron::ProviderNet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ni1-lan' } }
      network_type: flat
      physical_network: physvlan2
      shared: false

  data_int_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-si1' } }
      network: { get_resource: data_int_net1 }
      enable_dhcp: False
      cidr: 10.192/16
      allocation_pools:
        - start: 10.192.0.2
          end: 10.192.0.49

  spb_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.10
      security_groups:
        - { get_resource: spb_ctrl_sec }

  spb_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_3 }
      port_id: { get_resource: spb_ctrl_port }

  sde_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.20
      security_groups:
        - { get_resource: sde_ctrl_sec }

  sde_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_2 }
      port_id: { get_resource: sde_ctrl_port }

  pts_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.30
      security_groups:
        - { get_resource: pts_ctrl_sec }

  pts_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_1 }
      port_id: { get_resource: pts_ctrl_port }

  spb_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.130

  sde_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
       - ip_address: 192.168.192.140
 
  pts_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.150

  pts_port_int_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-i1-port"]]}
      network: { get_resource: data_int_net1 }
      port_security_enabled: False

  pts_port_sub_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-s1-port"]]}
      network: { get_resource: data_sub_net1 }
      port_security_enabled: False

  pts:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'pts_image' }
      flavor: "m1.small"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: pts_ctrl_port }
        - port: { get_resource: pts_srvc_port }
        - port: { get_resource: pts_port_sub_net1 }
        - port: { get_resource: pts_port_int_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  spb:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'spb_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: spb_ctrl_port }
        - port: { get_resource: spb_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  sde:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'sde_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: sde_ctrl_port }
        - port: { get_resource: sde_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

outputs:
  pts_floating_ip:
    description: The IP address of the deployed PTS instance
    value: { get_attr: [floating_ip_1, floating_ip_address] }

  sde_floating_ip:
    description: The IP address of the deployed SDE instance
    value: { get_attr: [floating_ip_2, floating_ip_address] }

  spb_floating_ip:
    description: The IP address of the deployed SPB instance
    value: { get_attr: [floating_ip_3, floating_ip_address] }
                                                                                                                                                                                           cloudservices-stack-16.02-rad-1.yaml                                                                0000664 0001750 0001750 00000037577 12670461151 016743  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 heat_template_version: 2013-05-23

description: >

  HOT template to create Sandvine Stack, it have an Instance acting as a L2 Bridge between two VXLAN networks.

  We have 3 Instances:

  * PTS - CentOS 7.2
  * SDE - CentOS 6.7
  * SPB - CentOS 6.7


  We want to wire them as:

  -------|ctrl_subnet|------------- Control Network (with Internet access via router_i0)
      |        |        |
     ---      ---      ---
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |
     |S|      |S|      |P|
     |B|      |D|      |T|
     |P|      |E|      |S|
     | |      | |      | |
     | |      | |------| |
     | |      | |      | |
     | |      | |      | |
     | |      | |------| |
     | |      | |      | |
     ---      ---      - -
      |        |        |
      --|service_subnet|------  <-- Service Network (not routed - no gateway)

parameters:
  ssh_key:
    type: string
    label: "Your SSH keypair name (pre-create please!)"
    description: |
        If you have not created your key, please go to
        Project/Compute/Access & Security, and either import
        one or create one. If you create it, make sure you keep
        the downloaded file (as you don't get a second chance)
    default: default

  public_network:
    type: string
    label: Public External Network
    description: Public Network with Floating IP addresses
    default: "ext-net"

  pts_image:
    type: string
    label: "PTS L2 Bridge Image (default 'cs-svpts-16.02-centos7-amd64')"
    description: "PTS Image"
    default: "cs-svpts-16.02-centos7-amd64"

  sde_image:
    type: string
    label: "SDE Image (default 'cs-svsde-16.02-centos6-amd64')"
    description: "SDE Image"
    default: "cs-svsde-16.02-centos6-amd64"

  spb_image:
    type: string
    label: "SPB Image (default 'cs-svspb-16.02-centos6-amd64')"
    description: "SPB Image"
    default: "cs-svspb-16.02-centos6-amd64"

resources:
  rtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-rtr' } }
      external_gateway_info:
        network: { get_param: public_network }

  router_i0:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: ctrl_subnet }

  router_i1:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: data_int_subnet1 }

  floating_ip_1:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_2:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_3:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  sde_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443
        - protocol: tcp
          port_range_min: 777
          port_range_max: 777
        - protocol: tcp
          port_range_min: 4739
          port_range_max: 4739
        - protocol: udp
          port_range_min: 52000
          port_range_max: 52256
          
  sde_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  spb_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  spb_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  pts_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  pts_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  ctrl_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }

  ctrl_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: ctrl_net }
      enable_dhcp: True
      cidr: 192.168.192/25
      allocation_pools:
        - start: 192.168.192.50
          end: 192.168.192.126

  service_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }

  service_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: service_net }
      enable_dhcp: True
      cidr: 192.168.192.128/25
      gateway_ip: ""

  data_sub_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ns1' } }

  data_real_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ss1' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: data_sub_net1 }
      enable_dhcp: True
      cidr: 10.192/16
      gateway_ip: 10.192.0.1
      allocation_pools:
        - start: 10.192.0.50
          end: 10.192.255.254

  data_int_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ni1' } }

  data_int_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-si1' } }
      network: { get_resource: data_int_net1 }
      enable_dhcp: False
      cidr: 10.192/16
      allocation_pools:
        - start: 10.192.0.2
          end: 10.192.0.49

  spb_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.10
      security_groups:
        - { get_resource: spb_ctrl_sec }

  spb_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_3 }
      port_id: { get_resource: spb_ctrl_port }

  sde_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.20
      security_groups:
        - { get_resource: sde_ctrl_sec }

  sde_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_2 }
      port_id: { get_resource: sde_ctrl_port }

  pts_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.30
      security_groups:
        - { get_resource: pts_ctrl_sec }

  pts_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_1 }
      port_id: { get_resource: pts_ctrl_port }

  spb_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.130

  sde_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
       - ip_address: 192.168.192.140
 
  pts_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.150

  pts_port_int_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-i1-port"]]}
      network: { get_resource: data_int_net1 }
      port_security_enabled: False

  pts_port_sub_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-s1-port"]]}
      network: { get_resource: data_sub_net1 }
      port_security_enabled: False

  sde_port_int_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-i1-port"]]}
      network: { get_resource: data_int_net1 }
      port_security_enabled: False

  sde_port_sub_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-s1-port"]]}
      network: { get_resource: data_sub_net1 }
      port_security_enabled: False

  pts:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'pts_image' }
      flavor: "m1.small"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: pts_ctrl_port }
        - port: { get_resource: pts_srvc_port }
        - port: { get_resource: pts_port_sub_net1 }
        - port: { get_resource: pts_port_int_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"
        runcmd:
        - 'su -c "\curl -s https://raw.githubusercontent.com/tmartinx/svauto/dev/scripts/install-svauto.sh | bash -s" sandvine'

  spb:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'spb_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: spb_ctrl_port }
        - port: { get_resource: spb_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"
            
  sde:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'sde_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: sde_ctrl_port }
        - port: { get_resource: sde_srvc_port }
        - port: { get_resource: sde_port_sub_net1 }
        - port: { get_resource: sde_port_int_net1 }                
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"
        runcmd:
        - 'su -c "\curl -s https://raw.githubusercontent.com/tmartinx/svauto/dev/scripts/install-svauto.sh | bash -s" sandvine'

outputs:
  pts_floating_ip:
    description: The IP address of the deployed PTS instance
    value: { get_attr: [floating_ip_1, floating_ip_address] }

  sde_floating_ip:
    description: The IP address of the deployed SDE instance
    value: { get_attr: [floating_ip_2, floating_ip_address] }

  spb_floating_ip:
    description: The IP address of the deployed SPB instance
    value: { get_attr: [floating_ip_3, floating_ip_address] }
                                                                                                                                 cloudservices-stack-16.02-vlan-1.yaml                                                               0000664 0001750 0001750 00000037665 12670461151 017133  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 heat_template_version: 2013-05-23

description: >

  HOT template to create Sandvine Stack, it have an Instance acting as a L2 Bridge between two VXLAN networks.

  We have 3 Instances:

  * PTS - CentOS 7.2
  * SDE - CentOS 6.7
  * SPB - CentOS 6.7


  We want to wire them as:

  -------|ctrl_subnet|------------- Control Network (with Internet access via router_i0)
      |        |        |
     ---      ---      ---
     | |      | |      | |      --|Android|     --|Windows|
     | |      | |      | |      |               |
     | |      | |      | |    --------------------------
     | |      | |      | |----|data_real_subnet1 + dhcp|---|CentOS|
     |S|      |S|      |P|    --------------------------
     |B|      |D|      |T|     |            |      |
     |P|      |E|      |S|     |            |      --|Mac|
     | |      | |      | |     --|Ubuntu|   |
     | |      | |      | |                  --|Debian|
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |------------|data_int_subnet1|----|Internet via router_i1|
     | |      | |      | |
     ---      ---      - -
      |        |        |
      --|service_subnet|------  <-- Service Network (not routed - no gateway)

parameters:
  ssh_key:
    type: string
    label: "Your SSH keypair name (pre-create please!)"
    description: |
        If you have not created your key, please go to
        Project/Compute/Access & Security, and either import
        one or create one. If you create it, make sure you keep
        the downloaded file (as you don't get a second chance)
    default: default

  public_network:
    type: string
    label: Public External Network
    description: Public Network with Floating IP addresses
    default: "ext-net"

  pts_image:
    type: string
    label: "PTS L2 Bridge Image (default 'cs-svpts-16.02-centos7-amd64')"
    description: "PTS Image"
    default: "cs-svpts-16.02-centos7-amd64"

  sde_image:
    type: string
    label: "SDE Image (default 'cs-svsde-16.02-centos6-amd64')"
    description: "SDE Image"
    default: "cs-svsde-16.02-centos6-amd64"

  spb_image:
    type: string
    label: "SPB Image (default 'cs-svspb-16.02-centos6-amd64')"
    description: "SPB Image"
    default: "cs-svspb-16.02-centos6-amd64"

resources:
  rtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-rtr' } }
      external_gateway_info:
        network: { get_param: public_network }

  router_i0:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: ctrl_subnet }

  router_i1:
    type: OS::Neutron::RouterInterface
    properties:
      router: { get_resource: rtr }
      subnet: { get_resource: data_int_subnet1 }

  floating_ip_1:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_2:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  floating_ip_3:
    type: OS::Neutron::FloatingIP
    depends_on: router_i0
    properties:
      floating_network: { get_param: public_network }

  subscriber_default_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscriber-default-sec' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443
        - protocol: tcp
          port_range_min: 3389
          port_range_max: 3389

  sde_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22
        - protocol: tcp
          port_range_min: 80
          port_range_max: 80
        - protocol: tcp
          port_range_min: 443
          port_range_max: 443

  sde_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  spb_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  spb_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  pts_ctrl_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-ctrl-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 22
          port_range_max: 22

  pts_srvc_sec:
    type: OS::Neutron::SecurityGroup
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts-srvc-rules' } }
      rules:
        - protocol: icmp
        - protocol: tcp
          port_range_min: 1
          port_range_max: 65535
        - protocol: udp
          port_range_min: 1
          port_range_max: 65535

  ctrl_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }

  ctrl_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: ctrl_net }
      enable_dhcp: True
      cidr: 192.168.192/25
      allocation_pools:
        - start: 192.168.192.50
          end: 192.168.192.126

  service_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }

  service_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: service_net }
      enable_dhcp: True
      cidr: 192.168.192.128/25
      gateway_ip: ""

  data_sub_net1:
    type: OS::Neutron::ProviderNet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ns1-vlan-{{vlan_sub_id}}' } }
      network_type: vlan
      physical_network: physvlan1
      segmentation_id: {{vlan_sub_id}}
      shared: false

  data_real_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ss1' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: data_sub_net1 }
      enable_dhcp: True
      cidr: 10.192/16
      gateway_ip: 10.192.0.1
      allocation_pools:
        - start: 10.192.0.50
          end: 10.192.255.254

  data_int_net1:
    type: OS::Neutron::ProviderNet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-ni1-vlan-{{vlan_int_id}}' } }
      network_type: vlan
      physical_network: physvlan2
      segmentation_id: {{vlan_int_id}}
      shared: false

  data_int_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-subscribers-si1' } }
      network: { get_resource: data_int_net1 }
      enable_dhcp: False
      cidr: 10.192/16
      allocation_pools:
        - start: 10.192.0.2
          end: 10.192.0.49

  spb_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.10
      security_groups:
        - { get_resource: spb_ctrl_sec }

  spb_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_3 }
      port_id: { get_resource: spb_ctrl_port }

  sde_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.20
      security_groups:
        - { get_resource: sde_ctrl_sec }

  sde_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_2 }
      port_id: { get_resource: sde_ctrl_port }

  pts_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.30
      security_groups:
        - { get_resource: pts_ctrl_sec }

  pts_floating_ip_assoc:
    type: OS::Neutron::FloatingIPAssociation
    properties:
      floatingip_id: { get_resource: floating_ip_1 }
      port_id: { get_resource: pts_ctrl_port }

  spb_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.130

  sde_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
       - ip_address: 192.168.192.140
 
  pts_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.150

  pts_port_int_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-i1-port"]]}
      network: { get_resource: data_int_net1 }
      port_security_enabled: False

  pts_port_sub_net1:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-s1-port"]]}
      network: { get_resource: data_sub_net1 }
      port_security_enabled: False

  pts:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'pts_image' }
      flavor: "m1.small"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: pts_ctrl_port }
        - port: { get_resource: pts_srvc_port }
        - port: { get_resource: pts_port_sub_net1 }
        - port: { get_resource: pts_port_int_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  spb:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'spb_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: spb_ctrl_port }
        - port: { get_resource: spb_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  sde:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'sde_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_real_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: sde_ctrl_port }
        - port: { get_resource: sde_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

outputs:
  pts_floating_ip:
    description: The IP address of the deployed PTS instance
    value: { get_attr: [floating_ip_1, floating_ip_address] }

  sde_floating_ip:
    description: The IP address of the deployed SDE instance
    value: { get_attr: [floating_ip_2, floating_ip_address] }

  spb_floating_ip:
    description: The IP address of the deployed SPB instance
    value: { get_attr: [floating_ip_3, floating_ip_address] }
                                                                           cloudservices-stack-nubo-16.02-stock-gui-1.yaml                                                     0000664 0001750 0001750 00000026147 12670461151 021032  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 heat_template_version: 2013-05-23

description: >

  HOT template to create Sandvine Stack, it have an Instance acting as a L2 Bridge between two VXLAN networks.

  We have 4 Instances:

  * PTS - CentOS 7.2
  * SDE - CentOS 6.7
  * SPB - CentOS 6.7
  * GUI - Windows or Android

  We want to wire them as:

  -------|ctrl_subnet|------------- Control Network (with Internet access via router_i0)
      |        |        |
     ---      ---      ---
     | |      | |      | |      --|Android|     --|Windows|
     | |      | |      | |      |               |
     | |      | |      | |    -------------------------
     | |      | |      | |----|     data_sub_net1     |---|CentOS|
     |S|      |S|      |P|    -------------------------
     |B|      |D|      |T|     |            |      |
     |P|      |E|      |S|     |            |      --|Mac|
     | |      | |      | |     --|Ubuntu|   |
     | |      | |      | |                  --|Debian|
     | |      | |      | |
     | |      | |      | |
     | |      | |      | |-------|data_int_subnet1 + dhcp|----|Internet via router_i1|
     | |      | |      | |
     ---      ---      - -
      |        |        |
      --|service_subnet|------  <-- Service Network (not routed - no gateway)

parameters:
  ssh_key:
    type: string
    label: "Your SSH keypair name (pre-create please!)"
    description: |
        If you have not created your key, please go to
        Project/Compute/Access & Security, and either import
        one or create one. If you create it, make sure you keep
        the downloaded file (as you don't get a second chance)
    default: default

  public_network:
    type: string
    label: Public External Network
    description: Public Network with Floating IP addresses
    default: "ext-net"

  sde_image:
    type: string
    label: "SDE Image (default 'cs-svsde-16.02-centos6-amd64')"
    description: "SDE Image"
    default: "cs-svsde-16.02-centos6-amd64"

  pts_image:
    type: string
    label: "PTS L2 Bridge Image (default 'cs-svpts-16.02-centos7-amd64')"
    description: "PTS Image"
    default: "cs-svpts-16.02-centos7-amd64"

  spb_image:
    type: string
    label: "SPB Image (default 'cs-svspb-16.02-centos6-amd64')"
    description: "SPB Image"
    default: "cs-svspb-16.02-centos6-amd64"

  gui_image:
    type: string
    label: "GUI image (win7 or android)"
    description: "GUI (win7 or android)"
    default: "win7"

resources:
  crtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-crtr' } }
      external_gateway_info: 
        network: { get_param: public_network }

  ctrl_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }

  ctrl_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-control' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      enable_dhcp: True
      network_id: { get_resource: ctrl_net }
      cidr: 192.168.192/25
      allocation_pools:
        - start: 192.168.192.50
          end: 192.168.192.126

  service_net:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }

  service_subnet:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-service' } }
      dns_nameservers: [8.8.4.4, 8.8.8.8]
      network: { get_resource: service_net }
      enable_dhcp: True
      cidr: 192.168.192.128/25
      gateway_ip: ""

  router_i0:
    type: OS::Neutron::RouterInterface
    properties:
      router_id: { get_resource: crtr }
      subnet_id: { get_resource: ctrl_subnet }

  drtr:
    type: OS::Neutron::Router
    properties:
      admin_state_up: True
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-drtr' } }
      external_gateway_info:
        network: { get_param: public_network }

  router_i1:
    type: OS::Neutron::RouterInterface
    properties:
      router_id: { get_resource: drtr }
      subnet_id: { get_resource: data_int_subnet1 }

  data_sub_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sub-net1' } }

  data_int_net1:
    type: OS::Neutron::Net
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-int-net1' } }

  data_int_subnet1:
    type: OS::Neutron::Subnet
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-data-int-subnet1' } }
      enable_dhcp: true
      network_id: { get_resource: data_int_net1 }
      cidr: 10.192/16

  spb_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network_id: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.10

  pts_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network_id: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.30

  sde_ctrl_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network_id: { get_resource: ctrl_net }
      fixed_ips:
        - ip_address: 192.168.192.20

  spb_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "spb-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.130

  sde_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "sde-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
       - ip_address: 192.168.192.140
 
  pts_srvc_port:
    type: OS::Neutron::Port
    properties:
      name: {"Fn::Join": ["-", [{ get_param: "OS::stack_name" } , "pts-port"]]}
      network: { get_resource: service_net }
      fixed_ips:
        - ip_address: 192.168.192.150

  pts:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-pts' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'pts_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_int_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: pts_ctrl_port }
        - port: { get_resource: pts_srvc_port }
        - network: { get_resource: data_sub_net1 }
        - network: { get_resource: data_int_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  spb:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-spb' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'spb_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_int_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: spb_ctrl_port }
        - port: { get_resource: spb_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  sde:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-sde' } }
      key_name: { get_param: 'ssh_key' }
      image: { get_param: 'sde_image' }
      flavor: "m1.medium"
      metadata:
        {
          common:
          {
            int_subnet:  { get_attr: [data_int_subnet1, cidr] }
          },
          sde:
          {
            1:
            {
              ip_c:     { get_attr: [ sde_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ sde_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          pts:
          {
            1:
            {
              ip_c:     { get_attr: [ pts_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ pts_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
          spb:
          {
            1:
            {
              ip_c:     { get_attr: [ spb_ctrl_port, fixed_ips, 0, ip_address ] },
              ip_s:     { get_attr: [ spb_srvc_port, fixed_ips, 0, ip_address ] }
            }
          },
        }
      networks:
        - port: { get_resource: sde_ctrl_port }
        - port: { get_resource: sde_srvc_port }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

  gui:
    type: OS::Nova::Server
    properties:
      name: { str_replace: { params: { $stack_name: { get_param: 'OS::stack_name' } }, template: '$stack_name-gui' } }
      image: { get_param: 'gui_image' }
      flavor: "m1.medium"
      networks:
        - network: { get_resource: data_sub_net1 }
      user_data_format: RAW
      user_data: |
        #cloud-config
        system_info:
          default_user:
            name: "sandvine"

outputs:
                                                                                                                                                                                                                                                                                                                                                                                                                         cs-svsde-16.02-centos6-amd64.hook                                                                   0000664 0001750 0001750 00000002215 12670461151 016056  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 #!/bin/bash
# used some from advanced script to have multiple ports: use an equal number of guest and host ports

# Update the following variables to fit your setup
Guest_name=cs-svsde-16.02-centos6-amd64
Guest_ipaddr=192.168.192.20
Host_ipaddr={{host_ipaddr}}
Host_port=(  '8080' '8443' )
Guest_port=( '80' '443' )

length=$(( ${#Host_port[@]} - 1 ))
if [ "${1}" = "${Guest_name}" ]; then
   if [ "${2}" = "stopped" ] || [ "${2}" = "reconnect" ]; then
       for i in `seq 0 $length`; do
               iptables -t nat -D PREROUTING -d ${Host_ipaddr} -p tcp --dport ${Host_port[$i]} -j DNAT --to ${Guest_ipaddr}:${Guest_port[$i]}
               iptables -D FORWARD -d ${Guest_ipaddr}/32 -p tcp -m state --state NEW -m tcp --dport ${Guest_port[$i]} -j ACCEPT
       done
   fi
   if [ "${2}" = "start" ] || [ "${2}" = "reconnect" ]; then
       for i in `seq 0 $length`; do
               iptables -t nat -A PREROUTING -d ${Host_ipaddr} -p tcp --dport ${Host_port[$i]} -j DNAT --to ${Guest_ipaddr}:${Guest_port[$i]}
               iptables -I FORWARD -d ${Guest_ipaddr}/32 -p tcp -m state --state NEW -m tcp --dport ${Guest_port[$i]} -j ACCEPT
       done
   fi
fi
                                                                                                                                                                                                                                                                                                                                                                                   cs-svpts-16.02-centos7-amd64.xml                                                                    0000664 0001750 0001750 00000005072 12670461151 015756  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <domain type='kvm'>
  <name>cs-svpts-16.02-centos7-amd64</name>
  <memory unit='KiB'>2097152</memory>
  <currentMemory unit='KiB'>2097152</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-trusty'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='host-model'>
    <model fallback='allow'/>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/cs-svpts-16.02-centos7-amd64-disk1.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </disk>
    <controller type='usb' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'/>
    <interface type='network'>
      <source network='control'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='network'>
      <source network='service'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <interface type='network'>
      <source network='subscriber'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </interface>
    <interface type='network'>
      <source network='internet'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='tablet' bus='usb'/>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </sound>
    <video>
      <model type='cirrus' vram='16384' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </memballoon>
  </devices>
</domain>
                                                                                                                                                                                                                                                                                                                                                                                                                                                                      cs-svsde-16.02-centos6-amd64.xml                                                                    0000664 0001750 0001750 00000004264 12670461151 015724  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <domain type='kvm'>
  <name>cs-svsde-16.02-centos6-amd64</name>
  <memory unit='KiB'>4196352</memory>
  <currentMemory unit='KiB'>4196352</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-trusty'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='host-model'>
    <model fallback='allow'/>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/cs-svsde-16.02-centos6-amd64-disk1.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </disk>
    <controller type='usb' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'/>
    <interface type='network'>
      <source network='control'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='network'>
      <source network='service'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='tablet' bus='usb'/>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </sound>
    <video>
      <model type='cirrus' vram='16384' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </memballoon>
  </devices>
</domain>
                                                                                                                                                                                                                                                                                                                                            cs-svspb-16.02-centos6-amd64.xml                                                                    0000664 0001750 0001750 00000004264 12670461151 015735  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <domain type='kvm'>
  <name>cs-svspb-16.02-centos6-amd64</name>
  <memory unit='KiB'>4196352</memory>
  <currentMemory unit='KiB'>4196352</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-trusty'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='host-model'>
    <model fallback='allow'/>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/cs-svspb-16.02-centos6-amd64-disk1.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </disk>
    <controller type='usb' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'/>
    <interface type='network'>
      <source network='control'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='network'>
      <source network='service'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='tablet' bus='usb'/>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </sound>
    <video>
      <model type='cirrus' vram='16384' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </memballoon>
  </devices>
</domain>
                                                                                                                                                                                                                                                                                                                                            libvirt-control-network.xml                                                                         0000664 0001750 0001750 00000000447 12670461151 016060  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <network>
  <name>control</name>
  <forward mode='nat'/>
  <bridge name='control' stp='on' delay='0'/>
  <domain name='sandvine.rocks'/>
  <ip address='192.168.192.1' netmask='255.255.255.128'>
    <dhcp>
      <range start='192.168.192.2' end='192.168.192.126'/>
    </dhcp>
  </ip>
</network>
                                                                                                                                                                                                                         libvirt-internet-network-bridge.xml                                                                 0000664 0001750 0001750 00000000135 12670461151 017454  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <network>
  <name>internet</name>
  <bridge name='internet' stp='off' delay='0'/>
</network>
                                                                                                                                                                                                                                                                                                                                                                                                                                   libvirt-internet-network-nat.xml                                                                    0000664 0001750 0001750 00000000375 12670461151 017010  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <network>
  <name>internet</name>
  <forward mode='nat'/>
  <bridge name='internet' stp='off' delay='0'/>
  <ip address='10.192.0.1' netmask='255.255.0.0'>
    <dhcp>
      <range start='10.192.0.2' end='10.192.255.254'/>
    </dhcp>
  </ip>
</network>
                                                                                                                                                                                                                                                                   libvirt-service-network.xml                                                                         0000664 0001750 0001750 00000000361 12670461151 016033  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <network>
  <name>service</name>
  <bridge name='service' stp='on' delay='0'/>
  <ip address='192.168.192.129' netmask='255.255.255.128'>
    <dhcp>
      <range start='192.168.192.130' end='192.168.192.254'/>
    </dhcp>
  </ip>
</network>
                                                                                                                                                                                                                                                                               libvirt-subscriber-network.xml                                                                      0000664 0001750 0001750 00000000141 12670461151 016532  0                                                                                                    ustar   ubuntu                          ubuntu                                                                                                                                                                                                                 <network>
  <name>subscriber</name>
  <bridge name='subscriber' stp='off' delay='0'/>
</network>
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               
