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

ifdown br-ex
ifdown dummy0
ifdown dummy1

rm /etc/network/interfaces.d/br-ex.cfg
rm /etc/network/interfaces.d/dummy*

apt-get purge chrony dnsmasq-base libvirt0 ubuntu-virt-server apache2 libapache2-mod-wsgi memcached mysql-common rabbitmq-server keystone "glance-*" "nova-*" "neutron-*" "cinder-*" "heat-*" "openstack-*" "manila-*" "openvswitch-*" -y

apt-get autoremove -y

dpkg -P `dpkg -l | grep ^rc | awk $'{print $2}' | xargs`

rm -r /etc/mysql /etc/openstack-dashboard /etc/apache2 /etc/keystone /etc/glance /etc/neutron /etc/nova /etc/heat /etc/cinder /var/lib/mysql /var/lib/nova /var/lib/glance /var/lib/keystone /var/lib/heat /var/lib/neutron /var/lib/cinder /var/lib/manila /var/lib/openvswitch /var/lib/libvirt /var/log/neutron /var/log/nova /var/log/glance /var/log/cinder /var/log/manila  /var/log/apache2 /var/lib/openstack-dashboard /usr/share/openstack-dashboard /usr/lib/python2.7/dist-packages/horizon/static/horizon/lib/jquery -f

rmmod openvswitch

iptables -F
iptables -X
iptables -F -t nat
iptables -X -t nat
