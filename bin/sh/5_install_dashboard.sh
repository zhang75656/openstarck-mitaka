#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

os_fn_inst_dashboard(){
    #功能: 安装dashboard
    fn_check_tag_file controller_node
    fn_err_or_info_log "检测当前节点是: controller "
    
    fn_check_tag_file dashboard
    fn_warn_or_info_log "检测当前节点已安装: dashboard"                                                                                                                                      
    [ $? -eq 0 ] && return 1

    fn_check_tag_file nova_server
    fn_err_or_info_log "检测当前节点已安装: nova_server"                                                                                                                                      
         
    fn_exec_eval "yum install openstack-dashboard -y"
    
    local local_settings=/etc/openstack-dashboard/local_settings 
    fn_check_file_and_backup $local_settings

    fn_exec_eval "grep \"^SECRET_KEY.*=.*'$\" $local_settings > _tmp"
    fn_exec_eval "rm -f $local_settings && cp -a $DASHBOARD_CONF_FILE $local_settings"
    fn_exec_eval "sed -i \"s/^SECRET_KEY.*=.*'$/`cat _tmp`/\" $local_settings"
    fn_exec_eval "sed -i  \"s/controller/$CONTROLLER_HOST_NAME/g\"  $local_settings"
    rm -f _tmp

    fn_exec_systemctl "httpd memcached"

    fn_create_tag_file "dashboard"

    local msg="Install OpenStack Dashboard Successed.@Access Dashboard URL: http://$CONTROLLER_MANAGE_IP/dashboard/"
    fn_inst_componet_complete_prompt "$msg"
    unset msg
}

os_fn_inst_dashboard
