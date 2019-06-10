#!/bin/bash

. $os_FUNCS
. $os_CONF_FILE

os_fn_inst_ceilometer(){
    #����: ��װCeilometer����.

    #��鵱ǰ�ڵ��Ƿ�ΪController�ڵ�.
    fn_check_tag_file controller_node
    fn_err_or_info_log "��⵱ǰ�ڵ���: controller "

    fn_check_tag_file ceilometer_server
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: ceilometer_server "
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: keystone "

    fn_exec_eval "yum install mongodb-server mongodb -y"

    local mongodconf="/etc/mongod.conf"
    fn_check_file_and_backup "$mongodconf"
    cat $MONGODB_CONF_FILE > $mongodconf
    sed -i "s/<ManageIP>/$CONTROLLER_MANAGE_IP/" $mongodconf
    
    fn_exec_systemctl "mongod"
    
    #create ceilometer databases 
    #mongo --host ${HOSTNAME} >testceilometer 2>/dev/null <<EOF
    #use admin ;
    #db.system.users.find()
    #exit
    #EOF
    #TEST_DB=`cat testceilometer  | grep ceilometer | wc -l `

    cat > _create_mongo_db <<EOF
mongo --host $CONTROLLER_HOST_NAME --eval '
  db = db.getSiblingDB("ceilometer");
  db.createUser({user: "ceilometer",
  pwd: "$MONGODB_PASSWORD",
  roles: [ "readWrite", "dbAdmin" ]})'
EOF
    fn_exec_eval "bash -x _create_mongo_db"
    rm -f _create_mongo_db

    . $ADMINOPENRC
    fn_create_user_and_grant default:ceilometer:$CEILOMETER_PASSWORD service:admin
    fn_create_service_and_endpoint ceilometer:"OpenStack Telemetry Service":metering 3*http://$CONTROLLER_HOST_NAME:8777

    #for controller
    fn_exec_eval "yum install -y \
                    openstack-ceilometer-api \
                    openstack-ceilometer-collector \
                    openstack-ceilometer-notification \
                    openstack-ceilometer-central \
                    python-ceilometerclient"

    local DomProjInfo="project_domain_name=default;user_domain_name=default;project_name=service"
    local RabbitInfo="rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD"
    local MemAuthURL="auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357;memcached_servers=$CONTROLLER_HOST_NAME:11211"

    fn_check_file_and_backup "/etc/ceilometer/ceilometer.conf"
    fn_exec_openstack-config "
            database|connection=mongodb://ceilometer:$CEILOMETER_PASSWORD@$CONTROLLER_HOST_NAME:27017/ceilometer
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|$RabbitInfo
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|$MemAuthURL;$DomProjInfo
            keystone_authtoken|auth_type=password;username=ceilometer;password=$CEILOMETER_PASSWORD
            service_credentials|auth_type=password;auth_url=http://CONTROLLER_HOST_NAME:5000/v3;
            service_credentials|$DomProjInfo;region_name=$REGION_NAME;username=ceilometer;password=$CEILOMETER_PASSWORD;interface=internalURL"


    fn_exec_systemctl "openstack-ceilometer-api
                       openstack-ceilometer-notification
                       openstack-ceilometer-central
                       openstack-ceilometer-collector"


    #1. ���glance������[�˶��ڿ��ƽڵ���ִ��.]
    for conffile in "/etc/glance/glance-api.conf" "/etc/glance/glance-registry.conf"
    do
        fn_check_file_and_backup "$conffile"
        fn_exec_openstack-config "
                DEFAULT|rpc_backend=rabbit
                oslo_messaging_notifications|driver=messagingv2
                oslo_messaging_rabbit|$RabbitInfo"
        sleep 1
    done

    fn_exec_systemctl "openstack-glance-api openstack-glance-registry"

    #2. ��ÿ������ڵ���ִ�а�װCeilometer����Ϣ�ռ��ͻ��˴���.
	
    #3. �ڿ��ƺ�block�洢�ڵ�������Cinderʹ��ceilometer.
    fn_check_file_and_backup "/etc/cinder/cinder.conf"
    fn_exec_openstack-config "oslo_messaging_notificatons|driver=messagingv2"

    #�������ƽڵ��ϵ�Cinder����.
    fn_exec_systemctl "openstack-cinder-api openstack-cinder-scheduler"

    #����Block�洢�ڵ��ϵ�cinder����.
    #fn_exec_systemctl "openstack-cinder-volume"

    . $ADMINOPENRC
    #��service��Ŀ�´���һ����ɫ:ResellerAdmin
    #��ʽ: fn_create_domain_project_role DomName:DomDescription ProName:ProDescription:ProDom RoleName
    fn_create_domain_project_role none:none service:none:none ResellerAdmin
    #����ceilometer�û���Service��Ŀ�е��� ResellerAdmin �Ľ�ɫ.
    fn_create_user_and_grant none:ceilometer:none service:ResellerAdmin
	
	fn_create_tag_file "ceilometer_server"
	fn_inst_componet_complete_prompt "Install Ceilometer_service node Successed.@Controller Node."

}

os_fn_inst_alarm_server(){
    #����ceilometer�ļ�ر�������.
    fn_exec_eval "yum install python-ceilometermiddleware -y"

    fn_create_db aodh aodh
    
    . $ADMINOPENRC
    fn_create_user_and_grant default:aodh:$AODH_PASSWORD service:admin
    fn_create_service_and_endpoint aodh:"OpenStack Telemetry Service":alarming 3*http://$CONTROLLER_HOST_NAME:8042

    fn_exec_eval "yum install -y openstack-aodh-api \
                              openstack-aodh-evaluator \
                              openstack-aodh-notifier \
                              openstack-aodh-listener \
                              openstack-aodh-expirer \
                              python-ceilometerclient"

    local DomProjInfo="project_domain_name=default;user_domain_name=default;project_name=service"
    local RabbitInfo="rabbit_host=$CONTROLLER_HOST_NAME;rabbit_userid=$RABBITMQ_USERNAME;rabbit_password=$RABBITMQ_PASSWORD"
    local MemAuthURL="auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357;memcached_servers=$CONTROLLER_HOST_NAME:11211"

    fn_check_file_and_backup "/etc/aodh/aodh.conf"
    fn_exec_openstack-config "
            database|connection=mysql+pymysql://aodh:$AODH_PASSWORD@$CONTROLLER_HOST_NAME/aodh
            DEFAULT|rpc_backend=rabbit
            oslo_messaging_rabbit|$RabbitInfo
            DEFAULT|auth_strategy=keystone
            keystone_authtoken|$MemAuthURL;$DomProjInfo
            keystone_authtoken|auth_type=password;username=aodh;password=$AODH_PASSWORD
            service_credentials|auth_url=http://$CONTROLLER_HOST_NAME:5000/v2.0;$DomProjInfo
            service_credentials|auth_type=password;username=aodh;password=$AODH_PASSWORD
            service_credentials|interface=internalURL;region_name=$REGION_NAME"

    fn_exec_systemctl "openstack-aodh-api openstack-aodh-evaluator openstack-aodh-notifier openstack-aodh-listener"

    fn_exec_eval "ceilometer meter-list"

    local IMAGE_ID=$(glance image-list |awk '$2!~/^$|ID/{print $2}' |tail -1)
    fn_exec_eval "glance image-download $IMAGE_ID > /tmp/test.img"

    fn_exec_eval "ceilometer meter-list"
    fn_exec_eval "ceilometer statistics -m image.download -p 60"
    rm -f /tmp/test.img

    fn_create_tag_file "ceilometer_alarming"
    fn_inst_componet_complete_prompt "Install Ceilometer_alarming Sucessed.@Controller Node"
}


os_fn_inst_ceilometer
os_fn_inst_alarm_server
