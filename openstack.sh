#!/bin/bash


export ROOT_DIR=$PWD

# 导入函数集 和 安装环境变量.
export os_FUNCS=$ROOT_DIR/bin/function
export os_CONF_FILE=$ROOT_DIR/etc/openstack.conf
for f in $os_FUNCS $os_CONF_FILE
do
    if [ -s $f ]
    then
        . $f
    else
        echo -e "\e[31m Not Found $f.\e[0m"
        exit 1
    fi
done

if  [ "${USER}"  != "root" ]
then 
	echo -e "\033[41;37m you must execute this scritp by root. \033[0m"
	exit 1
fi

function fn_install_openstack_controller (){
    #功能: 安装OpenStack控制节点
    echo -e "\n\n\e[32m[ Install \e[31mController\e[0m \e[32mNode ]\e[0m\n\n"

    cat << EOF
    Prerequisite:
        0) Configure System Environment.
        1) Install Keystone.
        2) Install Glance.
        3) Install Nova-server.
        4) Install Neutron-server.
        5) Install Dashboard.
        6) Prepare Create VM Environment.
    Optional:
        7) Install Cinder-server.
        8) Install Manila.
        9) Install Ceilometer.
        10) Install Heat
        q) Quit
EOF

    local CtrlOpt=(nodeinit keystone glance nova neutron dashboard vm cinder manila ceilometer heat)
    local msg="Please inpute one number for install:" CH
    read -p "`echo -e "\e[32m$msg\e[0m"` " CH
    [ "$CH" == "q" -o "$CH" == "Q" ] && exit 0
    
    case $CH in
        0) bash $ROOT_DIR/bin/${CtrlOpt[$CH]} "controller_node" ;;
        1|2|3|4|5|6|7|8|9|10) bash $ROOT_DIR/bin/${CtrlOpt[$CH]} ;;
        q|Q) exit 0 ;;
        *) echo "Inpute Error,Retry input." ;;
    esac

    fn_install_openstack_controller
}

function fn_install_openstack_compute(){
    #功能: 安装OpenStack计算节点.
    
    echo -e "\n\n\e[32m[ Install \e[31mCompute\e[0m \e[32mNode ]\e[0m\n\n"

    local NodeInit=$ROOT_DIR/bin/nodeinit
    local ComputeNode=$ROOT_DIR/bin/compute_node
    [ -f $NodeInit ] || fn_err_log "Not Found $NodeInit."
    [ -f $ComputeNode ] && . $ComputeNode || fn_err_log "Not Found $ComputeNode"

    cat << EOF
    0) Configure System Environment.
    1) Install nova-compute and neutron-compute
    2) Install ceilometer-compute
    q) Quit
EOF

    local msg="Please inpute one number for install:" CH
    read -p "`echo -e "\e[32m$msg\e[0m"` " CH
    case $CH in
        0) bash $NodeInit "compute_node" ;;
        1) os_fn_inst_nova_compute; os_fn_inst_neutron_compute ;;
        2) os_fn_inst_ceilometer_compute ;;
        q|Q) exit 0 ;;
        *) echo "输入有误,请重新输入." ;;
    esac

    fn_install_openstack_compute
}

function fn_install_openstack_storage(){
    #功能: 安装OpenStack存储节点.

    echo -e "\n\n\e[32m[ Install \e[31mStorage\e[0m \e[32mNode ]\e[0m\n\n"

    local NodeInit=$ROOT_DIR/bin/nodeinit
    local StorageNode=$ROOT_DIR/bin/storage_node
    [ -f $NodeInit ] || fn_err_log "Not Found $NodeInit."
    [ -f $StorageNode ] && . $StorageNode || fn_err_log "Not Found $StorageNode"

    cat << EOF
    0) Configure System Environment.
    1) Install Cinder(Block) Service.
    2) Install Manila(Shared File System) Service.
    q) Quit
EOF

    local msg="Please inpute one number for install:" CH
    read -p "`echo -e "\e[32m$msg\e[0m"` " CH
    case $CH in
        0) bash $NodeInit "storage_node" ;;
        1) os_fn_inst_cinder_node ;;
        2) os_fn_inst_manila_node ;;
        q|Q) exit 0 ;;
        *) echo "输入有误,请重新输入." ;;
    esac

    fn_install_openstack_storage
}

function fn_install_openstack(){

    echo -e "\n\t\e[32m欢迎使用 WeZeStack 安装OpenStack "
    cat $ROOT_DIR/etc/logo.txt
    echo -e "\e[0m\n"

cat << EOF
0) Install Controller Node Service.
1) Install Computer Node Service.
2) Install Storage Node Service .
q) Quit
EOF
    local NodeOpt=(controller compute storage) CH
    read -p "please input one number for install :" CH
    case $CH in
        0|1|2) fn_install_openstack_${NodeOpt[$CH]} ;;
        q|Q) exit 0 ;;
        *) echo "Inpute Error,Retry input." ;;
    esac

    fn_install_openstack
}

fn_install_openstack
