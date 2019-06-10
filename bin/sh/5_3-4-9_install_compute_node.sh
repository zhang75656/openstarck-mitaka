#!/bin/bash



os_fn_inst_nova_compute(){
    #��װnova-compute
    
    fn_check_tag_file "compute_node"
    fn_err_or_info_log "��⵱ǰ�ڵ���: compute_node "

    fn_check_tag_file "nova_compute"
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: nova_compute"
    [ $? -eq 0 ] && return 1
    
	[ -f $SLAVE_NODE_CONF ] && . $SLAVE_NODE_CONF || fn_err_log "Not Found compute configure file: $SLAVE_NODE_CONF"
	
    fn_exec_eval "yum install -y openstack-nova-compute"

    #SLAVE_NODE_MANAGE_IP:�ǳ�ʼ���ǿ��ƽڵ�ʱ,����fn_import_os_file����ʱ������.
    local ComputeManageIP=$SLAVE_NODE_MANAGE_IP
    #local ComputeManageIface=`ifconfig |grep -B1 "$ComputeManageIP" |awk -F: '/flags/{print $1}'`
    
    fn_check_file_and_backup /etc/nova/nova.conf

    local VirtType
    egrep -q '(vmx|svm)' /proc/cpuinfo 
    [ $? -eq 0 ] && VirtType=kvm || VirtType=qemu
    fn_check_file_and_backup /etc/nova/nova.conf
    fn_exec_openstack-config "
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
            keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
            keystone_authtoken|username=nova;password=${NOVA_PASSWORD}
            DEFAULT|my_ip=$ComputeManageIP;use_neutron=True;firewall_driver=nova.virt.firewall.NoopFirewallDriver
            vnc|enabled=True;vncserver_listen=0.0.0.0;vncserver_proxyclient_address=$ComputeManageIP
            vnc|novncproxy_base_url=http://$CONTROLLER_MANAGE_IP:6080/vnc_auto.html
            glance|api_servers=http://$CONTROLLER_HOST_NAME:9292
            oslo_concurrency|lock_path=/var/lib/nova/tmp
            libvirt|virt_type=$VirtType"


    fn_exec_systemctl "libvirtd openstack-nova-compute"

    #source /root/admin-openrc.sh
    . $ADMINOPENRC
	fn_info_log "openstack compute service list"
    fn_exec_eval "openstack compute service list"
    fn_exec_sleep 3

    #������װ��ɵı�־�ļ�.
    fn_create_tag_file "nova_compute"

    #��װnova�����ʾ.
    fn_inst_componet_complete_prompt "Install Nova Compute Successed.@Compute Node"
}

os_fn_inst_neutron_compute(){
    #����:��װCompute�ڵ��ϵ�neutron����.

    fn_check_tag_file "compute_node"
    fn_err_or_info_log "��鵱ǰ�ڵ���: compute_node "

    fn_check_tag_file "nova_compute"
    fn_err_or_info_log "������ڵ��Ѱ�װ: nova_compute "

    fn_check_tag_file "neutron_compute_agent"    
    fn_warn_or_info_log "��ǰ����ڵ��Ѿ���װ�� neutron_compute_agent ."
    [ $? -eq 0 ] && return 1

	[ -f $SLAVE_NODE_CONF ] && . $SLAVE_NODE_CONF || fn_err_log "Not Found compute configure file: $SLAVE_NODE_CONF"
	
    fn_exec_eval "yum install openstack-neutron-linuxbridge ebtables ipset -y"

    fn_check_file_and_backup /etc/neutron/neutron.conf
    fn_exec_openstack-config "
                DEFAULT|rpc_backend=rabbit
                oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
                DEFAULT|auth_strategy=keystone;
                keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357;
                keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
                keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
                keystone_authtoken|username=neutron,password=$NEUTRON_PASSWORD
                DEFAULT|notify_nova_on_port_status_changes=True;notify_nova_on_port_data_changes=True
                oslo_concurrency|lock_path=/var/lib/neutron/tmp
                DEFAULT|verbose=True"
    
    local ComputePubNetNIC=$SLAVE_NODE_PUBLIC_NET_NIC
    local ComputeManageIP=$SLAVE_NODE_MANAGE_IP
    
    fn_check_file_and_backup "/etc/neutron/plugins/ml2/linuxbridge_agent.ini"
    fn_exec_openstack-config "
            linux_bridge|physical_interface_mappings=provider:$ComputePubNetNIC
            vxlan|enable_vxlan=True;local_ip=$ComputeManageIP;l2_population=True
            securitygroup|enable_security_group=True
            securitygroup|firewall_driver=neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"
    
    fn_check_file_and_backup /etc/nova/nova.conf
    fn_exec_openstack-config "
            neutron|url=http://$CONTROLLER_HOST_NAME:9696;auth_url=http://$CONTROLLER_HOST_NAME:35357
            neutron|auth_type=password;project_domain_name=default;user_domain_name=default
            neutron|region_name=$REGION_NAME;project_name=service;username=neutron;password=$NEUTRON_PASSWORD"
    
    fn_exec_systemctl "openstack-nova-compute neutron-linuxbridge-agent"
	fn_exec_sleep 5; 
	
	fn_info_log "neutron ext-list; neutron agent-list"
	. $ADMINOPENRC
	fn_exec_eval "neutron ext-list; fn_exec_sleep 5;  neutron agent-list"

    fn_create_tag_file "neutron_compute"
    fn_inst_componet_complete_prompt "Install neutron compute node Successed.@Compute Node"
}

os_fn_inst_ceilometer_compute(){
    #����: ��װ�ռ�����ڵ���Ϣ�ķ���,���ɽ��ռ�����Ϣ�ϱ���Controller�ϵ�
    #   �����(ceilometer-server).

    fn_check_tag_file "compute_node"
    fn_err_or_info_log "��鵱ǰ�ڵ���: compute_node "

    fn_check_tag_file "nova_compute"
    fn_err_or_info_log "������ڵ��Ѱ�װ: nova_compute "

    fn_check_tag_file "ceilometer_node"    
    fn_warn_or_info_log "��ǰ����ڵ��Ѿ���װ�� ceilometer_node ."
    [ $? -eq 0 ] && return 1

	. $ADMINOPENRC
    fn_exec_eval "openstack user list | grep -q '\<ceilometer\>'"
    [ $? -eq 0 ] || fn_err_log "û�м�⵽ceilometer�û�,��ȷ�Ͽ��ƽڵ��Ѿ���װ��Ceilometer����."

    #�Լ���ڵ������.                                 
    fn_exec_eval "yum install openstack-ceilometer-compute python-ceilometerclient python-pecan -y"
                                                       
    local DomProjInfo="project_domain_name=default;user_domain_name=default;project_name=service"
    local RabbitInfo="rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD"
    local MemAuthURL="auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357;memcached_servers=$CONTROLLER_HOST_NAME:11211"
                                                       
    fn_check_file_and_backup "/etc/ceilometer/ceilometer.conf"
    fn_exec_openstack-config "                         
            DEFAULT|rpc_backend=rabbit                 
            oslo_messaging_rabbit|$RabbitInfo          
            DEFAULT|auth_strategy=keystone             
            keystone_authtoken|$MemAuthURL;$DomProjInfo
            keystone_authtoken|auth_type=password;username=ceilometer;password=$CEILOMETER_PASSWORD
            service_credentials|os_auth_url=http://$CONTROLLER_HOST_NAME:5000/v2.0;interface=internalURL
            service_credentials|os_username=ceilometer;os_password=$CEILOMETER_PASSWORD;os_tenant_name=service
            service_credentials|region_name=$REGION_NAME"
                                                       
    fn_check_file_and_backup "/etc/nova/nova.conf"     
    fn_exec_openstack-config "                         
            DEFAULT|instance_usage_audit=True;instance_usage_audit_period=hour
            DEFAULT|notify_on_state_change=vm_and_task_state;notification_driver=messagingv2"
                                                       
    fn_exec_systemctl "openstack-ceilometer-compute openstack-nova-compute"

    fn_create_tag_file "ceilometer_node"
    fn_inst_componet_complete_prompt "Install Ceilometer Agent Successed.@Compute Node"
}

