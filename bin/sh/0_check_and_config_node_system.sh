#!/bin/bash

. $os_FUNCS   
. $os_CONF_FILE

fn_import_os_file(){
    #功能:检查非控制节点上是否存在配置文件"os",若存在则导入。
    #     此函数,通过导入计算节点,存储节点上的上网接口名.
    #     来获取上网IP,和出口网关.
    # 
    #注:
    #    创建os文件: 
    #    echo "上网接口名" > ~/os
    #
    #另注:
    #   此函数,将在fn_init_node_env函数中调用;调用函数的假设前提是:
    #   计算节点和存储节点已经正确设置了主机名和/etc/hosts.
    #   否则,获取的信息将是错误的.


    local osfile=/root/os
    if [ -s "$osfile" ]
    then
        PublicNetNIC=`cat $osfile`
        if [ -n "$PublicNetNIC" ]
        then
            SLAVE_NODE_PUBLIC_NET_NIC=$PublicNetNIC
        else
            fn_err_log "您提供的 $osfile 为空."
        fi
    else
        local IFN_UserCh IFNAMES CH msg 
        IFN_UserCh=(`ifconfig |grep -B1 "\<inet\>" |awk -F: '/flags/{if($1!="lo"){print $1}}' |nl -n ln -v 0`)
        IFNAMES=(`ifconfig |grep -B1 "\<inet\>" |awk -F: '/flags/{if($1!="lo"){print $1}}'`)
        local msg="请选择上网接口的编号名称[${IFN_UserCh[*]}]:"
        read -p "`echo -e "\e[32m$msg\e[0m"`" CH
        if [ -z "${IFNAMES[$CH]}" ]
        then 
            fn_warn_log "您输入有误,请确认后,再次操作." 
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
    #导入从节点的配置文件
    . $CONF
}

#----------------------------[系统检测]---------------------------------#

fn_check_os_version(){
    #功能: 检查系统环境是否适合安装OpenStack-Mitaka版.
    #   1.检查/etc/centos-release 或 /etc/redhat-release
    #     若以上文件不存在或读取失败,则尝试:
    #     a. 查看/proc/version, Kernel必须是:3.10.0-327.x86_64
    #     b. 查看python -V, python版本必须是: 2.7.5
    
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
             fn_info_log "当前系统: $OS_Ver ,符合要求."
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
            fn_info_log "您的系统为: $OS-$OS_Kernel_Ver-$OS_Arch , Python-$Python_Ver 符合CentOS7.2-1511的基础环境."
            return 0 
        else
            local os="$OS-$OS_Kernel_Ver-$OS_Arch"
            local base="Kernel-3.10.0-327 和 Python-2.7.5"
            fn_err_log "您的系统为: $os , Python-$Python_Ver 不符合 $base 的基本要求."
            exit 0
        fi
    fi
}

fn_check_os_resource(){
    #功能:检查系统资源是否符合Mitaka的要求.
    #   M版要求: Controller Node: RAM=4G, DISK=5G, NIC=2
    #            Computer Node: RAM=2G,DISK=5G, NIC=2

    #对内存大小四舍五入
    local RAM_TotalSize=$(cat /proc/meminfo |awk '/MemTotal/{print int($2/1024/1024+0.5)}')
    local DISK_AvailableSize=$(df -h / |awk '/G/{printf("%d",$4)}')

    #eno1401021: en:EtherNet,o:Onboard(板载),1401021:设备索引号(domain=0014,pci=01,dev=02,function=1).
    #ens1402010: s:slot(热插拔槽)
    #enp2sxxxxx: p:PCI,s:slot:这是外接PCI或USB设备的命名.
    #enx78e7d1ea46da: enx:(不清楚), 78e7d1ea46da:此MAC地址.
    #
    local NIC_Num=$(nmcli dev |awk '/en[ospx]|eth[0-9]/{n++}END{print n}')
    local ramsize msg

    compare_chk(){
        msg="您系统的内存:${RAM_TotalSize}G 要求:${1}G,磁盘:${DISK_AvailableSize}G 要求:5G,网卡:${NIC_Num}个 要求:2个"
        if [ $RAM_TotalSize -ge $1 ] && [ $DISK_AvailableSize -ge 5 ] && \
           [ $NIC_Num -ge 2 ]
        then
            msg="${msg} 符合安装OpenStack-Mitaka的最低系统资源要求."
            fn_info_log "$msg"
        else
            msg="${msg} 不符合安装OpenStack-Mitaka的最低系统资源要求."
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
    #功能: 检查系统环境是否能满足脚本输出日志.
    #   1.此脚本采用中文日志,需检查:export LANG=zh_CN
    #   2. 检查脚本需要用到软件:
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

    #必须的软件检查
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
            fn_info_log "$rpm 已经安装." 
        else
            echo $rpm >> $softlist
            fn_warn_log "$rpm 软件未安装,\e[32m已加入安装计划列表($softlist)\e[0m."
        fi
    done
}

fn_check_os_net(){
    #功能:检查系统是否能正常访问Internet.
    #   1. 检查网络,不通:0.检查代理; 1.ping 公网DNS; 2.curl baidu.com;

    #检查网络
    #检查是否为DHCP分配IP
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
        #功能:检查配置文件中指定上网接口上的IP是否为DHCP分配,
        #    若是,1.检查配置文件是否定义了该接口的固定IP,有则修改为此固定IP.
        #         2.若没有定义固定IP,则提示将DHCP分配的IP修改为此接口固定IP.
        #    若否,返回0,即接口为固定IP.
        #注:
        #   不检查私有管理IP,是因为物理上网接口一般为DHCP分配IP,私有管理IP,
        #   一般为手动分配.至少在测试环境中是.

        #获取当前节点上网的接口名 和 上网的IP.
        #获取配置文件中export的所有'节点配置'中的变量的前缀.
        #local vnames="(COMPUTE|NEUTRON|STORAGE)[[:digit:]]{1,}"
        #local cns="CONTROLLER `env |grep -Eo "$vnames" |sort |uniq`"
        #
        ##通过这些标识不同节点的标识前缀,来确定当前应该使用那组公网IP和接口.
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
        #    #对比当前上网接口IP 与 配置文件:openstack.conf 中定义的上网接口IP是否一致.
        #    if [ -n "$PubNetIP" -a -n "$PubNetGW" ]
        #    then
        #        fn_exec_eval "$cmd $PubNetIP ipv4.method manual ipv4.gateway $PubNetGW && nmcli conn up $connName"
        #        fn_info_log "\e[;41m 修改上网接口:$PubNetifname 的IP($ip4)为配置文件中指定的固定IP($PubNetIP)"
        #        return 0
        #    fi

            local cmd="nmcli conn down $connName && nmcli conn modify $connName ipv4.addresses"
            if [ -n "$PubNetIP" -a -n "$PubNetGW" ]
            then
                local msg="发现接口:$PubNetifname 的活动链接:$connName 的IP:($PubNetIP)为DHCP自动分配,请修改为固定IP,"
                msg="$msg\n否则IP改变将导致OpenStack网络服务出错.(y=使用$PubNetIP,n=退出,手动修改.)[y|n]:"
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


    #检查直连网络
    chk_direct_net(){
        #仅在代理检测失败后,才做此检查.
        #   1.检查接口IP是否为固定IP.
        #   2.检查是否可直接上网,
        #     是: 返回0
        #     否: 返回1

        chk_dhcp
        local RetVal
        ping -c 2 114.114.114.114 &>/dev/null; RetVal=$?
        ping -c 2 8.8.8.8 &>/dev/null; RetVal=$(($RetVal+$?))
        if [ $RetVal -eq 0 ]
        then
            curl www.baidu.com &>/dev/null
            if [ $? -eq 0 ]
            then
                fn_info_log "本机可直接访问互联网,网络检查完成"
                return 0
            else
                local cmd="nmcli conn modify $connName ipv4.dns ${PUBLIC_NET_DNS};"
                cmd="$cmd nmcli conn down $connName && nmcli conn up $connName"
                local msg="执行命令: $cmd 添加DNS."
                eval "$cmd"
                unset cmd
                if [ $? -eq 0 ]
                then
                    fn_warn_log "$msg 成功.将使用公网yum源."
                    return 0
                else 
                    fn_warn_log "$msg 失败,将使用本地yum源."
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
                        fn_info_log "检查直连Internet成功,将使用Internet yum源."
                        return 0
                    else
                        fn_warn_log "检查直连Internet失败,将使用本地yum源."
                        return 1
                    fi
                fi
            fi

            fn_warn_log "检查直连Internet失败,将使用本地yum源."
            return 1
        fi
    }
    #检查代理网络.
    if [ "$G_PROXY" == "True" -a -f "$PROXY_CONF_FILE" -a `grep -v '^#' "$PROXY_CONF_FILE" |wc -l` -ge 1 ]
    then
         . "$PROXY_CONF_FILE"
         local Proxy="$http_proxy $https_proxy $ftp_proxy"
         curl www.baidu.com &>/dev/null
         if [ $? -eq 0 ]
         then
            fn_info_log "导入代理配置成功,将使用: $Proxy 做代理."
            return 0
         fi
    fi

    fn_warn_log "导入代理 $Proxy 不可用,测试 curl www.baidu.com 失败"
    chk_direct_net
    return $?
}

fn_check_yum(){
    #功能:测试是使用本地源或公网源.
    
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
        fn_exec_eval "$cmd" "导入yum配置文件."
        fn_exec_eval "yum clean all && yum repolist"
    }
    
    fn_check_os_net
    if [ $? -eq 0 ]
    then
        cmd="cp -a $INTERNET_YUM_FILE $YumHome;"
        cmd="$cmd cp -a $INTERNET_YUM_KEYS_DIR/* /etc/pki/rpm-gpg/"
        fn_exec_eval "$cmd"
        local msg="\e[;41m使用Internet yum源,将必须安装"yum-plugin-priorities",来控制源的优先级,"
        msg="$msg 这是因为,epel源,可能提供了比openstack源更新的包,这可能导致openstack出现,"
        msg="$msg 无法预料的错误."
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
            fn_info_log "开始创建本地yum源: $cmd"
            fn_exec_eval "$cmd" "导入yum源文件."

            fn_exec_systemctl "httpd"
            fn_info_log "$cmd 使用httpd来做本地yum源"
            
            inst_local_yum
            unset cmd
        else
            fn_err_log "没有找到本地yum源文件包: $CENTOS72_LOCAL_YUM_SOURCE"
        fi
    fi
}

#fn_set_hostname_and_import_hosts(){
#    #功能: 设置并检查主机名,并导入hosts文件.
#    #
#    #   注:使用此函数必须在调用时给HOST_NAME赋值.
#
#    if [ -z "$HOST_NAME" ]
#    then
#        fn_err_log "请提供节点主机名:export HOST_NAME=主机名"
#    else
#        fn_exec_eval "hostnamectl set-hostname ${HOST_NAME}"
#    fi
#
#    if [ -s $HOSTS_FILE ]
#    then
#        fn_exec_eval "cat $HOSTS_FILE >> /etc/hosts"
#    else
#       fn_err_log "请提供 $HOSTS_FILE ,以便保证各节点主机名可正常解析."
#
#       # fn_warn_log "$HOSTS_FILE 不存在,将自动添加主机名与IP地址映射."
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
#       #         err="$err $vhn=$vh : $vin=$vi 缺少映射关系.将不加入hosts.\n"
#       #     fi
#       # done
#       # fn_exec_eval "$cmd"
#       # [ -n "$err" ] && fn_warn_log "$err"
#    fi
#
#    ping -c 2 $HOST_NAME &>/dev/null && RetVal1=$?
#    ping -c 2 `hostname -i` &>/dev/null && RetVal2=$?
#    [ $RetVal1 -eq 0 -a $RetVal2 -eq 0 ] && \
#                    fn_info_log "设置并检测主机名完成" || \
#                    fn_err_log "主机名与IP映射失败,设置主机名失败."
#}

fn_add_fw_rich_rules(){
    #功能:添加firewall 访问规则.
    #     将Controller Node上的OpenStack服务内部节点开放.
    
    #firewall默认用户自定义服务根目录
    local FW_SERVICE_DIR=/etc/firewalld/services

    #firewall默认区域根目录
    local FW_DEFAULT_ZONE_DIR=/etc/firewalld/zones

    #默认public区域的富规则配置文件
    local FW_PUBLIC_ZONE_XML=$FIREWALL_CONF_DIR/public.xml

    #设置OpenStack管理网络的网段号
    local IP_NET=$CONTROLLER_MANAGE_NET

    #local DefaultZone=`firewall-cmd --get-default-zone`
    #if [ "$DefaultZone" == "public" ]
    #then
    #    if [ -f $FW_PUBLIC_ZONE_XML ]
    #    then
    #        local f=$FW_DEFAULT_ZONE_DIR/public.xml
    #        cat $FW_PUBLIC_ZONE_XML > $f
    #        sed -i "s,<IntNet>,$IP_NET,g" $f
    #        fn_err_or_info_log "向firewall默认区域(public)导入富规则"

            #安全重载firewall(不丢失当前已建立连接的firewall状态信息),使上面添加的规则生效.
    #        fn_exec_eval "firewall-cmd --reload"
    #        return 0
    #    fi
    #fi

    add_ipv4_rule(){
        if [ -z "$IP" ]
        then
            if [ -z "$2" ]
            then
                fn_err_log "必须提供OpenStack管理网络的网段IP(格式:192.168.10.0/24)."
            else
                IP=$2
            fi
        fi

        #添加OpenStack服务到默认firewall服务根目录.
        local SVRXmlFile=$FIREWALL_CONF_DIR/${1}.xml
        [ -f "$SVRXmlFile" ] && cp $SVRXmlFile $FW_SERVICE_DIR

        local Rule="rule family='ipv4' source address='$IP' service name='$1' log prefix="$1" level='info' accept"
        fn_exec_eval "firewall-cmd --permanent --add-rich-rule=\"$Rule\"" "导入防火墙规则"
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

    #注:
    #  firewall默认的vnc-server只开启了5900-5903这个4个VNC端口.
    fn_check_tag_file "compute_node" 
    if [ $? -eq 0 ]
    then 
        add_ipv4_rule "vnc-server" 
        #OTV:与VxLAN类似,它们都是大二层技术,都是将二层帧封装到IP包中,实现跨数据中心的二层互联.
        #但是OTV是Cisco的私有协议,VxLAN是Cisco/VMware合作开发的二层技术,目前已提交给IETF成为草案,
        #支持众多厂商,但OpenStack-Mitaka默认没有使用VxLAN,而采用了OTV来代替VxLAN.为何如此,还不清楚.
        #注:  开放OTV通信端口,是为了让启动的VM可以获取DHCP分配的IP,因为VM获取IP的拓扑如下:
        # VM[eth0]-----(tap0)[Intbr]宿主机(ComputeNode)[Intbr](vxlan-XX)---(vxlan-XX)[Intbr]控制节点[Intbr](tap)----(qdhcp-xxxx)NetNS
        # VM相对于ComputeNode是另一台主机,VM发出的报文,对于ComputeNode上的firewalld来说是进来的流量,
        # 因此查INPUT链,但必须说明的是,VM发出的报文到达Intbr时,是没有封装OTV的,当OTV接口接收到报文时,
        # 因为报文要去的远端是OTV的对端,因此OTV会封装它,封装完成后,外层IP和PORT是计算节点的与控制节点
        # 建立OTV隧道的IP(一般为管理IP,此脚本安装的也是管理IP)和OTV的UDP端口号,这时firewalld进入INPUT
        # 链查找时,匹配的是外层IP和端口,若没有放行,就会导致丢包.  控制节点就更不用说了,从外部来的流量
        # 检查一样是INPUT链,当然也要放行。
        add_ipv4_rule "os_otv"

        #临时的解决浮动IP的方法:
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
    #注: 若VM需要附加块设备时,需要放行3260(iSCSI)服务.
    #  OpenStack默认使用targetcli来提供iSCSI服务,所以,在storage_node中配置
    #  cinder时指定了iscsi_helper=lioadm.
    fn_check_tag_file "storage_node" && add_ipv4_rule "iscsi-target"
    
    #安全重载firewall(不丢失当前已建立连接的firewall状态信息),使上面添加的规则生效.
    fn_exec_eval "firewall-cmd --reload"
    return 0
}


fn_modify_os_security_set(){
    #功能:关闭系统的防火墙 和 SELinux.
    # 关闭iptables:
    #   1.systemctl stop firewalld.service
    # 关闭SELInux
    #   1.修改/etc/selinux/config中,SELINUX=enforcing,为SELINUX=permissive
    #   注: permissive:非关闭SELinux,它将使SELinux仅警告,不阻拦.

    fn_add_fw_rich_rules
    fn_exec_eval "sed -i 's|^\(SELINUX=\).*|\1permissive|' /etc/selinux/config && setenforce 0"
}

#----------------------------[END - 系统检测]---------------------------------#



#----------------------------[节点配置]---------------------------------#

fn_init_os_auth_file(){
    #功能:初始化admin-token.sh admin-openrc.sh demo-openrc.sh
    
    #复制模板
    rm -f $ADMINTOKENRC $DEMOOPENRC $ADMINTOKENRC
    cd $ROOT_DIR/etc/openrc_template && cp * ../

    #修改模板.
    [ -f $ADMINTOKENRC ] && sed -i "s|<TOKEN>|$ADMIN_TOKEN|; s|<HOSTNAME>|$CONTROLLER_HOST_NAME|" $ADMINTOKENRC
    [ -f $ADMINOPENRC ] && sed -i "s|<HOSTNAME>|$CONTROLLER_HOST_NAME|; s|<PWD>|$ADMIN_PASSWD|" $ADMINOPENRC
    [ -f $DEMOOPENRC ] && sed -i "s|<HOSTNAME>|$CONTROLLER_HOST_NAME|; s|<PWD>|$DEMO_PASSWD|" $DEMOOPENRC

    #复制openrc到root用户家目录
    local f cmd
    for f in $ADMINTOKENRC $ADMINOPENRC $DEMOOPENRC
    do
        cmd="$cmd cp $f /root/`basename ${f}`_script;"
    done
    fn_exec_eval "$cmd"
    unset cmd

    #创建密码报表.
    fn_create_password_report "admin-token.sh" "admin" "$ADMIN_TOKEN" "$ADMINTOKENRC"
    fn_create_password_report "admin-openrc.sh" "admin" "$ADMIN_PASSWD" "$ADMINOPENRC"
    fn_create_password_report "demo-openrc.sh" "demo" "$DEMO_PASSWD" "$DEMOOPENRC"
}


fn_config_ntp_service(){
    #功能:配置chrony将Controller节点配置为其它节点的NTP时间源.

    fn_check_tag_file chrony
    [ $? -eq 0 ] && return 1

    local f=/etc/chrony.conf
    fn_check_file_and_backup $f
    local cmd="sed -i 's|^server|#server|g' $f;"
    cmd="$cmd sed -i '/#server.*3/a server $CONTROLLER_MANAGE_IP iburst' $f;"

    #controller_node:此标志文件,将在入口脚本 openstack.sh 中,初始化配置控制节点时创建.
    fn_check_tag_file controller_node
    [ $? -eq 0 ] && cmd="$cmd sed -i '/^server/a allow $CONTROLLER_MANAGE_NET' $f"
    fn_exec_eval "$cmd"

    #启动服务
    fn_exec_systemctl "chronyd"

    fn_exec_eval "chronyc sources -v; chronyc sourcestats -v"

    fn_exec_sleep 10

    #创建标准文件.
    fn_create_tag_file chrony
    unset cmd
}

fn_inst_localNTPconfig(){
    #功能: 在控制节点安装ntp服务端软件,并配置本地为时间服务器.
    #      非控制节点,配置ntp同步.

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
    #功能:安装并配置MairaDB

    fn_check_tag_file mairadb
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install mariadb mariadb-server python2-PyMySQL -y"

    local mycnf=/etc/my.cnf.d/openstack.cnf
    local cmd="cat $MYCNF_FILE > $mycnf;"
    cmd="$cmd sed -i 's,<IP>,$CONTROLLER_MANAGE_IP,' $mycnf"
    fn_exec_eval "$cmd"
    
    #启动服务
    fn_exec_systemctl "mariadb"

    #ROOT_DIR:在入口脚本openstack.sh中export了。
    local mysql="$ROOT_DIR/bin/modify_mysql_secure_installation"
    $mysql  --oldrootpass "" --newrootpass "$MARIADB_PASSWORD"

    #创建密码报表
    fn_create_password_report "MariaDB" "root" "$MARIADB_PASSWORD" "MariaDB root password."
    
    #创建标志文件.
    fn_create_tag_file mairadb
    unset cmd
}

fn_inst_rabbitmq(){
    #功能:安装、启动并配置rabbitmq

    fn_check_tag_file rabbitmq
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install rabbitmq-server -y"
    
    #启动服务.
    fn_exec_systemctl "rabbitmq-server"

    #在rabbitmq中创建openstack用户
    # 格式: rabbitmqctl add_user USERNAME PASSWORD
    local cmd="rabbitmqctl add_user ${RABBITMQ_USERNAME} ${RABBITMQ_PASSWORD}"
    fn_exec_eval "$cmd" " (创建openstack用户来访问RabbitMq的资源.)"

    #设置openstack的权限(configuration, write, read)
    cmd='rabbitmqctl set_permissions openstack ".*" ".*" ".*"'
    fn_exec_eval "$cmd" " (配置openstack用户拥有对'/'这个vhost的(配置,写,读)的权限,注:默认用户guest也具有这些权限."

    #生成RabbitMQ的密码报告.
    fn_create_password_report "RabbitMQ" "openstack" "${RABBITMQ_PASSWORD}" "RabbitMQ Admin Account Create." 
    
    #创建标志文件.
    fn_create_tag_file rabbitmq
    unset cmd
}

fn_inst_memcached(){
    #功能:安装并配置Memcached

    fn_check_tag_file memcached
    [ $? -eq 0 ] && return 1

    fn_exec_eval "yum install memcached python-memcached -y"

    #启动服务.
    fn_exec_systemctl "memcached"

    #创建标志文件.
    fn_create_tag_file memcached
}

fn_check_openstack_conf(){
    #功能: 检查etc/openstack.conf中的参数值是否存在可预测的错误.
    #  1.检测控制节点的管理IP,公网IP是否与当前控制节点ifconfig输出一致.
    #    检测非控制节点上ifconfig的输出与etc/hosts中提供的是否一致。
    #  2.检测是否已经将etc/hosts 导入到/etc/hosts 中,没有则导入.
    #  3.检测ping,先ping本机,不通报错退出;接着检查其他节点.
    #  4.检查存储节点上主配置文件中提供的磁盘或分区是否已占用或不存在.

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
            fn_err_log "输入CIDR掩码有误,请确认."
        fi
    }

    #检查etc/hosts
    if [ -s $HOSTS_FILE ]
    then
        grep "\<$CONTROLLER_HOST_NAME\>" $HOSTS_FILE |grep -q "\<$CONTROLLER_MANAGE_IP\>"
        [ $? -eq 0 ] || fn_err_log "发现主配置文件中控制节点的主机名或管理IP与$HOSTS_FILE 中定义的不一致."

        local storage compute
        fn_check_tag_file "storage_node"; storage=$?
        fn_check_tag_file "compute_node"; compute=$?
        if [ $storage -eq 0 -o $compute -eq 0 ]
        then
            #注：
            #   这里实际上是存在问题的,如:本机上配置了:
            #   eth0:10.1.10.10/16   eth1:10.1.11.10/16 ,这样就无法区分那个是管理IP了.
            #   因为:16取的话,网络位取出来是:10.1 ,过滤时就会出现两个IP,就很可能出错.
            #另注:
            #  1.用IP前缀过滤最大可能性为管理IP的IP地址,
            #  2.接着验证CIDR(这里转成了子网掩码),
            #  3.再来验证etc/hosts中提供的IP与可能的管理IP是否一致
            #  4.最后,验证该IP对应的主机名是否与本地设置的一致.
            get_netprefix_and_subnetmask ${CONTROLLER_MANAGE_NET#*/}
            ifconfig |grep "$NetPrefix" |grep "$SubnetMask" |awk 'END{print $2}' |xargs -i{} grep {} $HOSTS_FILE |grep -q "`hostname`"
            [ $? -eq 0 ] || fn_err_log "检查ifconfig输出的管理IP 或 hostname输出的主机名 与$HOSTS_FILE 中定义的不一致,请确认."
        fi

        #导入hosts文件
        grep -q "$CONTROLLER_MANAGE_IP" /etc/hosts || cat $HOSTS_FILE >> /etc/hosts
        #检测本机网络的连通性
        ping -c 2 `hostname` &>/dev/null
        [ $? -eq 0 ] || fn_err_log "ping检测hostname失败,请检查本机IP配置和主机名配置是否正确."

        local retval=0
        for host in `awk '{print $2}' $HOSTS_FILE`
        do
            ping -c 2 $host &>/dev/null
            fn_warn_or_info_log "测试ping主机: $host "
            retval=$((retval+$?))
        done
        [ $retval -eq 0 ] || fn_warn_log "测试各节点主机名失败: $retval 次,请注意此问题."
        fn_exec_sleep '5'
    else 
        fn_err_log "请提供: $HOSTS_FILE,保证各节点主机名映射IP正常."
    fi

    #存储节点检查
    fn_check_tag_file "storage_node"
    if [ $? -eq 0 ]
        then
        for disk in ${CINDER_DISK} ${MANILA_DISK}
        do
            fdisk -l $disk &>/dev/null; retval=$?
            pvs |grep -q "\<$disk\>"; retval=$(($retval+$?))
            [ $retval -eq 1 ] || fn_err_log "配置文件中指定的将分配给cinder或manila使用的磁盘:$disk 不存在或已占用."
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
        #这是存储管理网络的子网掩码,用于配置本地NTP服务器使用.
        echo "$ManageSubnetMask" > /tmp/_ManageNetmask

        #检查管理IP和公网IP
        msg="ifconfig执行结果中没有找到主配置文件中定义的控制节点的管理IP或子网掩码:"
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
            msg="route命令执行结果中没有找到主配置文件中指定的默认网关:$PUBLIC_NET_GW"
            G_msg="$G_msg\n$msg"
            fn_warn_log "$msg"
        fi


        #neutron部分检查
        local PrioverNet_CIDR=${PUBLIC_NET#*/}
        local ControllerPubNet_CIDR=${CONTROLLER_PUBLIC_NET_IP#*/}
        msg="请修改主配置文件中提供网络(Priover Network)的PUBLIC_NET的CIDR值与CONTROLLER_PUBLIC_NET_IP所指定的一致."
        [ $PrioverNet_CIDR -eq $ControllerPubNet_CIDR ] || fn_err_log "$msg"

        #glance部分
        local exist=0
        for img in ${IMG_LIST[*]}
        do
            [ -f "`a=${img#*:}; echo ${a%:*}`" ] && exist=$(($noexist+1))
        done
        [ $exist -eq 0 ] && fn_err_log "主配置文件中定义的image file没有一个存在."

        #yum源打包文件检查
        [ -f $CENTOS72_LOCAL_YUM_SOURCE ] || fn_err_log "没有找到创建本地yum的rpm打包文件($CENTOS72_LOCAL_YUM_SOURCE)."
    fi

    #yum部分
    if [ ! -f $INTERNET_YUM_FILE ]
    then
        msg="没有找到公网yum源安装配置文件($INTERNET_YUM_FILE)."
        G_msg="$G_msg\n$msg"
        fn_warn_log "$msg"
    fi
    [ -f $LOCAL_YUM_FILE ] || fn_err_log "没有找到本地yum源安装配置文件($LOCAL_YUM_FILE)."

    #密码部分
    if [ "$ALL_PASSWORD" == "ChangeMe" ]
    then
        msg="发现所有服务密码将使用默认密码:ChangeMe"
        G_msg="$G_msg\n$msg"
        fn_warn_log "$msg"
    fi

    #模板配置文件部分
    [ -f "$MYCNF_FILE" ] || fn_err_log "没有找到修改过的mariadb模板配置文件:$MYCNF_FILE"
    [ -f "$KEYSTONE_HTTPCONF_FILE" ] || fn_err_log "没有找到修改过的keystone的httpd的模板配置文件:$KEYSTONE_HTTPCONF_FILE"
    [ -f "$DASHBOARD_CONF_FILE" ] || fn_err_log "没有找到修改过的dashboard的模板配置文件:$DASHBOARD_CONF_FILE"
    [ -f "$MONGODB_CONF_FILE" ] || fn_err_log "没有找到修改过的mongodb的模板配置文件:$MONGODB_CONF_FILE"


    if [ -n "$G_msg" ]
    then
        echo -e "\e[33m检查主配置文件($os_CONF_FILE)结果:"; echo -e "$G_msg\e[0m"|nl -n ln
        fn_exec_sleep 10
    fi
    return 0
}

fn_init_node_env(){
    #功能:检查系统环境是否符合安装Openstack-Mitaka的条件.
    #   1.检查系统语言和必须的软件包.
    #   2.检查主配置文件是否存在可预测的错误。
    #   3.导入hosts文件,并进行ping测试主机名
    #   4.非控制节点调用fn_import_os_file函数,读取非控制节点上~/os 文件,获取该节点上的
    #     上网接口的接口名.  
    #   5.检查系统版本是否与CentOS7.2-1511的系统环境相近.
    #     主要查:Kernel=3.10.0-327; python=2.7.5
    #   6.检查系统资源是否符合Controller或Compute节点的最低配置要求.
    #     即:Controller=RAM4G,DISK5G,NIC2; Compute:RAM2G,DISK5G,NIC2
    #   7.检查主机名,并根据配置文件中设定的主机名来修改主机名.
    #     注:修改完主机名后,还需要导入hosts文件内容.
    #   8.修改系统设置:将SELinux修改为仅警告不阻止(permissive) 和 导入允许访问OpenStack服务的firewall规则.
    #   9.检查yum源配置.
    #   10.安装未安装但必须的软件
    #   11.更新系统中所有可更新的软件.
    #   12.初始化admin-token.sh admin-openrc.sh demo-openrc.sh
    #   13.Controller节点将安装并配置mairadb/rabbitmq/memcached.
    #   14.配置NTP服务,(注:Controller:将被配置为NTP服务端,非Controller将为客户端.)

    #注:应该在选择安装节点时,创建节点类型标志文件.
    #创建安装节点是 Controller | Compute | Storage 节点的标志文件.
    fn_create_tag_file "$1"

    fn_check_os_lang_and_soft
    fn_check_openstack_conf

    #检查当前节点若为非控制节点则导入"/root/os",获取上网接口名,并导出此节点的
    #   SLAVE_NODE_HOST_NAME,SLAVE_NODE_MANAGE_IP, 
    #   SLAVE_NODE_PUBLIC_NET_NIC, SLAVE_NODE_PUBLIC_NET_IP,SLAVE_NODE_PUBLIC_NET_GW
    fn_check_tag_file "controller_node" || fn_import_os_file

    fn_check_os_version
    fn_check_os_resource
    fn_modify_os_security_set
    fn_check_yum

    #安装必须的软件:
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

    #初始化admin-token.sh admin-openrc.sh demo-openrc.sh
    fn_init_os_auth_file

    fn_check_tag_file "compute_node"; compute=$?
    fn_check_tag_file "storage_node"; storage=$?
    fn_check_tag_file "controller_node"; controller=$?
    if [ $controller -eq 0 ]
        then
        if [ $compute -eq 0 -o $storage -eq 0 ]
        then
            fn_err_log "请检查当前节点上的节点标志文件,一个节点不建议同时为控制节点 和 计算节点或存储节点."
        fi
        
        #Controller节点将安装并配置mairadb/rabbitmq/memcached.(注:rabbitmq将自动启动,其它需手动启动.)
        fn_inst_mairadb
        fn_inst_rabbitmq
        fn_inst_memcached
    fi

    #配置NTP服务,(注:Controller:将被配置为NTP服务端,非Controller将为客户端.)
    fn_inst_localNTPconfig
    #fn_config_ntp_service

    fn_inst_componet_complete_prompt "Init $1 Successed."
}

#----------------------------[ END - 节点配置]---------------------------------#

#set -o xtrace
fn_init_node_env "$1"
#set +o xtrace
