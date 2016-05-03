#! /bin/sh


ebtables -I FORWARD 1 -p 802_1Q --vlan-id 100 -o tap9e060d5e-b7 -j ACCEPT
ebtables -I FORWARD 2 -p 802_1Q --vlan-id 101 -o tap9e060d5e-b7 -j ACCEPT
ebtables -I FORWARD 3 -p 802_1Q -o tap9e060d5e-b7 -j DROP

#ebtables -t broute -A BROUTING --logical-in brqf3660a9c-84 -p 802_1Q --vlan-id 100 -d fa:16:3e:34:15:d1 -j ACCEPT
#ebtables -t broute -A BROUTING --logical-in brqf3660a9c-84 -p 802_1Q --vlan-id 101 -d fa:16:3e:34:15:d1 -j ACCEPT
#ebtables -t broute -A BROUTING --logical-in brqf3660a9c-84 -p 802_1Q -d fa:16:3e:34:15:d1 -j DROP

