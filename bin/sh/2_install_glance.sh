#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_glance(){
    #功能:安装glance

    #检查当前节点是否为Controller节点.
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller "

    fn_check_tag_file glance
    fn_warn_or_info_log "检测当前节点已安装: glance "
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "检测当前节点已安装: keystone "
    
    fn_exec_eval "yum install -y openstack-glance"

    fn_create_db glance glance
    
    . $ADMINOPENRC
    fn_create_user_and_grant default:glance:${GLANCE_PASSWORD} service:admin

    #默认服务区域是openstack.conf 中定义的: $REGION ,单独修改可单独指定: Region=RegionTwo... 
    fn_create_service_and_endpoint glance:"OpenStack Image Service":image 3*http://${CONTROLLER_HOST_NAME}:9292
    
    #备份并修改glance-api.conf
    fn_check_file_and_backup /etc/glance/glance-api.conf
    fn_exec_openstack-config "
        database|connection=mysql+pymysql://glance:${GLANCE_PASSWORD}@$CONTROLLER_HOST_NAME/glance
        keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
        keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
        keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service;
        keystone_authtoken|username=glance;password=${GLANCE_PASSWORD}
        paste_deploy|flavor=keystone
        glance_store|stores=file,http;default_store=file;filesystem_store_datadir=/var/lib/glance/images/"
        
    #备份并修改glance-registry.conf
    fn_check_file_and_backup /etc/glance/glance-registry.conf
    fn_exec_openstack-config "
        database|connection=mysql+pymysql://glance:${GLANCE_PASSWORD}@$CONTROLLER_HOST_NAME/glance
        keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
        keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
        keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service;
        keystone_authtoken|username=glance;password=${GLANCE_PASSWORD}
        paste_deploy|flavor=keystone"
    
    #同步glance数据库.    
    fn_exec_eval 'su -s /bin/sh -c "glance-manage db_sync" glance'
    fn_exec_sleep 5
	echo $SHOW_glance_TABLES
	fn_exec_eval "$SHOW_glance_TABLES"
	

    #设置开机自启动,并启动glance服务.
    fn_exec_systemctl "openstack-glance-api openstack-glance-registry"
    
    #导入VM的磁盘镜像.
    . $ADMINOPENRC
    local img imgfmt imgname imgpath imgpermission imgperm
    #IMG_LIST的格式: ImgName:ImgPath:[Public|Private]
    for img in ${IMG_LIST[*]}
    do
        imgfmt=qcow2
        imgname=${img%%:*}
        imgpath=`a=${img#*:}; echo ${a%:*}`
        imgpermission=${img##*:}
        [ "$imgpermission" == "Private" ] && imgperm= || imgperm="--public"

        fn_exec_eval "openstack image create \"$imgname\" --file $imgpath --disk-format $imgfmt --container-format bare $imgperm"
    done
    
    #测试
    #fn_exec_eval "openstack image list"
    fn_exec_eval "glance image-list"
    
    #创建安装完成的标志文件.
    fn_create_tag_file glance

    #安装glance完成提示.
    fn_inst_componet_complete_prompt "Install Glance Successed.@Controller Node"
}

os_fn_inst_glance
