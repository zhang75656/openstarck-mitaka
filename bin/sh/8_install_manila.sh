#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_manila_server(){
    #功能：安装共享存储服务:manila.
    
    #检查当前节点是否为Controller节点.
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller "

    fn_check_tag_file manila_server
    fn_warn_or_info_log "检测当前节点已安装: manila_server"
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "检测当前节点已安装: keystone "

    fn_check_tag_file neutron_server
    fn_err_or_info_log "检测当前节点已安装: neutron_server"
    
    fn_create_db manila manila
    
    . $ADMINOPENRC
    fn_create_user_and_grant default:manila:$MANILA_PASSWORD service:admin
    fn_create_service_and_endpoint manila:"OpenStack Shared File Systems":share 3*http://$CONTROLLER_HOST_NAME:8786/v1/%\\\(tenant_id\\\)s
    fn_create_service_and_endpoint manilav2:"OpenStack Shared File Systems":sharev2 3*http://$CONTROLLER_HOST_NAME:8786/v2/%\\\(tenant_id\\\)s

    fn_exec_eval "yum install -y openstack-manila python-manilaclient"

    local manilaconf=/etc/manila/manila.conf
    fn_check_file_and_backup "$manilaconf"
    fn_exec_openstack-config "
            database|connection=mysql+pymysql://manila:$MANILA_PASSWORD@$CONTROLLER_HOST_NAME/manila
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
            DEFAULT|default_share_type=default_share_type;rootwrap_config=/etc/manila/rootwrap.conf
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
            keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
            keystone_authtoken|username=manila;password=$MANILA_PASSWORD
            DEFAULT|my_ip=$CONTROLLER_MANAGE_IP
            oslo_concurrency|lock_path=/var/lib/manila/tmp"

    fn_exec_eval "su -s /bin/sh -c 'manila-manage db sync' manila"
    fn_exec_sleep 3
	echo $SHOW_manila_TABLES
	fn_exec_eval "$SHOW_manila_TABLES"
	
    fn_exec_systemctl "openstack-manila-api openstack-manila-scheduler"

    fn_create_tag_file "manila_server"
    fn_inst_componet_complete_prompt "Install Manila(Share File System) Service Successed.@Controller Node."

}

os_fn_inst_manila_server
