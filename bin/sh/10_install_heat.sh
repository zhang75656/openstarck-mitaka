#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_heat(){
    #����:��װ�������������heat.

    #��鵱ǰ�ڵ��Ƿ�ΪController�ڵ�.
    fn_check_tag_file controller_node
    fn_err_or_info_log "��⵱ǰ�ڵ���: controller "

    fn_check_tag_file heat
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: heat "
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: keystone "

    fn_create_db heat heat

    . $ADMINOPENRC
    fn_create_user_and_grant default:heat:$HEAT_PASSWORD service:admin
    fn_create_service_and_endpoint heat:"OpenStack Orchestration":orchestration 3*http://$CONTROLLER_HOST_NAME:8004/v1/%\\\(tenant_id\\\)s
    fn_create_service_and_endpoint heat-cfn:"OpenStack Orchestration":cloudformation 3*http://$CONTROLLER_HOST_NAME:8000/v1
    
    fn_create_domain_project_role heat:"Stack projects and users" none:none:none heat_stack_owner
    fn_create_user_and_grant heat:heat_domain_admin:$HEAT_DOMAIN_ADMIN_PASSWORD none:none

    #��Ȩheat_domain_admin�û����й���heat���Ȩ��.
    local cmd="openstack role add --domain heat --user-domain heat --user heat_domain_admin admin"
    fn_exec_eval -w "openstack role list |grep -q '\<heat_domain_admin\>'"
    [ $? -eq 0 ] && fn_info_log "heat_domain_admin�Ѿ���Ȩ,�����ٴ���Ȩ." || fn_exec_eval "$cmd"

    #����demo�û���demo��Ŀ�е���heat_stack_owner��ɫ.
    fn_create_user_and_grant none:demo:none demo:heat_stack_owner
    
    #����heat_stack_user��ɫ.
    fn_create_domain_project_role none:none none:none:none heat_stack_user

    fn_exec_eval "yum install openstack-heat-api openstack-heat-api-cfn openstack-heat-engine -y"

    fn_check_file_and_backup "/etc/heat/heat.conf"
    fn_exec_openstack-config "
            database|connection=mysql+pymysql://heat:$HEAT_PASSWORD@$CONTROLLER_HOST_NAME/heat
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME
            oslo_messaging_rabbit|rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
            keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
            keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
            keystone_authtoken|username=heat;password=$HEAT_PASSWORD
            trustee|auth_plugin=password;auth_url=http://$CONTROLLER_HOST_NAME:35357
            trustee|username=heat;password=$HEAT_PASSWORD;user_domain_name=default
            clients_keystone|auth_uri=http://$CONTROLLER_HOST_NAME:35357
            ec2authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000
            DEFAULT|heat_metadata_server_url=http://$CONTROLLER_HOST_NAME:8000
            DEFAULT|heat_waitcondition_server_url=http://${CONTROLLER_HOST_NAME}:8000/v1/waitcondition
            DEFAULT|stack_domain_admin=heat_domain_admin
            DEFAULT|stack_domain_admin_password=${HEAT_DOMAIN_ADMIN_PASSWORD};stack_user_domain_name=heat"


    fn_exec_eval "su -s /bin/sh -c 'heat-manage db_sync' heat"
	echo $SHOW_heat_TABLES
	fn_exec_eval "$SHOW_heat_TABLES"

    fn_exec_systemctl "openstack-heat-api openstack-heat-api-cfn openstack-heat-engine"
	fn_exec_sleep 30
	
    #source /root/admin-openrc.sh
    . $ADMINOPENRC
    fn_exec_eval "openstack orchestration service list"
    fn_exec_sleep 5 

    fn_create_tag_file "heat"
    fn_inst_componet_complete_prompt "Install Heat Sucessed. @Controller Node"

}

os_fn_inst_heat
