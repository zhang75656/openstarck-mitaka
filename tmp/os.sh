#!/bin/bash
#功能:
#   用来检查OpenStack服务是否都正常启动了,若启动失败,则尝试启动。

check_openstack_service(){
    systemctl is-enabled $1 &>/dev/null
    if [ $? -eq 0 ]
    then
        systemctl is-failed $1 &>/dev/null
        if [ $? -eq 0 ]
        then
            systemctl start $1
            systemctl is-failed $1 &>/dev/null
            [ $? -eq 0 ] && echo -e "\e[31mopenstack service: $1 start failed.\e[0m" |tee -a openstack-start.log
        else
            echo "openstack service: $1 start successed."
        fi
    fi
}

openstack_service(){
    systemctl $1 $2
    echo "OpenStack Service: $1 $2 successed."
    systemctl is-failed $1 &>/dev/null
    [ $? -eq 0 ] && echo -e "\e[31mopenstack service: $1 start failed.\e[0m" |tee -a openstack-start.log
}

keystone_svr_list=(
    httpd
    chronyd
    mariadb
    rabbitmq-server
    memcached
)
glance_svr_list=(
    openstack-glance-api
    openstack-glance-registry
)
nova_svr_list=(
    openstack-nova-api
    openstack-nova-cert
    openstack-nova-consoleauth
    openstack-nova-scheduler
    openstack-nova-conductor
    openstack-nova-novncproxy
)
neutron_svr_list=(
    neutron-server
    neutron-linuxbridge-agent
    neutron-dhcp-agent
    neutron-metadata-agent
    neutron-l3-agent
)

cinder_svr_list=(
    openstack-cinder-api
    openstack-cinder-scheduler
)
manila_svr_list=(
    openstack-manila-api
    openstack-manila-scheduler
)
ceilometer_svr_list=(
    mongod

    openstack-ceilometer-api
    openstack-ceilometer-notification
    openstack-ceilometer-central
    openstack-ceilometer-collector

    openstack-aodh-api
    openstack-aodh-evaluator
    openstack-aodh-notifier
    openstack-aodh-listener
)
heat_svr_list=(
    openstack-heat-api
    openstack-heat-api-cfn
    openstack-heat-engine
)

os_storageNode_svr_list=(
    lvm2-lvmetad
    openstack-cinder-volume
    target
    openstack-manila-share
)

os_computeNode_svr_list=(
    libvirtd
    openstack-nova-compute
    neutron-linuxbridge-agent
)
#openstack-ceilometer-compute

case $1 in
    storage)
        os_svr_list=(${os_storageNode_svr_list[*]})
        ;;
    compute)
        os_svr_list=(${os_computeNode_svr_list[*]})
        ;;
    compute_ceil)
        os_svr_list=(${os_computeNode_svr_list[*]} openstack-ceilometer-compute)
        ;;
    controller)
        svr1=(${keystone_svr_list[*]} ${glance_svr_list[*]} ${nova_svr_list[*]} ${neutron_svr_list[*]})
        svr2=(${cinder_svr_list[*]} ${manila_svr_list[*]} ${heat_svr_list[*]} ${ceilometer_svr_list[*]})
        os_svr_list=(${svr1[*]} ${svr2[*]})
        ;;
    primary)
        os_svr_list=(${keystone_svr_list[*]} ${glance_svr_list[*]} ${nova_svr_list[*]} ${neutron_svr_list[*]})
        ;;
    noprimary)
        os_svr_list=(${cinder_svr_list[*]} ${manila_svr_list[*]} ${heat_svr_list[*]} ${ceilometer_svr_list[*]})
        ;;
    keystone)
        os_svr_list=(${keystone_svr_list[*]})
        ;;
    glance)
        os_svr_list=(${glance_svr_list[*]})
        ;;
    nova)
        os_svr_list=(${nova_svr_list[*]})
        ;;
    neutron)
        os_svr_list=(${neutron_svr_list[*]})
        ;;
    cinder)
        os_svr_list=(${cinder_svr_list[*]})
        ;;
    manila)
        os_svr_list=(${manila_svr_list[*]})
        ;;
    ceilometer)
        os_svr_list=(${ceilometer_svr_list[*]})
        ;;
    heat)
        os_svr_list=(${heat_svr_list[*]})
        ;;
    *)
        echo "Usage: $0 <primary|noprimary|keystone|glance|nova|neutron|cinder|manila|ceilometer|heat|storage|controller|compute|compute_ceil> <start|stop|restart|check>"
        exit 1
        ;;
esac

case $2 in
    start|restart|stop)
        for svr in ${os_svr_list[*]}
        do
            openstack_service $2 $svr
        done
        ;;
    check)
        for svr in ${os_svr_list[*]}
        do
            check_openstack_service $svr
        done
        ;;
    *)
        echo "Usage: $0 <primary|noprimary|keystone|glance|nova|neutron|cinder|manila|ceilometer|heat|storage|controller|compute|compute_ceil> <start|stop|restart|check>"
        exit 1
        ;;
esac


