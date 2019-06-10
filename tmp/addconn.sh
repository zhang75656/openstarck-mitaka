#!/bin/bash

IntIfname=eno16777736
IntIP4=100.1.192.10/16
IntConnName=int-net

ExIfname=eno33554984
ExIP4=192.168.137.10/24
ExGW4=192.168.137.1
ExConnName=ex-net

HostName=controller

for uuid in `nmcli -t -f uuid conn show`
do
	nmcli conn delete uuid $uuid
done

nmcli conn add con-name $IntConnName type ethernet ifname $IntIfname ip4 $IntIP4
nmcli conn add con-name $ExConnName type ethernet ifname $ExIfname ip4 $ExIP4 gw4 $ExGW4

hostnamectl set-hostname $HostName
