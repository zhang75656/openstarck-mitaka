#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_cinder_server(){
    #功能: 安装cinder-server服务.

    #检查当前节点是否为Controller节点.
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller_node "

    fn_check_tag_file cinder_server
    fn_warn_or_info_log "检测当前节点已安装: cinder_server "
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "检测当前节点已安装: keystone "

    #创建数据库
    fn_create_db cinder cinder
    
    . $ADMINOPENRC
    fn_create_user_and_grant default:cinder:$CINDER_PASSWORD service:admin
    fn_create_service_and_endpoint cinder:"OpenStack Block Storage.":volume 3*http://${CONTROLLER_HOST_NAME}:8776/v1/%\\\(tenant_id\\\)s 
    fn_create_service_and_endpoint cinderv2:"OpenStack Block Storage.":volumev2 3*http://${CONTROLLER_HOST_NAME}:8776/v2/%\\\(tenant_id\\\)s 

    fn_exec_eval "yum install -y openstack-cinder"

    local dbconn="mysql+pymysql://cinder:$CINDER_PASSWORD@$CONTROLLER_HOST_NAME/cinder"
    fn_check_file_and_backup "/etc/cinder/cinder.conf"
    fn_exec_openstack-config "
            database|connection=$dbconn DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBIT_USERNAME;rabbit_password=$RABBIT_PASSWORD
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
            keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
            keystone_authtoken|username=cinder;password=$CINDER_PASSWORD
            oslo_concurrency|lock_path=/var/lib/cinder/tmp
            DEFAULT|my_ip=$CONTROLLER_MANAGE_IP"

    fn_exec_eval 'su -s /bin/sh -c "cinder-manage db sync" cinder'
    fn_exec_sleep 3
	echo $SHOW_cinder_TABLES
	fn_exec_eval "$SHOW_cinder_TABLES"

    fn_check_file_and_backup /etc/nova/nova.conf
    fn_exec_openstack-config "cinder|os_region_name=$REGION_NAME"
    
    fn_exec_systemctl "openstack-nova-api openstack-cinder-api openstack-cinder-scheduler"

    . $ADMINOPENRC
    fn_exec_eval "cinder service-list"
    fn_exec_sleep 30
    fn_exec_eval "cinder service-list |tee -a _tmp"
    awk -F'|' '$6!~/State|^$/{print $6}' _tmp |grep -qi "down"
    [ $? -eq 0 ] && fn_err_log "Cinder服务启动失败." || fn_info_log "Cinder服务启动成功."
    rm -f _tmp

    fn_create_tag_file "cinder_server"
    fn_inst_componet_complete_prompt "Install Cinder Service Sucessed.@Controller Node"
}

os_fn_inst_cinder_server
