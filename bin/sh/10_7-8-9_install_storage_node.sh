#!/bin/bash

os_fn_inst_cinder_node(){
    #����: ��װblock�ڵ�,ΪVM�ṩ���豸.

    fn_check_tag_file "storage_node"
    fn_err_or_info_log "��鵱ǰ�ڵ���: storage_node "

    fn_check_tag_file "cinder"
    fn_warn_or_info_log "��鵱ǰ�ڵ��Ѱ�װ: cinder "
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
    [ $? -eq 0 ] && fn_err_log "Cinder��������ʧ��." || fn_info_log "Cinder���������ɹ�."
    rm -f _tmp

    #USER_ceilometer=`openstack user list | grep ceilometer | grep -v ceilometer_domain_admin | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
    #if [ ${USER_ceilometer}x = ceilometerx ]
    fn_exec_eval -w "openstack user list | grep -q '\<ceilometer\>'"
    if [ $? -eq 0 ]
    then
        #�ڿ��ƺ�block�洢�ڵ�������Cinderʹ��ceilometer.
        fn_check_file_and_backup "/etc/cinder/cinder.conf"
        fn_exec_openstack-config "oslo_messaging_notifications|driver=messagingv2"
        fn_exec_systemctl "openstack-cinder-volume"
    else
    	fn_warn_log "û�м�⵽:ceilometer�˻�,���ƽڵ��Ͽ���û�а�װ"ceilometer"����,Cinder������Ceilometer������."
    fi

    fn_create_tag_file "cinder_node"
    fn_inst_componet_complete_prompt "Install Cinder(Block) Service Successed.@Storage Node"
}

os_fn_inst_manila_node(){
    #����:��װ�����ļ�ϵͳ�ڵ�:manila node.
    #   ��������ģʽ:
    #   1.��֧�ֹ����������.��ģʽ��,�������κ��������йص�����.
    #     ����Ҫʵ����NFS������֮���������������.
    #     ��ѡ��ʹ��LVM������ҪLVM��NFS������manila����LVM������Ӵ���.

    #   2.֧�ֹ��������������,��ģʽ��,������ҪNova,Neutron,
    #     Cinder����,���������������.���ڴ����������������Ϣ������
    #     Ϊ��������,��ģʽʹ��ͨ�õ����������빲��������Ĵ���������
    #     ��Ҫ���ӵ��Զ�������·����.
    
    fn_check_tag_file "storage_node"
    fn_err_or_info_log "��鵱ǰ�ڵ���: storage_node "
                                               
    fn_check_tag_file "manila"
    fn_warn_or_info_log "��鵱ǰ�ڵ��Ѱ�װ: manila "
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
        #��װmanilaģʽ2
        #���nova, neutron, cinder�Ƿ��Ѿ���������Ӧ���û�.��Ӽ�������Ѿ��ڿ��ƽڵ㰲װ��.
        
        fn_info_log "Manilaģʽ2��Ҫʹ��neutron,nova,cinder��ΪVM�ṩ�����ļ��ķ���,��ȷ���Ѿ��ڿ��ƽڵ��ϰ�װ��������Щ������."
        fn_exec_eval -w "openstack user list |tee -a _tmp |grep -q '\<nova\>'"
        fn_warn_or_info_log "������nova�����˻�"
        
        fn_exec_eval -w "grep -q '\<neutron\>' _tmp"
        fn_warn_or_info_log "������neutron�����˻�"
        
        fn_exec_eval -w "grep -q '\<cinder\>' _tmp"
        fn_warn_or_info_log "������cinder�����˻�"
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
        #��װmanilaģʽ1

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

