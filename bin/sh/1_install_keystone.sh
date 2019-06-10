#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_keystone(){
    #����:��װKeystone

    #��鵱ǰ�ڵ��Ƿ�ΪController�ڵ�.
    fn_check_tag_file controller_node
    fn_err_or_info_log "��⵱ǰ�ڵ���: controller "

    fn_check_tag_file keystone
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: keystone "
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install openstack-keystone httpd mod_wsgi memcached python-memcached -y"

    #��ʽ: fn_create_db DB_Name DB_UserName [DB_Passwd]
    fn_create_db keystone keystone
    
    #�޸�keystone�����ļ�
    # 1.��Ⲣ���� �����ļ�, �����򵼳���������ļ�λ�õı���.
    local keystoneconf=/etc/keystone/keystone.conf
    fn_check_file_and_backup $keystoneconf
    
    # 2. �޸������ļ�.
    local myconn=mysql+pymysql://keystone:${KEYSTONE_PASSWORD}@$CONTROLLER_HOST_NAME/keystone
    fn_exec_openstack-config "DEFAULT|admin_token=$ADMIN_TOKEN database|connection=$myconn token|provider=fernet"

    #����Keystone ���ݿ�.
    fn_exec_eval "su -s /bin/sh -c \"keystone-manage db_sync\" keystone"
    fn_exec_sleep 5
	echo $SHOW_keystone_TABLES
	fn_exec_eval "$SHOW_keystone_TABLES"
    
    #ִ�д���fernet key.
    cd /etc/keystone/
    fn_exec_eval "keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone"

    #�޸�httpd.conf �е�������.
    local httpdconf=/etc/httpd/conf/httpd.conf
    fn_check_file_and_backup $httpdconf
    fn_exec_eval "sed  -i  \"s/^#ServerName.*/ServerName ${CONTROLLER_HOST_NAME}/\" $httpdconf"
    
    #����޸��Ƿ�ɹ�.
    grep -q "^ServerName ${CONTROLLER_HOST_NAME}$" $httpdconf
    fn_err_or_info_log "�޸�httpd.conf: ServerName ${CONTROLLER_HOST_NAME} "
    
    #�޸�keystone��http �����ļ�. 
    local osHttpconf=$KEYSTONE_HTTPCONF_FILE
    local wsgi_keystone_conf=/etc/httpd/conf.d/wsgi-keystone.conf
    [ -f $wsgi_keystone_conf ] && cat $osHttpconf > $wsgi_keystone_conf || cp $osHttpconf $wsgi_keystone_conf
    fn_err_or_info_log "����keystone��װ�� wsgi-keystone.conf Ϊ�޸ĺ�������ļ�."
    
    #����httpd ���ÿ���������
    fn_exec_systemctl "httpd"
    
    # ADMINTOKERC: �ڰ�װ�����ļ� etc/openstack.conf �ж���.
    # source admin-token.sh
    source $ADMINTOKENRC

    #����keystone���� �� ����ʵ�.
    #��ʽ:fn_create_service_and_endpoint SrvName:SrvDescription:SrvType [(2|3)*]url [[(2|3)*]url]
    local url="2*http://$CONTROLLER_HOST_NAME:5000/v3 http://$CONTROLLER_HOST_NAME:35357/v3"
	fn_create_service_and_endpoint keystone:"OpenStack Identity":identity $url
	unset url

    #����default��,admin��Ŀ,��admin��ɫ.
    #fn_create_domain_project_role DomName:DomDescription ProName:ProDescription:ProDom RoleName
    fn_create_domain_project_role default:"Default Domain" admin:"Admin Project":default admin 

    #��default���д���admin�û�,����Ȩ����admin��Ŀ�е���admin��ɫ.
    #fn_create_user_and_grant DomName:UserName:Passwd ProName:RoleName
    fn_create_user_and_grant default:admin:${ADMIN_PASSWD} admin:admin

    #��default���д���service��Ŀ.
    fn_create_domain_project_role none:none service:"Service Project":default none

    #��default���д���demo��Ŀ,����demo��Ŀ������user��ɫ.
    fn_create_domain_project_role none:none demo:"Demo Project":default user

    #��default���д���demo�û�,����Ȩ����demo��Ŀ�е���user��ɫ.
    fn_create_user_and_grant default:demo:${DEMO_PASSWD} demo:user


    #ɾ��token, ���Դ������û����������Ƿ����.
	#ע: �������ȡ��OS_TOKEN��OS_URL�������"openstack token issue"ʱ,��������´���:
	#	 'NoneType' object has no attribute 'service_catalog'
    unset OS_TOKEN OS_URL 
    
    fn_exec_eval "openstack --os-auth-url http://$CONTROLLER_HOST_NAME:35357/v3 \
            --os-project-domain-name default \
            --os-user-domain-name default \
            --os-project-name admin \
            --os-username admin --os-password ${ADMIN_PASSWD} \
            token issue"

    fn_exec_eval "openstack --os-auth-url http://$CONTROLLER_HOST_NAME:5000/v3 \
            --os-project-domain-name default \
            --os-user-domain-name default \
            --os-project-name demo \
            --os-username demo --os-password ${DEMO_PASSWD} \
            token issue"

    #source admin-openrc.sh
    . $ADMINOPENRC
    
    #���Դ�����admin�û��Ƿ��ͨ����token��ʽ��֤.
    fn_exec_eval "openstack token issue"

    #����tag��ʶ�ļ�.
    fn_create_tag_file keystone

    #��ʾ��װ�������.
    fn_inst_componet_complete_prompt "Install Keystone Sucessed.@Controller Node"
}

os_fn_inst_keystone
