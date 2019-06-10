#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_neutron_server(){
    #功能:安装neutron-server.

    #检查当前节点是否为Controller节点.
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller "

    fn_check_tag_file neutron_server
    fn_warn_or_info_log "检测当前节点已安装: neutron_server"
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "检测当前节点已安装: keystone "

    fn_check_tag_file nova_server
    fn_err_or_info_log "检测当前节点已安装: nova_server,(需先安装nova)"

    fn_create_db neutron neutron
    
    #source /root/admin-openrc.sh
    . $ADMINOPENRC

    fn_create_user_and_grant default:neutron:$NEUTRON_PASSWORD service:admin
    fn_create_service_and_endpoint neutron:"OpenStack Networking Service":network 3*http://$CONTROLLER_HOST_NAME:9696

    fn_exec_eval "yum install -y openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge ebtables "
    
    #修改neutron.conf
	#注:	503 Service Unavailable, neutron-server.log中提示需要认证("code": 401, "title": "Unauthorized"):
	#   这多半是此配置文件中认证部分有错误.
    local neutron_conf=/etc/neutron/neutron.conf
    fn_check_file_and_backup "$neutron_conf"
    fn_exec_openstack-config "
                database|connection=mysql+pymysql://neutron:$NEUTRON_PASSWORD@$CONTROLLER_HOST_NAME/neutron
                DEFAULT|core_plugin=ml2;service_plugins=router;allow_overlapping_ips=True;rpc_backend=rabbit
                oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
                DEFAULT|auth_strategy=keystone;
                keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357;
                keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
                keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
                keystone_authtoken|username=neutron;password=$NEUTRON_PASSWORD
                DEFAULT|notify_nova_on_port_status_changes=True;notify_nova_on_port_data_changes=True
                nova|auth_url=http://$CONTROLLER_HOST_NAME:35357;auth_type=password;username=nova;password=$NOVA_PASSWORD
                nova|project_domain_name=default;user_domain_name=default;region_name=$REGION_NAME;project_name=service
                oslo_concurrency|lock_path=/var/lib/neutron/tmp
                DEFAULT|verbose=True"

    local ml2_conf_ini=/etc/neutron/plugins/ml2/ml2_conf.ini
    fn_check_file_and_backup "$ml2_conf_ini"
    fn_exec_openstack-config "
            ml2|type_drivers=flat,vlan,vxlan;mechanism_drivers=linuxbridge,l2population
            ml2|tenant_network_types=vxlan;extension_drivers=port_security
            ml2_type_flat|flat_networks=provider
            ml2_type_vxlan|vni_ranges=1:1000
            securitygroup|enable_ipset=True"

    fn_check_file_and_backup "/etc/neutron/plugins/ml2/linuxbridge_agent.ini"
    fn_exec_openstack-config "
            linux_bridge|physical_interface_mappings=provider:$CONTROLLER_PUBLIC_NET_NIC
            vxlan|enable_vxlan=True;local_ip=$CONTROLLER_MANAGE_IP;l2_population=True
            securitygroup|enable_security_group=True;firewall_driver=neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"

    fn_check_file_and_backup "/etc/neutron/l3_agent.ini" 
    fn_exec_openstack-config "
            DEFAULT|interface_driver=neutron.agent.linux.interface.BridgeInterfaceDriver
            DEFAULT|external_network_bridge;verbose=True"
    
    fn_check_file_and_backup "/etc/neutron/dhcp_agent.ini"
    fn_exec_openstack-config "
            DEFAULT|interface_driver=neutron.agent.linux.interface.BridgeInterfaceDriver
            DEFAULT|dhcp_driver=neutron.agent.linux.dhcp.Dnsmasq;enable_isolated_metadata=True
            DEFAULT|verbose=True"

    fn_exec_eval 'echo "dhcp-option-force=26,1450"> /etc/neutron/dnsmasq-neutron.conf'

    fn_check_file_and_backup "/etc/neutron/metadata_agent.ini"
    fn_exec_openstack-config "
            DEFAULT|nova_metadata_ip=$CONTROLLER_HOST_NAME;metadata_proxy_shared_secret=$NEUTRON_METADATA_SHARED_PASSWORD
            DEFAULT|verbose=True"

    fn_check_file_and_backup "/etc/nova/nova.conf"
    fn_exec_openstack-config "
            neutron|url=http://$CONTROLLER_HOST_NAME:9696;auth_url=http://$CONTROLLER_HOST_NAME:35357
            neutron|auth_type=password;username=neutron;password=$NEUTRON_PASSWORD
            neutron|project_domain_name=default;user_domain_name=default
            neutron|region_name=$REGION_NAME;project_name=service;service_metadata_proxy=True
            neutron|metadata_proxy_shared_secret=$NEUTRON_METADATA_SHARED_PASSWORD"

    local plugin_ini_link=/etc/neutron/plugin.ini
    fn_exec_eval "rm -f $plugin_ini_link && ln -s $ml2_conf_ini $plugin_ini_link"

    #同步neutron数据库
    fn_exec_eval "su -s /bin/sh -c 'neutron-db-manage --config-file $neutron_conf --config-file $ml2_conf_ini upgrade head' neutron"
    fn_exec_sleep 5
	echo $SHOW_neutron_TABLES
	fn_exec_eval "$SHOW_neutron_TABLES"
	
    fn_exec_systemctl "
            openstack-nova-api
            neutron-server
            neutron-linuxbridge-agent
            neutron-dhcp-agent
            neutron-metadata-agent
            neutron-l3-agent"
    
    . $ADMINOPENRC
    fn_exec_eval "neutron ext-list; fn_exec_sleep 3; neutron agent-list"

    #创建标志文件.
    fn_create_tag_file "neutron_server"
    fn_inst_componet_complete_prompt "Install Neutron Server Completed.@Controller Node"
}

os_fn_inst_neutron_server
