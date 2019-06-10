#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

fn_import_os_file(){
    #����:���ǿ��ƽڵ����Ƿ���������ļ�"os",���������롣
    #     �˺���,ͨ���������ڵ�,�洢�ڵ��ϵ������ӿ���.
    #     ����ȡ����IP,�ͳ�������.
    # 
    #ע:
    #    ����os�ļ�: 
    #    echo "�����ӿ���" > ~/os
    #
    #��ע:
    #   �˺���,����fn_init_node_env�����е���;���ú����ļ���ǰ����:
    #   ����ڵ�ʹ洢�ڵ��Ѿ���ȷ��������������/etc/hosts.
    #   ����,��ȡ����Ϣ���Ǵ����.


    local osfile=/root/os
    if [ -s "$osfile" ]
    then
        PublicNetNIC=`cat $osfile`
        if [ -n "$PublicNetNIC" ]
        then
            SLAVE_NODE_PUBLIC_NET_NIC=$PublicNetNIC
        else
            fn_err_log "���ṩ�� $osfile Ϊ��."
        fi
    else
        local IFN_UserCh IFNAMES CH msg 
        IFN_UserCh=(`ifconfig |grep -B1 "\<inet\>" |awk -F: '/flags/{if($1!="lo"){print $1}}' |nl -n ln -v 0`)
        IFNAMES=(`ifconfig |grep -B1 "\<inet\>" |awk -F: '/flags/{if($1!="lo"){print $1}}'`)
        local msg="��ѡ�������ӿڵı������[${IFN_UserCh[*]}]:"
        read -p "`echo -e "\e[32m$msg\e[0m"`" CH
        if [ -z "${IFNAMES[$CH]}" ]
        then 
            fn_warn_log "����������,��ȷ�Ϻ�,�ٴβ���." 
            fn_import_os_file
        else
            SLAVE_NODE_PUBLIC_NET_NIC=${IFNAMES[$CH]}
        fi
    fi 

    local CONF=$SLAVE_NODE_CONF
    echo "export SLAVE_NODE_PUBLIC_NET_NIC=$SLAVE_NODE_PUBLIC_NET_NIC" > $CONF
    echo "export SLAVE_NODE_PUBLIC_NET_IP=`LANG=C nmcli dev show $SLAVE_NODE_PUBLIC_NET_NIC |awk '/IP4.ADDRESS\[1\]/{print $2}'`" >> $CONF
    echo "export SLAVE_NODE_PUBLIC_NET_GW=`LANG=C nmcli dev show $SLAVE_NODE_PUBLIC_NET_NIC |awk '/IP4.GATEWAY/{print $2}'`" >> $CONF
    echo "export SLAVE_NODE_HOST_NAME=`hostname`" >> $CONF 
    echo "export SLAVE_NODE_MANAGE_IP=`hostname -i`" >> $CONF 

    cat $CONF
    #����ӽڵ�������ļ�
    . $CONF
}

#----------------------------[ϵͳ���]---------------------------------#

fn_check_os_version(){
    #����: ���ϵͳ�����Ƿ��ʺϰ�װOpenStack-Mitaka��.
    #   1.���/etc/centos-release �� /etc/redhat-release
    #     �������ļ������ڻ��ȡʧ��,����:
    #     a. �鿴/proc/version, Kernel������:3.10.0-327.x86_64
    #     b. �鿴python -V, python�汾������: 2.7.5
    
    local OS_Ver
    #/etc/centos-release: "CentOS Linux release 7.2.1511 (Core)"
    for f in /etc/centos-release /etc/system-release /etc/redhat-release;do
        [ -f $f ] && OS_Ver=$(cat $f |awk '{print $1$4}') || OS_Ver=
        [ -n $OS_Ver ] && break
    done
    if [ -n "$OS_Ver" ]
    then
        if [ "${OS_Ver}x" == "CentOS7.2.1511x" ] || [ "${OS_Ver}x" == "Redhat7.2.1511x" ]
        then
             fn_info_log "��ǰϵͳ: $OS_Ver ,����Ҫ��."
             return 0
        fi
    fi

    local OS=`uname -s`
    local OS_Arch=`uname -m`
    #OS_Kernel_Ver=3.10.0-327
    local OS_Kernel_Ver=`a=$(uname -r); b=${a%.*}; echo ${b%.*}` 
    local Python_Ver=`python -V 2>&1 |awk '{print $2}'`
    if [ "$OS" == "Linux" -a "$OS_Arch" == "x86_64" ]
    then
        local OS_Major_Kernel_Ver=${OS_Kernel_Ver%-*}
        local OS_Kernel_RevisionNumber=${OS_Kernel_Ver#*-}
        local Python_Major_Ver=${Python_Ver%.*}
        local Python_RevisionNumber=${Python_Ver##*.}
        if  [ "$OS_Major_Kernel_Ver" == "3.10.0" ] && [ $OS_Kernel_RevisionNumber -ge 327 ] && \
            [ "$Python_Major_Ver" == "2.7" ] && [ $Python_RevisionNumber -ge 5 ]
        then
            fn_info_log "����ϵͳΪ: $OS-$OS_Kernel_Ver-$OS_Arch , Python-$Python_Ver ����CentOS7.2-1511�Ļ�������."
            return 0 
        else
            local os="$OS-$OS_Kernel_Ver-$OS_Arch"
            local base="Kernel-3.10.0-327 �� Python-2.7.5"
            fn_err_log "����ϵͳΪ: $os , Python-$Python_Ver ������ $base �Ļ���Ҫ��."
            exit 0
        fi
    fi
}

fn_check_os_resource(){
    #����:���ϵͳ��Դ�Ƿ����Mitaka��Ҫ��.
    #   M��Ҫ��: Controller Node: RAM=4G, DISK=5G, NIC=2
    #            Computer Node: RAM=2G,DISK=5G, NIC=2

    #���ڴ��С��������
    local RAM_TotalSize=$(cat /proc/meminfo |awk '/MemTotal/{print int($2/1024/1024+0.5)}')
    local DISK_AvailableSize=$(df -h / |awk '/G/{printf("%d",$4)}')

    #eno1401021: en:EtherNet,o:Onboard(����),1401021:�豸������(domain=0014,pci=01,dev=02,function=1).
    #ens1402010: s:slot(�Ȳ�β�)
    #enp2sxxxxx: p:PCI,s:slot:�������PCI��USB�豸������.
    #enx78e7d1ea46da: enx:(�����), 78e7d1ea46da:��MAC��ַ.
    #
    local NIC_Num=$(nmcli dev |awk '/en[ospx]|eth[0-9]/{n++}END{print n}')
    local ramsize msg

    compare_chk(){
        msg="��ϵͳ���ڴ�:${RAM_TotalSize}G Ҫ��:${1}G,����:${DISK_AvailableSize}G Ҫ��:5G,����:${NIC_Num}�� Ҫ��:2��"
        if [ $RAM_TotalSize -ge $1 ] && [ $DISK_AvailableSize -ge 5 ] && \
           [ $NIC_Num -ge 2 ]
        then
            msg="${msg} ���ϰ�װOpenStack-Mitaka�����ϵͳ��ԴҪ��."
            fn_info_log "$msg"
        else
            msg="${msg} �����ϰ�װOpenStack-Mitaka�����ϵͳ��ԴҪ��."
            fn_err_log "$msg"
        fi
    }
    
    fn_check_tag_file controller_node
    if [ $? -eq 0 ]
    then
        ramsize=4
        compare_chk $ramsize
    else
        ramsize=2
        compare_chk $ramsize
    fi
}

fn_check_os_lang_and_soft(){
    #����: ���ϵͳ�����Ƿ�������ű������־.
    #   1.�˽ű�����������־,����:export LANG=zh_CN
    #   2. ���ű���Ҫ�õ����:
    #       curl,
    #       openstack-utils(openstack-config),
    #       python-openstackclient(openstack)
    #       openstack-selinux
    #       chrony
    #       ntpdate
    #       yum-plugin-priorities
    #       sysfsutils

    local Lang=zh_CN
    [ "$LANG" == "$Lang" ] || export LANG="$Lang"

    #�����������
    local softlist=/tmp/softlist.txt

    rpms=(
        curl
        openstack-utils
        python-openstackclient
        openstack-selinux
        chrony
        ntpdate
        yum-plugin-priorities
        sysfsutils
    )

    [ "$G_PROXY" == "True" ] && . $PROXY_CONF_FILE
    [ -f "$softlist" ] && rm -f $softlist
    for rpm in ${rpms[*]}
    do
        fn_exec_eval -w "rpm -q $rpm &>/dev/null"
        if [ $? -eq 0 ] 
        then
            fn_info_log "$rpm �Ѿ���װ." 
        else
            echo $rpm >> $softlist
            fn_warn_log "$rpm ���δ��װ,\e[32m�Ѽ��밲װ�ƻ��б�($softlist)\e[0m."
        fi
    done
}

fn_check_os_net(){
    #����:���ϵͳ�Ƿ�����������Internet.
    #   1. �������,��ͨ:0.������; 1.ping ����DNS; 2.curl baidu.com;

    #�������
    #����Ƿ�ΪDHCP����IP
    local connName
    fn_check_tag_file "controller_node"
    if [ $? -eq 0 ]
    then
        PubNetifname=$CONTROLLER_PUBLIC_NET_NIC
        PubNetIP=$CONTROLLER_PUBLIC_NET_IP
    else
        PubNetifname=$SLAVE_NODE_PUBLIC_NET_NIC
        PubNetIP=$SLAVE_NODE_PUBLIC_NET_IP
    fi
    PubNetGW=$PUBLIC_NET_GW
    
    chk_dhcp(){
        #����:��������ļ���ָ�������ӿ��ϵ�IP�Ƿ�ΪDHCP����,
        #    ����,1.��������ļ��Ƿ����˸ýӿڵĹ̶�IP,�����޸�Ϊ�˹̶�IP.
        #         2.��û�ж���̶�IP,����ʾ��DHCP�����IP�޸�Ϊ�˽ӿڹ̶�IP.
        #    ����,����0,���ӿ�Ϊ�̶�IP.
        #ע:
        #   �����˽�й���IP,����Ϊ���������ӿ�һ��ΪDHCP����IP,˽�й���IP,
        #   һ��Ϊ�ֶ�����.�����ڲ��Ի�������.

        #��ȡ��ǰ�ڵ������Ľӿ��� �� ������IP.
        #��ȡ�����ļ���export������'�ڵ�����'�еı�����ǰ׺.
        #local vnames="(COMPUTE|NEUTRON|STORAGE)[[:digit:]]{1,}"
        #local cns="CONTROLLER `env |grep -Eo "$vnames" |sort |uniq`"
        #
        ##ͨ����Щ��ʶ��ͬ�ڵ�ı�ʶǰ׺,��ȷ����ǰӦ��ʹ�����鹫��IP�ͽӿ�.
        #local var varName
        #for var in $cns
        #do
        #    varName=`env|grep "$HOST_NAME" |grep "${var}_HOST_NAME" |awk -F= '{print $1}'`
        #    [ -n "$varName" ] && break
        #done

        #local PubNetifname=$(eval echo $`echo ${varName/_HOST_NAME/_PUBLIC_NET_NIC}`)
        #local PubNetIP=$(eval echo $`echo ${varName/_HOST_NAME/_PUBLIC_IP}`)
        #local PubNetGW=$PUBLIC_NET_GW

        local ipMethod
        connName=`nmcli -t -f device,connection dev |grep "$PubNetifname" |awk -F: '{print $2}'`
        [ "$connName" == "--" ] || ipMethod=`nmcli conn show $connName |awk '/ipv4.method/{print $2}'`
        if [ "$ipMethod" == "auto" ]
        then
        #    local ip4=`LANG=en_US nmcli conn show $connName |awk '/IP4.ADDRESS/{print $2}'`
        #    #�Աȵ�ǰ�����ӿ�IP �� �����ļ�:openstack.conf �ж���������ӿ�IP�Ƿ�һ��.
        #    if [ -n "$PubNetIP" -a -n "$PubNetGW" ]
        #    then
        #        fn_exec_eval "$cmd $PubNetIP ipv4.method manual ipv4.gateway $PubNetGW && nmcli conn up $connName"
        #        fn_info_log "\e[;41m �޸������ӿ�:$PubNetifname ��IP($ip4)Ϊ�����ļ���ָ���Ĺ̶�IP($PubNetIP)"
        #        return 0
        #    fi

            local cmd="nmcli conn down $connName && nmcli conn modify $connName ipv4.addresses"
            if [ -n "$PubNetIP" -a -n "$PubNetGW" ]
            then
                local msg="���ֽӿ�:$PubNetifname �Ļ����:$connName ��IP:($PubNetIP)ΪDHCP�Զ�����,���޸�Ϊ�̶�IP,"
                msg="$msg\n����IP�ı佫����OpenStack����������.(y=ʹ��$PubNetIP,n=�˳�,�ֶ��޸�.)[y|n]:"
                local YN
                read -p "`echo -e "\e[31m$msg\e[0m"`" YN
                if [ "$YN" == "y" -o "$YN" == "Y" ]
                then
                    fn_exec_eval "$cmd $PubNetIP ipv4.method manual ipv4.gateway $PubNetGW && nmcli conn up $connName"
                    unset cmd
                    return 0
                else
                    exit 1
                fi
            fi
        fi
    }


    #���ֱ������
    chk_direct_net(){
        #���ڴ�����ʧ�ܺ�,�����˼��.
        #   1.���ӿ�IP�Ƿ�Ϊ�̶�IP.
        #   2.����Ƿ��ֱ������,
        #     ��: ����0
        #     ��: ����1

        chk_dhcp
        local RetVal
        ping -c 2 114.114.114.114 &>/dev/null; RetVal=$?
        ping -c 2 8.8.8.8 &>/dev/null; RetVal=$(($RetVal+$?))
        if [ $RetVal -eq 0 ]
        then
            curl www.baidu.com &>/dev/null
            if [ $? -eq 0 ]
            then
                fn_info_log "������ֱ�ӷ��ʻ�����,���������"
                return 0
            else
                local cmd="nmcli conn modify $connName ipv4.dns ${PUBLIC_NET_DNS};"
                cmd="$cmd nmcli conn down $connName && nmcli conn up $connName"
                local msg="ִ������: $cmd ���DNS."
                eval "$cmd"
                unset cmd
                if [ $? -eq 0 ]
                then
                    fn_warn_log "$msg �ɹ�.��ʹ�ù���yumԴ."
                    return 0
                else 
                    fn_warn_log "$msg ʧ��,��ʹ�ñ���yumԴ."
                    return 1
                fi
            fi
        else
            ifconfig |grep -q "\<${PubNetIP%/*}\>" 
            if [ $? -ne 0 ]
            then
                fn_exec_eval "nmcli conn add con-name os-ex-net type ethernet ifname $PubNetifname ip4 $PubNetIP gw4 $PubNetGW"
                fn_exec_eval "nmcli conn modify os-ex-net ipv4.dns $PUBLIC_NET_DNS"
                if [ $? -eq 0 ]
                then
                    curl www.baidu.com &>/dev/null
                    if [ $? -eq 0 ]
                    then
                        fn_info_log "���ֱ��Internet�ɹ�,��ʹ��Internet yumԴ."
                        return 0
                    else
                        fn_warn_log "���ֱ��Internetʧ��,��ʹ�ñ���yumԴ."
                        return 1
                    fi
                fi
            fi

            fn_warn_log "���ֱ��Internetʧ��,��ʹ�ñ���yumԴ."
            return 1
        fi
    }
    #����������.
    if [ "$G_PROXY" == "True" -a -f "$PROXY_CONF_FILE" -a `grep -v '^#' "$PROXY_CONF_FILE" |wc -l` -ge 1 ]
    then
         . "$PROXY_CONF_FILE"
         local Proxy="$http_proxy $https_proxy $ftp_proxy"
         curl www.baidu.com &>/dev/null
         if [ $? -eq 0 ]
         then
            fn_info_log "����������óɹ�,��ʹ��: $Proxy ������."
            return 0
         fi
    fi

    fn_warn_log "������� $Proxy ������,���� curl www.baidu.com ʧ��"
    chk_direct_net
    return $?
}

fn_check_yum(){
    #����:������ʹ�ñ���Դ����Դ.
    
    local cmd=
    local YumHome=/etc/yum.repos.d
    local YumTmp=$YumHome/tmp
    mvrepo(){
        if [ -d $YumTmp ]
        then
            fn_exec_eval "mv $YumHome/*.repo $YumTmp"
        else
            fn_exec_eval "mkdir $YumTmp && mv $YumHome/*.repo $YumTmp"
        fi
    }
    ls -1 $YumHome |grep -q "\.repo" && mvrepo

    inst_local_yum(){
        local repofile=$YumHome/`basename $LOCAL_YUM_FILE`
        cmd="cp -a $LOCAL_YUM_FILE $repofile &&"
        cmd="$cmd sed -i 's|<HostName>|$CONTROLLER_HOST_NAME|' $repofile"
        fn_exec_eval "$cmd" "����yum�����ļ�."
        fn_exec_eval "yum clean all && yum repolist"
    }
    
    fn_check_os_net
    if [ $? -eq 0 ]
    then
        cmd="cp -a $INTERNET_YUM_FILE $YumHome;"
        cmd="$cmd cp -a $INTERNET_YUM_KEYS_DIR/* /etc/pki/rpm-gpg/"
        fn_exec_eval "$cmd"
        local msg="\e[;41mʹ��Internet yumԴ,�����밲װ"yum-plugin-priorities",������Դ�����ȼ�,"
        msg="$msg ������Ϊ,epelԴ,�����ṩ�˱�openstackԴ���µİ�,����ܵ���openstack����,"
        msg="$msg �޷�Ԥ�ϵĴ���."
        fn_warn_log "$msg"
    else
        fn_check_tag_file "compute_node"; compute=$?
        fn_check_tag_file "storage_node"; storage=$?
        if [ $storage -eq 0 -o $compute -eq 0 ]
        then
            inst_local_yum
            return 0 
        fi
        
        if [ -f $CENTOS72_LOCAL_YUM_SOURCE ]
        then
            local LocalSourceDir=/var/www/html/openstack-mitaka/
            [ -d $LocalSourceDir ] || mkdir -p $LocalSourceDir
            cmd="tar xf $CENTOS72_LOCAL_YUM_SOURCE -C $LocalSourceDir;"
            fn_info_log "��ʼ��������yumԴ: $cmd"
            fn_exec_eval "$cmd" "����yumԴ�ļ�."

            fn_exec_systemctl "httpd"
            fn_info_log "$cmd ʹ��httpd��������yumԴ"
            
            inst_local_yum
            unset cmd
        else
            fn_err_log "û���ҵ�����yumԴ�ļ���: $CENTOS72_LOCAL_YUM_SOURCE"
        fi
    fi
}

#fn_set_hostname_and_import_hosts(){
#    #����: ���ò����������,������hosts�ļ�.
#    #
#    #   ע:ʹ�ô˺��������ڵ���ʱ��HOST_NAME��ֵ.
#
#    if [ -z "$HOST_NAME" ]
#    then
#        fn_err_log "���ṩ�ڵ�������:export HOST_NAME=������"
#    else
#        fn_exec_eval "hostnamectl set-hostname ${HOST_NAME}"
#    fi
#
#    if [ -s $HOSTS_FILE ]
#    then
#        fn_exec_eval "cat $HOSTS_FILE >> /etc/hosts"
#    else
#       fn_err_log "���ṩ $HOSTS_FILE ,�Ա㱣֤���ڵ�����������������."
#
#       # fn_warn_log "$HOSTS_FILE ������,���Զ������������IP��ַӳ��."
#       # cmd=
#       # local hosts=/etc/hosts
#       # local vnames="(COMPUTE|NEUTRON|STORAGE)[[:digit:]]{1,}"
#       # local cns="CONTROLLER `env |grep -Eo "$vnames" |sort |uniq`"
#       # echo cns=$cns
#       # local v vh vi vhn vin i err
#       # for v in $cns
#       # do
#       #     vhn=${v}_HOST_NAME
#       #     vin=${v}_MANAGE_IP
#       #     vh=$(eval echo $`echo ${vhn}`)
#       #     vi=$(eval echo $`echo ${vin}`)
#       #     if [ -n "$vh" -a -n "$vi" ]
#       #     then
#       #         cmd="$cmd echo $vi  $vh >> $hosts;"
#       #     else
#       #         err="$err $vhn=$vh : $vin=$vi ȱ��ӳ���ϵ.��������hosts.\n"
#       #     fi
#       # done
#       # fn_exec_eval "$cmd"
#       # [ -n "$err" ] && fn_warn_log "$err"
#    fi
#
#    ping -c 2 $HOST_NAME &>/dev/null && RetVal1=$?
#    ping -c 2 `hostname -i` &>/dev/null && RetVal2=$?
#    [ $RetVal1 -eq 0 -a $RetVal2 -eq 0 ] && \
#                    fn_info_log "���ò�������������" || \
#                    fn_err_log "��������IPӳ��ʧ��,����������ʧ��."
#}

fn_add_fw_rich_rules(){
    #����:���firewall ���ʹ���.
    #     ��Controller Node�ϵ�OpenStack�����ڲ��ڵ㿪��.
    
    #firewallĬ���û��Զ�������Ŀ¼
    local FW_SERVICE_DIR=/etc/firewalld/services

    #firewallĬ�������Ŀ¼
    local FW_DEFAULT_ZONE_DIR=/etc/firewalld/zones

    #Ĭ��public����ĸ����������ļ�
    local FW_PUBLIC_ZONE_XML=$FIREWALL_CONF_DIR/public.xml

    #����OpenStack������������κ�
    local IP_NET=$CONTROLLER_MANAGE_NET

    #local DefaultZone=`firewall-cmd --get-default-zone`
    #if [ "$DefaultZone" == "public" ]
    #then
    #    if [ -f $FW_PUBLIC_ZONE_XML ]
    #    then
    #        local f=$FW_DEFAULT_ZONE_DIR/public.xml
    #        cat $FW_PUBLIC_ZONE_XML > $f
    #        sed -i "s,<IntNet>,$IP_NET,g" $f
    #        fn_err_or_info_log "��firewallĬ������(public)���븻����"

            #��ȫ����firewall(����ʧ��ǰ�ѽ������ӵ�firewall״̬��Ϣ),ʹ������ӵĹ�����Ч.
    #        fn_exec_eval "firewall-cmd --reload"
    #        return 0
    #    fi
    #fi

    add_ipv4_rule(){
        if [ -z "$IP" ]
        then
            if [ -z "$2" ]
            then
                fn_err_log "�����ṩOpenStack�������������IP(��ʽ:192.168.10.0/24)."
            else
                IP=$2
            fi
        fi

        #���OpenStack����Ĭ��firewall�����Ŀ¼.
        local SVRXmlFile=$FIREWALL_CONF_DIR/${1}.xml
        [ -f "$SVRXmlFile" ] && cp $SVRXmlFile $FW_SERVICE_DIR

        local Rule="rule family='ipv4' source address='$IP' service name='$1' log prefix="$1" level='info' accept"
        fn_exec_eval "firewall-cmd --permanent --add-rich-rule=\"$Rule\"" "�������ǽ����"
    }
    
    IP=${IP_NET}
    os_svr_list=(
        http
        ntp
		os_otv
        os_vncproxy
        os_mariadb
        os_mongodb
        os_rabbitmq
        os_memcached
        os_keystone
        os_glance
        os_nova
        os_neutron
        os_cinder
        os_manila
        os_ceilometer
        os_alarming
        os_heat
    )
    fn_check_tag_file "controller_node"
    if [ $? -eq 0 ]
    then 
        for svr in ${os_svr_list[*]}
        do
            add_ipv4_rule "$svr"
        done
    fi

    #ע:
    #  firewallĬ�ϵ�vnc-serverֻ������5900-5903���4��VNC�˿�.
    fn_check_tag_file "compute_node" 
    if [ $? -eq 0 ]
    then 
        add_ipv4_rule "vnc-server" 
        #OTV:��VxLAN����,���Ƕ��Ǵ���㼼��,���ǽ�����֡��װ��IP����,ʵ�ֿ��������ĵĶ��㻥��.
        #����OTV��Cisco��˽��Э��,VxLAN��Cisco/VMware���������Ķ��㼼��,Ŀǰ���ύ��IETF��Ϊ�ݰ�,
        #֧���ڶ೧��,��OpenStack-MitakaĬ��û��ʹ��VxLAN,��������OTV������VxLAN.Ϊ�����,�������.
        #ע:  ����OTVͨ�Ŷ˿�,��Ϊ����������VM���Ի�ȡDHCP�����IP,��ΪVM��ȡIP����������:
        # VM[eth0]-----(tap0)[Intbr]������(ComputeNode)[Intbr](vxlan-XX)---(vxlan-XX)[Intbr]���ƽڵ�[Intbr](tap)----(qdhcp-xxxx)NetNS
        # VM�����ComputeNode����һ̨����,VM�����ı���,����ComputeNode�ϵ�firewalld��˵�ǽ���������,
        # ��˲�INPUT��,������˵������,VM�����ı��ĵ���Intbrʱ,��û�з�װOTV��,��OTV�ӿڽ��յ�����ʱ,
        # ��Ϊ����Ҫȥ��Զ����OTV�ĶԶ�,���OTV���װ��,��װ��ɺ�,���IP��PORT�Ǽ���ڵ������ƽڵ�
        # ����OTV�����IP(һ��Ϊ����IP,�˽ű���װ��Ҳ�ǹ���IP)��OTV��UDP�˿ں�,��ʱfirewalld����INPUT
        # ������ʱ,ƥ��������IP�Ͷ˿�,��û�з���,�ͻᵼ�¶���.  ���ƽڵ�͸�����˵��,���ⲿ��������
        # ���һ����INPUT��,��ȻҲҪ���С�
        add_ipv4_rule "os_otv"

        #��ʱ�Ľ������IP�ķ���:
        add_forward_rule(){
            fn_exec_eval "firewall-cmd --permanent --direct --passthrough ipv4 -I FORWARD -p $1 -m $1 $2"
        }
        add_forward_rule tcp "--sport 69 --dport 67 -j ACCEPT"
        add_forward_rule udp "--sport 67 --dport 68 -j ACCEPT"
        add_forward_rule udp "--sport 8472 -j ACCEPT"
        add_forward_rule udp "--dport 8472 -j ACCEPT"
        add_forward_rule tcp "--dport 22 -j ACCEPT"
        add_forward_rule tcp "--sport 22 -j ACCEPT"
    fi
    #ע: ��VM��Ҫ���ӿ��豸ʱ,��Ҫ����3260(iSCSI)����.
    #  OpenStackĬ��ʹ��targetcli���ṩiSCSI����,����,��storage_node������
    #  cinderʱָ����iscsi_helper=lioadm.
    fn_check_tag_file "storage_node" && add_ipv4_rule "iscsi-target"
    
    #��ȫ����firewall(����ʧ��ǰ�ѽ������ӵ�firewall״̬��Ϣ),ʹ������ӵĹ�����Ч.
    fn_exec_eval "firewall-cmd --reload"
    return 0
}


fn_modify_os_security_set(){
    #����:�ر�ϵͳ�ķ���ǽ �� SELinux.
    # �ر�iptables:
    #   1.systemctl stop firewalld.service
    # �ر�SELInux
    #   1.�޸�/etc/selinux/config��,SELINUX=enforcing,ΪSELINUX=permissive
    #   ע: permissive:�ǹر�SELinux,����ʹSELinux������,������.

    fn_add_fw_rich_rules
    fn_exec_eval "sed -i 's|^\(SELINUX=\).*|\1permissive|' /etc/selinux/config && setenforce 0"
}

#----------------------------[END - ϵͳ���]---------------------------------#



#----------------------------[�ڵ�����]---------------------------------#

fn_init_os_auth_file(){
    #����:��ʼ��admin-token.sh admin-openrc.sh demo-openrc.sh
    
    #����ģ��
    rm -f $ADMINTOKENRC $DEMOOPENRC $ADMINTOKENRC
    cd $ROOT_DIR/etc/openrc_template && cp * ../

    #�޸�ģ��.
    [ -f $ADMINTOKENRC ] && sed -i "s|<TOKEN>|$ADMIN_TOKEN|; s|<HOSTNAME>|$CONTROLLER_HOST_NAME|" $ADMINTOKENRC
    [ -f $ADMINOPENRC ] && sed -i "s|<HOSTNAME>|$CONTROLLER_HOST_NAME|; s|<PWD>|$ADMIN_PASSWD|" $ADMINOPENRC
    [ -f $DEMOOPENRC ] && sed -i "s|<HOSTNAME>|$CONTROLLER_HOST_NAME|; s|<PWD>|$DEMO_PASSWD|" $DEMOOPENRC

    #����openrc��root�û���Ŀ¼
    local f cmd
    for f in $ADMINTOKENRC $ADMINOPENRC $DEMOOPENRC
    do
        cmd="$cmd cp $f /root/`basename ${f}`_script;"
    done
    fn_exec_eval "$cmd"
    unset cmd

    #�������뱨��.
    fn_create_password_report "admin-token.sh" "admin" "$ADMIN_TOKEN" "$ADMINTOKENRC"
    fn_create_password_report "admin-openrc.sh" "admin" "$ADMIN_PASSWD" "$ADMINOPENRC"
    fn_create_password_report "demo-openrc.sh" "demo" "$DEMO_PASSWD" "$DEMOOPENRC"
}


fn_config_ntp_service(){
    #����:����chrony��Controller�ڵ�����Ϊ�����ڵ��NTPʱ��Դ.

    fn_check_tag_file chrony
    [ $? -eq 0 ] && return 1

    local f=/etc/chrony.conf
    fn_check_file_and_backup $f
    local cmd="sed -i 's|^server|#server|g' $f;"
    cmd="$cmd sed -i '/#server.*3/a server $CONTROLLER_MANAGE_IP iburst' $f;"

    #controller_node:�˱�־�ļ�,������ڽű� openstack.sh ��,��ʼ�����ÿ��ƽڵ�ʱ����.
    fn_check_tag_file controller_node
    [ $? -eq 0 ] && cmd="$cmd sed -i '/^server/a allow $CONTROLLER_MANAGE_NET' $f"
    fn_exec_eval "$cmd"

    #��������
    fn_exec_systemctl "chronyd"

    fn_exec_eval "chronyc sources -v; chronyc sourcestats -v"

    fn_exec_sleep 10

    #������׼�ļ�.
    fn_create_tag_file chrony
    unset cmd
}

fn_inst_localNTPconfig(){
    #����: �ڿ��ƽڵ㰲װntp��������,�����ñ���Ϊʱ�������.
    #      �ǿ��ƽڵ�,����ntpͬ��.

    fn_check_tag_file "controller_node"
    if [ $? -eq 0 ]
    then
        fn_exec_eval "yum install -y ntp"
        local MANAGE_MASK=`cat /tmp/_ManageNetmask`
        local AllowNet="restrict ${CONTROLLER_MANAGE_NET%/*} mask $MANAGE_MASK nomodify notrap"
        echo "server 127.127.1.0" > _ntpSVRconf
        echo "fudge 127.127.1.0 stratum 10" >> _ntpSVRconf
        sed -i -e "s,^restrict ::1,$AllowNet," \
               -e "s,^server,#server," \
               -e "/127\.127\.1\.0/d" \
               -e "/^#server 3.*/r _ntpSVRconf" /etc/ntp.conf
        rm -f _ntpSVRconf /tmp/_ManageNetmask
        return 0
    fi

    echo "*/3 * * * * /usr/sbin/ntpdate $CONTROLLER_MANAGE_IP &>/dev/null" > _ntpsync
    crontab _ntpsync && rm -f _ntpsync
    echo "SYNC_HWCLOCK=yes" >> /etc/sysconfig/ntpd
    return 0
}

fn_inst_mairadb(){
    #����:��װ������MairaDB

    fn_check_tag_file mairadb
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install mariadb mariadb-server python2-PyMySQL -y"

    local mycnf=/etc/my.cnf.d/openstack.cnf
    local cmd="cat $MYCNF_FILE > $mycnf;"
    cmd="$cmd sed -i 's,<IP>,$CONTROLLER_MANAGE_IP,' $mycnf"
    fn_exec_eval "$cmd"
    
    #��������
    fn_exec_systemctl "mariadb"

    #ROOT_DIR:����ڽű�openstack.sh��export�ˡ�
    local mysql="$ROOT_DIR/bin/modify_mysql_secure_installation"
    $mysql  --oldrootpass "" --newrootpass "$MARIADB_PASSWORD"

    #�������뱨��
    fn_create_password_report "MariaDB" "root" "$MARIADB_PASSWORD" "MariaDB root password."
    
    #������־�ļ�.
    fn_create_tag_file mairadb
    unset cmd
}

fn_inst_rabbitmq(){
    #����:��װ������������rabbitmq

    fn_check_tag_file rabbitmq
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install rabbitmq-server -y"
    
    #��������.
    fn_exec_systemctl "rabbitmq-server"

    #��rabbitmq�д���openstack�û�
    # ��ʽ: rabbitmqctl add_user USERNAME PASSWORD
    local cmd="rabbitmqctl add_user ${RABBITMQ_USERNAME} ${RABBITMQ_PASSWORD}"
    fn_exec_eval "$cmd" " (����openstack�û�������RabbitMq����Դ.)"

    #����openstack��Ȩ��(configuration, write, read)
    cmd='rabbitmqctl set_permissions openstack ".*" ".*" ".*"'
    fn_exec_eval "$cmd" " (����openstack�û�ӵ�ж�'/'���vhost��(����,д,��)��Ȩ��,ע:Ĭ���û�guestҲ������ЩȨ��."

    #����RabbitMQ�����뱨��.
    fn_create_password_report "RabbitMQ" "openstack" "${RABBITMQ_PASSWORD}" "RabbitMQ Admin Account Create." 
    
    #������־�ļ�.
    fn_create_tag_file rabbitmq
    unset cmd
}

fn_inst_memcached(){
    #����:��װ������Memcached

    fn_check_tag_file memcached
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install memcached python-memcached -y"

    #��������.
    fn_exec_systemctl "memcached"

    #������־�ļ�.
    fn_create_tag_file memcached
}

fn_check_openstack_conf(){
    #����: ���etc/openstack.conf�еĲ���ֵ�Ƿ���ڿ�Ԥ��Ĵ���.
    #  1.�����ƽڵ�Ĺ���IP,����IP�Ƿ��뵱ǰ���ƽڵ�ifconfig���һ��.
    #    ���ǿ��ƽڵ���ifconfig�������etc/hosts���ṩ���Ƿ�һ�¡�
    #  2.����Ƿ��Ѿ���etc/hosts ���뵽/etc/hosts ��,û������.
    #  3.���ping,��ping����,��ͨ�����˳�;���ż�������ڵ�.
    #  4.���洢�ڵ����������ļ����ṩ�Ĵ��̻�����Ƿ���ռ�û򲻴���.

    get_netprefix_and_subnetmask(){
        local CIDR=$1
        local TotalHostBit=$((32-$CIDR))
        local contrIP=$CONTROLLER_MANAGE_IP
        if [ $TotalHostBit -le 8 ]
        then
            SubnetMask=255.255.255.`echo 256-2^$TotalHostBit|bc`
            NetPrefix=`echo $contrIP|awk -F'.' '{printf "%d.%d.%d\n",$1,$2,$3}'`
        elif [ $TotalHostBit -le 16 ]
        then
            SubnetMask=255.255.`echo 256-2^\($TotalHostBit-8\)|bc`.0
            NetPrefix=`echo $contrIP|awk -F'.' '{printf "%d.%d\n",$1,$2}'`
        elif [ $TotalHostBit -le 24 ]
        then 
            SubnetMask=255.`echo 256-2^\($TotalHostBit-16\)|bc`.0.0
            NetPrefix=`echo $contrIP|awk -F'.' '{printf "%d\n",$1}'`
        elif [ $TotalHostBit -lt 32 ]
        then
            SubnetMask=`echo 256-2^\($TotalHostBit-24\)|bc`.0.0.0
            NetPrefix=`echo $contrIP|awk -F'.' '{printf "%d\n",$1}'`
        else
            fn_err_log "����CIDR��������,��ȷ��."
        fi
    }

    #���etc/hosts
    if [ -s $HOSTS_FILE ]
    then
        grep "\<$CONTROLLER_HOST_NAME\>" $HOSTS_FILE |grep -q "\<$CONTROLLER_MANAGE_IP\>"
        [ $? -eq 0 ] || fn_err_log "�����������ļ��п��ƽڵ�������������IP��$HOSTS_FILE �ж���Ĳ�һ��."

        local storage compute
        fn_check_tag_file "storage_node"; storage=$?
        fn_check_tag_file "compute_node"; compute=$?
        if [ $storage -eq 0 -o $compute -eq 0 ]
        then
            #ע��
            #   ����ʵ�����Ǵ��������,��:������������:
            #   eth0:10.1.10.10/16   eth1:10.1.11.10/16 ,�������޷������Ǹ��ǹ���IP��.
            #   ��Ϊ:16ȡ�Ļ�,����λȡ������:10.1 ,����ʱ�ͻ��������IP,�ͺܿ��ܳ���.
            #��ע:
            #  1.��IPǰ׺������������Ϊ����IP��IP��ַ,
            #  2.������֤CIDR(����ת������������),
            #  3.������֤etc/hosts���ṩ��IP����ܵĹ���IP�Ƿ�һ��
            #  4.���,��֤��IP��Ӧ���������Ƿ��뱾�����õ�һ��.
            get_netprefix_and_subnetmask ${CONTROLLER_MANAGE_NET#*/}
            ifconfig |grep "$NetPrefix" |grep "$SubnetMask" |awk 'END{print $2}' |xargs -i{} grep {} $HOSTS_FILE |grep -q "`hostname`"
            [ $? -eq 0 ] || fn_err_log "���ifconfig����Ĺ���IP �� hostname����������� ��$HOSTS_FILE �ж���Ĳ�һ��,��ȷ��."
        fi

        #����hosts�ļ�
        grep -q "$CONTROLLER_MANAGE_IP" /etc/hosts || cat $HOSTS_FILE >> /etc/hosts
        #��Ȿ���������ͨ��
        ping -c 2 `hostname` &>/dev/null
        [ $? -eq 0 ] || fn_err_log "ping���hostnameʧ��,���鱾��IP���ú������������Ƿ���ȷ."

        local retval=0
        for host in `awk '{print $2}' $HOSTS_FILE`
        do
            ping -c 2 $host &>/dev/null
            fn_warn_or_info_log "����ping����: $host "
            retval=$((retval+$?))
        done
        [ $retval -eq 0 ] || fn_warn_log "���Ը��ڵ�������ʧ��: $retval ��,��ע�������."
        fn_exec_sleep '5'
    else 
        fn_err_log "���ṩ: $HOSTS_FILE,��֤���ڵ�������ӳ��IP����."
    fi

    #�洢�ڵ���
    fn_check_tag_file "storage_node"
    if [ $? -eq 0 ]
        then
        for disk in ${CINDER_DISK} ${MANILA_DISK}
        do
            fdisk -l $disk &>/dev/null; retval=$?
            pvs |grep -q "\<$disk\>"; retval=$(($retval+$?))
            [ $retval -eq 1 ] || fn_err_log "�����ļ���ָ���Ľ������cinder��manilaʹ�õĴ���:$disk �����ڻ���ռ��."
        done
    fi

    local G_msg msg msg1
    fn_check_tag_file "controller_node"
    if [ $? -eq 0 ]
    then
        get_netprefix_and_subnetmask ${CONTROLLER_PUBLIC_NET_IP#*/}
        local PubNetSubnetMask=$SubnetMask
        get_netprefix_and_subnetmask ${CONTROLLER_MANAGE_NET#*/}
        local ManageSubnetMask=$SubnetMask
        #���Ǵ洢�����������������,�������ñ���NTP������ʹ��.
        echo "$ManageSubnetMask" > /tmp/_ManageNetmask

        #������IP�͹���IP
        msg="ifconfigִ�н����û���ҵ��������ļ��ж���Ŀ��ƽڵ�Ĺ���IP����������:"
        ifconfig |grep "\<$CONTROLLER_MANAGE_IP\>" |grep -q "\<$ManageSubnetMask\>" || \
                  fn_err_log "$msg $CONTROLLER_MANAGE_IP/$ManageSubnetMask(${CONTROLLER_MANAGE_NET#*/})"

        local PubNetIP=${CONTROLLER_PUBLIC_NET_IP%/*}
        ifconfig |grep "\<$PubNetIP\>" |grep -q "\<$PubNetSubnetMask\>"
        if [ $? -ne 0 ]
        then
            msg1="$msg $CONTROLLER_PUBLIC_NET_IP/$PubNetSubnetMask(${CONTROLLER_PUBLIC_NET_IP#*/})"
            G_msg="$G_msg\n$msg1"
            fn_warn_log "$msg1"
        fi
        
        route -n |grep '^0.0.0.0' |grep -q "\<$PUBLIC_NET_GW\>"
        if [ $? -ne 0 ]
        then
            msg="route����ִ�н����û���ҵ��������ļ���ָ����Ĭ������:$PUBLIC_NET_GW"
            G_msg="$G_msg\n$msg"
            fn_warn_log "$msg"
        fi


        #neutron���ּ��
        local PrioverNet_CIDR=${PUBLIC_NET#*/}
        local ControllerPubNet_CIDR=${CONTROLLER_PUBLIC_NET_IP#*/}
        msg="���޸��������ļ����ṩ����(Priover Network)��PUBLIC_NET��CIDRֵ��CONTROLLER_PUBLIC_NET_IP��ָ����һ��."
        [ $PrioverNet_CIDR -eq $ControllerPubNet_CIDR ] || fn_err_log "$msg"

        #glance����
        local exist=0
        for img in ${IMG_LIST[*]}
        do
            [ -f "`a=${img#*:}; echo ${a%:*}`" ] && exist=$(($noexist+1))
        done
        [ $exist -eq 0 ] && fn_err_log "�������ļ��ж����image fileû��һ������."

        #yumԴ����ļ����
        [ -f $CENTOS72_LOCAL_YUM_SOURCE ] || fn_err_log "û���ҵ���������yum��rpm����ļ�($CENTOS72_LOCAL_YUM_SOURCE)."
    fi

    #yum����
    if [ ! -f $INTERNET_YUM_FILE ]
    then
        msg="û���ҵ�����yumԴ��װ�����ļ�($INTERNET_YUM_FILE)."
        G_msg="$G_msg\n$msg"
        fn_warn_log "$msg"
    fi
    [ -f $LOCAL_YUM_FILE ] || fn_err_log "û���ҵ�����yumԴ��װ�����ļ�($LOCAL_YUM_FILE)."

    #���벿��
    if [ "$ALL_PASSWORD" == "ChangeMe" ]
    then
        msg="�������з������뽫ʹ��Ĭ������:ChangeMe"
        G_msg="$G_msg\n$msg"
        fn_warn_log "$msg"
    fi

    #ģ�������ļ�����
    [ -f "$MYCNF_FILE" ] || fn_err_log "û���ҵ��޸Ĺ���mariadbģ�������ļ�:$MYCNF_FILE"
    [ -f "$KEYSTONE_HTTPCONF_FILE" ] || fn_err_log "û���ҵ��޸Ĺ���keystone��httpd��ģ�������ļ�:$KEYSTONE_HTTPCONF_FILE"
    [ -f "$DASHBOARD_CONF_FILE" ] || fn_err_log "û���ҵ��޸Ĺ���dashboard��ģ�������ļ�:$DASHBOARD_CONF_FILE"
    [ -f "$MONGODB_CONF_FILE" ] || fn_err_log "û���ҵ��޸Ĺ���mongodb��ģ�������ļ�:$MONGODB_CONF_FILE"


    if [ -n "$G_msg" ]
    then
        echo -e "\e[33m����������ļ�($os_CONF_FILE)���:"; echo -e "$G_msg\e[0m"|nl -n ln
        fn_exec_sleep 10
    fi
    return 0
}

fn_init_node_env(){
    #����:���ϵͳ�����Ƿ���ϰ�װOpenstack-Mitaka������.
    #   1.���ϵͳ���Ժͱ���������.
    #   2.����������ļ��Ƿ���ڿ�Ԥ��Ĵ���
    #   3.����hosts�ļ�,������ping����������
    #   4.�ǿ��ƽڵ����fn_import_os_file����,��ȡ�ǿ��ƽڵ���~/os �ļ�,��ȡ�ýڵ��ϵ�
    #     �����ӿڵĽӿ���.  
    #   5.���ϵͳ�汾�Ƿ���CentOS7.2-1511��ϵͳ�������.
    #     ��Ҫ��:Kernel=3.10.0-327; python=2.7.5
    #   6.���ϵͳ��Դ�Ƿ����Controller��Compute�ڵ���������Ҫ��.
    #     ��:Controller=RAM4G,DISK5G,NIC2; Compute:RAM2G,DISK5G,NIC2
    #   7.���������,�����������ļ����趨�����������޸�������.
    #     ע:�޸�����������,����Ҫ����hosts�ļ�����.
    #   8.�޸�ϵͳ����:��SELinux�޸�Ϊ�����治��ֹ(permissive) �� �����������OpenStack�����firewall����.
    #   9.���yumԴ����.
    #   10.��װδ��װ����������
    #   11.����ϵͳ�����пɸ��µ����.
    #   12.��ʼ��admin-token.sh admin-openrc.sh demo-openrc.sh
    #   13.Controller�ڵ㽫��װ������mairadb/rabbitmq/memcached.
    #   14.����NTP����,(ע:Controller:��������ΪNTP�����,��Controller��Ϊ�ͻ���.)

    #ע:Ӧ����ѡ��װ�ڵ�ʱ,�����ڵ����ͱ�־�ļ�.
    #������װ�ڵ��� Controller | Compute | Storage �ڵ�ı�־�ļ�.
    fn_create_tag_file "$1"

    fn_check_os_lang_and_soft
    fn_check_openstack_conf

    #��鵱ǰ�ڵ���Ϊ�ǿ��ƽڵ�����"/root/os",��ȡ�����ӿ���,�������˽ڵ��
    #   SLAVE_NODE_HOST_NAME,SLAVE_NODE_MANAGE_IP, 
    #   SLAVE_NODE_PUBLIC_NET_NIC, SLAVE_NODE_PUBLIC_NET_IP,SLAVE_NODE_PUBLIC_NET_GW
    fn_check_tag_file "controller_node" || fn_import_os_file

    fn_check_os_version
    fn_check_os_resource
    fn_modify_os_security_set
    fn_check_yum

    #��װ��������:
    #       curl,
    #       openstack-utils(openstack-config),
    #       python-openstackclient(openstack)
    #       openstack-selinux
    #       chrony(ntp)
    #       ntpdate
    #       yum-plugin-priorities
    #       sysfsutils

    local softlist=/tmp/softlist.txt
    cat $softlist |while read rpm
    do
        fn_exec_eval "yum install $rpm -y" 
    done

    yum update -y

    #��ʼ��admin-token.sh admin-openrc.sh demo-openrc.sh
    fn_init_os_auth_file

    fn_check_tag_file "compute_node"; compute=$?
    fn_check_tag_file "storage_node"; storage=$?
    fn_check_tag_file "controller_node"; controller=$?
    if [ $controller -eq 0 ]
        then
        if [ $compute -eq 0 -o $storage -eq 0 ]
        then
            fn_err_log "���鵱ǰ�ڵ��ϵĽڵ��־�ļ�,һ���ڵ㲻����ͬʱΪ���ƽڵ� �� ����ڵ��洢�ڵ�."
        fi
        
        #Controller�ڵ㽫��װ������mairadb/rabbitmq/memcached.(ע:rabbitmq���Զ�����,�������ֶ�����.)
        fn_inst_mairadb
        fn_inst_rabbitmq
        fn_inst_memcached
    fi

    #����NTP����,(ע:Controller:��������ΪNTP�����,��Controller��Ϊ�ͻ���.)
    fn_inst_localNTPconfig
    #fn_config_ntp_service

    fn_inst_componet_complete_prompt "Init $1 Successed."
}

#----------------------------[ END - �ڵ�����]---------------------------------#

#set -o xtrace
fn_init_node_env "$1"
#set +o xtrace
