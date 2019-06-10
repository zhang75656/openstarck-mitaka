#!/bin/bash

os_fn_inst_cinder_node(){
    #功能: 安装block节点,为VM提供块设备.

    fn_check_tag_file "storage_node"
    fn_err_or_info_log "检查当前节点是: storage_node "

    fn_check_tag_file "cinder"
    fn_warn_or_info_log "检查当前节点已安装: cinder "
    [ $? -eq 0 ] && return 1

	[ -f $SLAVE_NODE_CONF ] && . $SLAVE_NODE_CONF || fn_err_log "Not Found Storage node configure file: $SLAVE_NODE_CONF"

    fn_exec_eval "yum install -y lvm2 python-oslo-policy openstack-cinder targetcli python-keystonemiddleware*"
    fn_exec_systemctl "lvm2-lvmetad"

    fn_chk_disk_and_create_vg "cinder"
    
    local CinderManageIP=$SLAVE_NODE_MANAGE_IP
    fn_check_file_and_backup "/etc/cinder/cinder.conf"
    fn_exec_openstack-config "
            database|connection=mysql+pymysql://cinder:$CINDER_PASSWORD@$CONTROLLER_HOST_NAME/cinder
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
            keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service keystone_authtoken|username=cinder;password=$CINDER_PASSWORD
            DEFAULT|my_ip=$CinderManageIP oslo_concurrency|lock_path=/var/lib/cinder/tmp
            DEFAULT|glance_api_servers=http://$CONTROLLER_HOST_NAME:9292;enabled_backends=lvm
            lvm|volume_driver=cinder.volume.drivers.lvm.LVMVolumeDriver;volume_group=cinder_volumes
            lvm|iscsi_protocol=iscsi;iscsi_helper=lioadm"

    #chown cinder:cinder /etc/cinder/cinder.conf

    fn_exec_systemctl "openstack-cinder-volume target"

    . $ADMINOPENRC
    #cinder service-list
    fn_exec_eval "cinder service-list"
    fn_exec_sleep 30
    fn_exec_eval "cinder service-list |tee -a _tmp"
    awk -F'|' '$6!~/State|^$/{print $6}' _tmp |grep -qi "down"
    [ $? -eq 0 ] && fn_err_log "Cinder服务启动失败." || fn_info_log "Cinder服务启动成功."
    rm -f _tmp

    #USER_ceilometer=`openstack user list | grep ceilometer | grep -v ceilometer_domain_admin | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
    #if [ ${USER_ceilometer}x = ceilometerx ]
    fn_exec_eval -w "openstack user list | grep -q '\<ceilometer\>'"
    if [ $? -eq 0 ]
    then
        #在控制和block存储节点上配置Cinder使用ceilometer.
        fn_check_file_and_backup "/etc/cinder/cinder.conf"
        fn_exec_openstack-config "oslo_messaging_notifications|driver=messagingv2"
        fn_exec_systemctl "openstack-cinder-volume"
    else
    	fn_warn_log "没有检测到:ceilometer账户,控制节点上可能没有安装"ceilometer"服务,Cinder将忽略Ceilometer的配置."
    fi

    fn_create_tag_file "cinder_node"
    fn_inst_componet_complete_prompt "Install Cinder(Block) Service Successed.@Storage Node"
}

os_fn_inst_manila_node(){
    #功能:安装共享文件系统节点:manila node.
    #   它分两种模式:
    #   1.不支持共享管理驱动.此模式下,服务不做任何与网络有关的事情.
    #     它需要实例和NFS服务器之间的网络连接正常.
    #     此选项使用LVM驱动需要LVM和NFS包及给manila共享LVM卷组添加磁盘.

    #   2.支持共享管理驱动程序,此模式下,服务需要Nova,Neutron,
    #     Cinder服务,用来管理共享服务器.用于创建共享服务器的信息被配置
    #     为共享网络,此模式使用通用的驱动程序与共享服务器的处理能力和
    #     需要附加的自动化网络路由器.
    
    fn_check_tag_file "storage_node"
    fn_err_or_info_log "检查当前节点是: storage_node "
                                               
    fn_check_tag_file "manila"
    fn_warn_or_info_log "检查当前节点已安装: manila "
    [ $? -eq 0 ] && return 1

	[ -f $SLAVE_NODE_CONF ] && . $SLAVE_NODE_CONF || fn_err_log "Not Found Storage node configure file: $SLAVE_NODE_CONF"

    fn_exec_eval "yum install openstack-manila-share python2-PyMySQL -y"

	local ManilaManageIP=$SLAVE_NODE_MANAGE_IP
    local manilaconf=/etc/manila/manila.conf
    local MemAuthURL="memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357"
    fn_check_file_and_backup "$manilaconf"
    fn_exec_openstack-config "
            database|connection=mysql+pymysql://manila:$MANILA_PASSWORD@$CONTROLLER_HOST_NAME/manila
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
            DEFAULT|default_share_type=default_share_type;rootwrap_config=/etc/manila/rootwrap.conf
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|$MemAuthURL;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
            keystone_authtoken|username=manila;password=$MANILA_PASSWORD
            DEFAULT|my_ip=$ManilaManagerIP
			oslo_concurrency|lock_path=/var/lib/manila/tmp"
        
    in_fn_support_driver_manila(){
        #安装manila模式2
        #检查nova, neutron, cinder是否已经创建了相应的用户.间接检查他们已经在控制节点安装了.
        
        fn_info_log "Manila模式2需要使用neutron,nova,cinder来为VM提供共享文件的服务,请确保已经在控制节点上安装并启动这些服务了."
        fn_exec_eval -w "openstack user list |tee -a _tmp |grep -q '\<nova\>'"
        fn_warn_or_info_log "检查存在nova服务账户"
        
        fn_exec_eval -w "grep -q '\<neutron\>' _tmp"
        fn_warn_or_info_log "检查存在neutron服务账户"
        
        fn_exec_eval -w "grep -q '\<cinder\>' _tmp"
        fn_warn_or_info_log "检查存在cinder服务账户"
        rm -f _tmp

        fn_exec_eval "yum install openstack-neutron openstack-neutron-linuxbridge ebtables -y"

        local MemAuthURL="memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357"
        local DomProjInfo="project_domain_name=default;user_domain_name=default;project_name=service;region_name=$REGION_NAME"
        fn_check_file_and_backup "$manilaconf"
        fn_exec_openstack-config "
                DEFAULT|enabled_share_backends=generic;enabled_share_protocols=NFS,CIFS
                neutron|url=http://$CONTROLLER_HOST_NAME:9696;$MemAuthURL;$DomProjInfo
                neutron|auth_type=password;username=neutron;password=$NEUTRON_PASSWORD
                nova|$MemAuthURL;auth_type=password;username=nova;password=$NOVA_PASSWORD;$DomProjInfo
                cinder|$MemAuthURL;auth_type=password;username=cinder;password=$CINDER_PASSWORD;$DomProjInfo
                generic|share_backend_name=GENERIC;share_driver=manila.share.drivers.generic.GenericShareDriver
                generic|driver_handles_share_servers=True;service_instance_flavor_id=100;service_image_name=manila-service-image
                generic|service_instance_user=manila;service_instance_password=manila;interface_driver=manila.network.linux.interface.BridgeInterfaceDriver"
    }
    
    in_fn_nosuppot_driver_manila () {
        #安装manila模式1

        fn_exec_eval "yum install lvm2 nfs-utils nfs4-acl-tools portmap -y"
        fn_exec_systemctl "lvm2-lvmetad"
    
        local ManilaManageIP=$SLAVE_NODE_MANAGE_IP
        fn_chk_disk_and_create_vg "manila"
        fn_check_file_and_backup "$manilaconf"
        fn_exec_openstack-config "
                DEFAULT|enabled_share_backends=lvm;enabled_share_protocols=NFS,CIFS
                lvm|share_backend_name=LVM;share_driver=manila.share.drivers.lvm.LVMShareDriver
                lvm|driver_handles_share_servers=False;lvm_share_volume_group=manila_volumes
                lvm|lvm_share_export_ip=$ManilaManageIP"
    }

    [ -z "$STORAGE_MANILA_DISK" ] && in_fn_suppot_driver_manila || in_fn_nosuppot_driver_manila

    fn_exec_systemctl "openstack-manila-share"

    #. $ADMINOPENRC
    #fn_exec_eval "manila service-list"
 
    fn_create_tag_file "manila"
    fn_inst_componet_complete_prompt "Install Manila(Shared File System) Service Successed.@Storage node"
}

