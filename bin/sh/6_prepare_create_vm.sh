#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE
G_MSG=

os_fn_create_keypair_and_secgroup(){
    #功能: 创建keypair和安全组.

    . $ADMINOPENRC
    #创建flavor
	fn_exec_eval "openstack flavor list |tee _tmp"
	local FlavorName='m1.cirros'
	
	local cmd="openstack flavor create --id auto --vcpus 1 --ram 64 --disk 1 $FlavorName"
    grep -q "\<$FlavorName\>" _tmp 
	if [ $? -ne 0 ]
	then
		fn_exec_eval "$cmd"
		G_MSG="Create flavor: $FlavorName@"
	fi

    #创建keypair
    cmd=
	. $DEMOOPENRC
    if [ -z "${KEYPAIR_LIST[*]}" ]
    then
        cmd="ssh-keygen -t dsa -f ~/.ssh/id_dsa -N '' && openstack keypair create --public-key ~/.ssh/id_dsa.pub mykey"
		G_MSG="$G_MSG Create keypair:mykey@"
    else
        local keyName keyPath keyType
        fn_exec_eval "openstack keypair list |tee _tmp"
        for kp in ${KEYPAIR_LIST[*]}
        do
            keyName=${kp%%:*}
            keyPath=`a=${kp#*:};echo ${a%:*}`
            keyType=${kp##*:}
            grep -q "\<$keyName\>" _tmp && continue
            if [ -f "$keyPath" ]
            then
                cmd="$cmd openstack keypair create --public-key ${keyPath}.pub $keyName;"
				G_MSG="$G_MSG Create keypair: $keyName@"
            else
				cmd="rm -f $keyPath;"
                cmd="$cmd ssh-keygen -t $keyType -f $keyPath -N '' && openstack keypair create --public-key ${keyPath}.pub $keyName;"
				G_MSG="$G_MSG Create SSH keypair:$keyPath and openstack keypair: $keyName@"
            fi
        done
        rm -f _tmp
    fi
    [ -n "$cmd" ] && fn_exec_eval "$cmd"

    . $ADMINOPENRC
    #创建安全组规则
    SECRULE=`nova secgroup-list-rules default |awk '/22/{print$4}'`
    if [ x${SECRULE} == x22 ]
    then 
    	fn_info_log "port 22 and icmp had add to secgroup."
    else
    	fn_exec_eval "openstack security group rule create --proto icmp default"
    	fn_exec_eval "openstack security group rule create --proto tcp --dst-port 22 default"
		G_MSG="$G_MSG Create Security Group Rule:allow icmp and port:22(secgroup:default )@"
    fi
}

os_fn_create_virt_net(){ 
    #功能: 创建虚拟网络

    . $ADMINOPENRC
    fn_exec_eval "neutron net-list |tee _tmp"
    local ExNet=provider
    local ExNetType=flat
    local ExNetName=provider

    cmd="neutron net-create --shared --provider:physical_network $ExNet --provider:network_type $ExNetType $ExNetName"
    grep -q "\<$ExNet\>" _tmp
	if [ $? -ne 0 ]
	then 
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Create External Network(ProviderNet):$ExNetName@"
	fi
	
    fn_exec_eval "neutron subnet-list |tee _tmp"
    local ExSubnetName=provider
    local ExIPPool="start=$PUBLIC_NET_START,end=$PUBLIC_NET_END"

	cmd="neutron subnet-create --name $ExSubnetName --allocation-pool $ExIPPool --dns-nameserver ${PUBLIC_NET_DNS} --gateway ${PUBLIC_NET_GW} provider $PUBLIC_NET"
    grep -q "\<$ExSubnetName\>" _tmp
	if [ $? -ne 0 ]
	then 
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Create External Subnet(ProviderNet):$ExSubnetName($ExIPPool)@"
	fi
    
    . $DEMOOPENRC
    fn_exec_eval "neutron net-list |tee _tmp"
    local IntNetName=selfservice
    
	cmd="neutron net-create $IntNetName"
    grep -q "\<$IntNetName\>" _tmp
	if [ $? -ne 0 ]
	then 
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Create Internal Network(PrivateNet):$IntNetName@"
	fi

    fn_exec_eval "neutron subnet-list |tee _tmp"
    local IntSubnetName=selfservice
    
    cmd="neutron subnet-create --name $IntSubnetName --dns-nameserver ${PRIVATE_NET_DNS} --gateway ${PRIVATE_NET_GW}  selfservice ${PRIVATE_NET}"
    grep -q "\<$IntSubnetName\>" _tmp
	if [ $? -ne 0 ]
	then 
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Create Internal Subnet(PrivateSubnet):$IntSubnetName($PRIVATE_NET)@"
	fi
    
    . $ADMINOPENRC
    local ExRouterYN=`neutron net-show $ExNetName |awk '/router:external/{print $4}'`

    cmd="neutron net-update $ExNetName --router:external"
    if [ "$ExRouterYN" != "True" ]
	then
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Net-Update: $ExNetName = Router:External=True@"
	fi
	
    . $DEMOOPENRC
    fn_exec_eval "neutron router-list |tee _tmp"
    local IntRouterName=router

    cmd="neutron router-create $IntRouterName;"
    cmd="$cmd neutron router-interface-add $IntRouterName $IntSubnetName;"
    cmd="$cmd neutron router-gateway-set $IntRouterName $ExSubnetName"
    grep -q "\<$IntRouterName\>" _tmp
	if [ $? -ne 0 ]
	then 
		fn_exec_eval "$cmd"
		G_MSG="$G_MSG Create Private Router:($IntSubnetName)--$IntRouterName--($ExSubnetName)"
	fi
	
    rm -f _tmp
    unset cmd

    fn_exec_eval "neutron router-port-list $IntRouterName" "Demo测试"

    . $ADMINOPENRC
    fn_exec_eval "neutron router-port-list $IntRouterName" "Admin测试"

    fn_exec_eval "ip netns list"
}

#set -o xtrace
os_fn_create_keypair_and_secgroup
os_fn_create_virt_net
fn_inst_componet_complete_prompt "$G_MSG@Controller Node"
#set +o xtrace
