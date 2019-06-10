#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_keystone(){
    #功能:安装Keystone

    #检查当前节点是否为Controller节点.
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller "

    fn_check_tag_file keystone
    fn_warn_or_info_log "检测当前节点已安装: keystone "
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install openstack-keystone httpd mod_wsgi memcached python-memcached -y"

    #格式: fn_create_db DB_Name DB_UserName [DB_Passwd]
    fn_create_db keystone keystone
    
    #修改keystone配置文件
    # 1.检测并备份 配置文件, 存在则导出存放配置文件位置的变量.
    local keystoneconf=/etc/keystone/keystone.conf
    fn_check_file_and_backup $keystoneconf
    
    # 2. 修改配置文件.
    local myconn=mysql+pymysql://keystone:${KEYSTONE_PASSWORD}@$CONTROLLER_HOST_NAME/keystone
    fn_exec_openstack-config "DEFAULT|admin_token=$ADMIN_TOKEN database|connection=$myconn token|provider=fernet"

    #导入Keystone 数据库.
    fn_exec_eval "su -s /bin/sh -c \"keystone-manage db_sync\" keystone"
    fn_exec_sleep 5
	echo $SHOW_keystone_TABLES
	fn_exec_eval "$SHOW_keystone_TABLES"
    
    #执行创建fernet key.
    cd /etc/keystone/
    fn_exec_eval "keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone"

    #修改httpd.conf 中的主机名.
    local httpdconf=/etc/httpd/conf/httpd.conf
    fn_check_file_and_backup $httpdconf
    fn_exec_eval "sed  -i  \"s/^#ServerName.*/ServerName ${CONTROLLER_HOST_NAME}/\" $httpdconf"
    
    #检测修改是否成功.
    grep -q "^ServerName ${CONTROLLER_HOST_NAME}$" $httpdconf
    fn_err_or_info_log "修改httpd.conf: ServerName ${CONTROLLER_HOST_NAME} "
    
    #修改keystone的http 配置文件. 
    local osHttpconf=$KEYSTONE_HTTPCONF_FILE
    local wsgi_keystone_conf=/etc/httpd/conf.d/wsgi-keystone.conf
    [ -f $wsgi_keystone_conf ] && cat $osHttpconf > $wsgi_keystone_conf || cp $osHttpconf $wsgi_keystone_conf
    fn_err_or_info_log "覆盖keystone安装的 wsgi-keystone.conf 为修改后的配置文件."
    
    #重启httpd 设置开机自启动
    fn_exec_systemctl "httpd"
    
    # ADMINTOKERC: 在安装配置文件 etc/openstack.conf 中定义.
    # source admin-token.sh
    source $ADMINTOKENRC

    #创建keystone服务 和 其访问点.
    #格式:fn_create_service_and_endpoint SrvName:SrvDescription:SrvType [(2|3)*]url [[(2|3)*]url]
    local url="2*http://$CONTROLLER_HOST_NAME:5000/v3 http://$CONTROLLER_HOST_NAME:35357/v3"
	fn_create_service_and_endpoint keystone:"OpenStack Identity":identity $url
	unset url

    #创建default域,admin项目,和admin角色.
    #fn_create_domain_project_role DomName:DomDescription ProName:ProDescription:ProDom RoleName
    fn_create_domain_project_role default:"Default Domain" admin:"Admin Project":default admin 

    #在default域中创建admin用户,并授权它在admin项目中担任admin角色.
    #fn_create_user_and_grant DomName:UserName:Passwd ProName:RoleName
    fn_create_user_and_grant default:admin:${ADMIN_PASSWD} admin:admin

    #在default域中创建service项目.
    fn_create_domain_project_role none:none service:"Service Project":default none

    #在default域中创建demo项目,并在demo项目中设置user角色.
    fn_create_domain_project_role none:none demo:"Demo Project":default user

    #在default域中创建demo用户,并授权它在demo项目中担任user角色.
    fn_create_user_and_grant default:demo:${DEMO_PASSWD} demo:user


    #删除token, 测试创建的用户名和密码是否可用.
	#注: 这里必须取消OS_TOKEN和OS_URL否则测试"openstack token issue"时,会出现以下错误:
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
    
    #测试创建的admin用户是否可通过非token方式认证.
    fn_exec_eval "openstack token issue"

    #创建tag标识文件.
    fn_create_tag_file keystone

    #提示安装服务完成.
    fn_inst_componet_complete_prompt "Install Keystone Sucessed.@Controller Node"
}

os_fn_inst_keystone
