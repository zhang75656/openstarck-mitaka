#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_glance(){
    #����:��װglance

    #��鵱ǰ�ڵ��Ƿ�ΪController�ڵ�.
    fn_check_tag_file controller_node
    fn_err_or_info_log "��⵱ǰ�ڵ���: controller "

    fn_check_tag_file glance
    fn_warn_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: glance "
    [ $? -eq 0 ] && return 1

    fn_check_tag_file keystone
    fn_err_or_info_log "��⵱ǰ�ڵ��Ѱ�װ: keystone "
    
    fn_exec_eval "yum install -y openstack-glance"

    fn_create_db glance glance
    
    . $ADMINOPENRC
    fn_create_user_and_grant default:glance:${GLANCE_PASSWORD} service:admin

    #Ĭ�Ϸ���������openstack.conf �ж����: $REGION ,�����޸Ŀɵ���ָ��: Region=RegionTwo... 
    fn_create_service_and_endpoint glance:"OpenStack Image Service":image 3*http://${CONTROLLER_HOST_NAME}:9292
    
    #���ݲ��޸�glance-api.conf
    fn_check_file_and_backup /etc/glance/glance-api.conf
    fn_exec_openstack-config "
        database|connection=mysql+pymysql://glance:${GLANCE_PASSWORD}@$CONTROLLER_HOST_NAME/glance
        keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
        keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
        keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service;
        keystone_authtoken|username=glance;password=${GLANCE_PASSWORD}
        paste_deploy|flavor=keystone
        glance_store|stores=file,http;default_store=file;filesystem_store_datadir=/var/lib/glance/images/"
        
    #���ݲ��޸�glance-registry.conf
    fn_check_file_and_backup /etc/glance/glance-registry.conf
    fn_exec_openstack-config "
        database|connection=mysql+pymysql://glance:${GLANCE_PASSWORD}@$CONTROLLER_HOST_NAME/glance
        keystone_authtoken|auth_uri=http://$CONTROLLER_HOST_NAME:5000;auth_url=http://$CONTROLLER_HOST_NAME:35357
        keystone_authtoken|memcached_servers=$CONTROLLER_HOST_NAME:11211;auth_type=password
        keystone_authtoken|project_domain_name=default;user_domain_name=default;project_name=service;
        keystone_authtoken|username=glance;password=${GLANCE_PASSWORD}
        paste_deploy|flavor=keystone"
    
    #ͬ��glance���ݿ�.    
    fn_exec_eval 'su -s /bin/sh -c "glance-manage db_sync" glance'
    fn_exec_sleep 5
	echo $SHOW_glance_TABLES
	fn_exec_eval "$SHOW_glance_TABLES"
	

    #���ÿ���������,������glance����.
    fn_exec_systemctl "openstack-glance-api openstack-glance-registry"
    
    #����VM�Ĵ��̾���.
    . $ADMINOPENRC
    local img imgfmt imgname imgpath imgpermission imgperm
    #IMG_LIST�ĸ�ʽ: ImgName:ImgPath:[Public|Private]
    for img in ${IMG_LIST[*]}
    do
        imgfmt=qcow2
        imgname=${img%%:*}
        imgpath=`a=${img#*:}; echo ${a%:*}`
        imgpermission=${img##*:}
        [ "$imgpermission" == "Private" ] && imgperm= || imgperm="--public"

        fn_exec_eval "openstack image create \"$imgname\" --file $imgpath --disk-format $imgfmt --container-format bare $imgperm"
    done
    
    #����
    #fn_exec_eval "openstack image list"
    fn_exec_eval "glance image-list"
    
    #������װ��ɵı�־�ļ�.
    fn_create_tag_file glance

    #��װglance�����ʾ.
    fn_inst_componet_complete_prompt "Install Glance Successed.@Controller Node"
}

os_fn_inst_glance
