#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_nova_server(){
    #����: ��װnova����.
    
    #��鵱ǰ�ڵ��Ƿ�ΪController�ڵ�.
    fn_check_tag_file controller_node
    fn_err_or_info_log "��⵱ǰ�ڵ���: controller "

    fn_check_tag_file nova_server
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: nova_server"
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: keystone "

    fn_check_tag_file glance
    fn_err_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: glance"
    
    fn_exec_eval "yum install -y \
                openstack-nova-api openstack-nova-cert \
                openstack-nova-conductor openstack-nova-console \
                openstack-nova-novncproxy openstack-nova-scheduler"

    #��ʽ:fn_create_db dbName dbUser [dbPasswd]
    fn_create_db nova nova
    fn_create_db nova_api nova

    #source admin-openrc.sh
    . $ADMINOPENRC    

    #��Ȩdefault���µ�nova�û�,��default���µ�service��Ŀ����admin�Ľ�ɫ.
    fn_create_user_and_grant default:nova:${NOVA_PASSWORD} service:admin

    #Ĭ�Ϸ���������openstack.conf �ж����: $REGION ,�����޸Ŀɵ���ָ��: Region=RegionTwo... 
    fn_create_service_and_endpoint nova:"OpenStack Compute Server":compute 3*http://${CONTROLLER_HOST_NAME}:8774/v2.1/%\\\(tenant_id\\\)s

    fn_check_file_and_backup /etc/nova/nova.conf
    local dbconn="mysql+pymysql://nova:${NOVA_PASSWORD}@$CONTROLLER_HOST_NAME/nova"
    fn_exec_openstack-config "
                DEFAULT|enabled_apis=osapi_compute,metadata 
                database|connection=$dbconn
                api_database|connection=${dbconn}_api
                DEFAULT|rpc_backend=rabbit
                oslo_messaging_rabbit|rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=${RABBITMQ_PASSWORD}
                DEFAULT|auth_strategy=keystone
                keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
                keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
                keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service
                keystone_authtoken|username=nova;password=${NOVA_PASSWORD}
                DEFAULT|my_ip=$CONTROLLER_MANAGE_IP;use_neutron=True;firewall_driver=nova.virt.firewall.NoopFirewallDriver
                vnc|vncserver_listen=$CONTROLLER_MANAGE_IP;vncserver_proxyclient_address=$CONTROLLER_MANAGE_IP
                glance|api_servers=http://$CONTROLLER_HOST_NAME:9292
                oslo_concurrency|lock_path=/var/lib/nova/tmp"

    fn_exec_eval 'su -s /bin/sh -c "nova-manage api_db sync" nova'
    fn_exec_sleep 30
	echo $SHOW_nova_TABLES
	fn_exec_eval "$SHOW_nova_TABLES"
	
    fn_exec_eval 'su -s /bin/sh -c "nova-manage db sync" nova'
    fn_exec_sleep 5
	echo "$SHOW_nova_api_TABLES"
	fn_exec_eval "$SHOW_nova_api_TABLES"
    
    fn_exec_systemctl  "openstack-nova-api
                        openstack-nova-cert
                        openstack-nova-consoleauth
                        openstack-nova-scheduler
                        openstack-nova-conductor
                        openstack-nova-novncproxy"

    #source /root/admin-openrc.sh
    . $ADMINOPENRC
    fn_exec_eval "openstack compute service list"
    fn_exec_sleep 3

    #������װ��ɵı�־�ļ�.
    fn_create_tag_file nova_server

    #��װnova�����ʾ.
    fn_inst_componet_complete_prompt "Install Nova Server Successed.@Controller Node"
}

os_fn_inst_nova_server
