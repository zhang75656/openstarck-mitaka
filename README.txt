
WeZeStack编写的初衷就是希望能够快捷的帮助希望学习OpenStack的人,
便捷的安装,来体验OpenStack的效果,为进一步深入学习做一个好的铺垫.

WeZeStack采用最简单易用的Shell编写,这主要是出于它更容易调试,更容易
让Linux学习者方便的改写,并加入自己需要的功能,由于本人对OpenStack
了解甚少,此脚本的原本是另一位OpenStack高手:WuYuLiang 所做,这一版本是我对原本
的大量修改后的产物,但原版的思想依然存在. 我非常非常希望能有更多
对OpenStack感兴趣的同仁加入,用最简单易懂的方式向OpenStack的初学者
提供一点指引。

原作者脚本和教程网址:
http://blog.csdn.net/wylfengyujiancheng/article/details/51137707

WeZeStack的整体架构:
D:\MITAKA\ZCF
│  openstack.sh		#这是整个安装脚本的入口脚本.
│  README.txt
│
├─bin									#bin是存放所有安装脚本的目录.
│  │  function							#此脚本是通用函数的集合
│  │  modify_mysql_secure_installation  #它是用来初始化Mariadb的脚本,这是Mariadb默认的初始化脚本,
│  │									#我对它做了一点修改,让它可以支持传参并自动完成Mariadb的初始化.
│  └─sh									#此为存放每个模块的安装脚本.
│          0_check_and_config_node_system.sh		#它是用来检查节点环境是否符合安装要求,并初始化节点的脚本.
│          1_install_keystone.sh
│          2_install_glance.sh
│          3_install_nova.sh
│          4_install_neutron.sh
│          5_3-4-9_install_compute_node.sh			#这是安装计算节点的脚本,
													#它主要安装:nova-compute,neutron-linuxbridge-agent和ceilometer-agent.
													#由于不能定义非控制节点的外网接口是哪个,因此,需要在非控制节点上创建os文件,
													#来记录哪个接口是用来连接物理网络的,若没有os文件,则需要从脚本检查到
													#的接口列表中手动选择哪个是外网接口。才能继续。
│          5_install_dashboard.sh
│          6_prepare_create_vm.sh					#这是要在控制节点上初始化VM创建的基础环境的脚本,
													#主要:完成创建cirros-flavor,keypair,安全组,桥(虚拟交换机)
│          7_install_cinder.sh
│          8_install_manila.sh
│          9_install_ceilometer.sh
│          10_7-8-9_install_storage_node.sh			#它是安装存储节点的脚本,主要安装Cinder和Manila
│          10_install_heat.sh						#它是安装heat的脚本,heat是支持集成容器VM的OpenStack组件.
│
├─etc
│  │  admin-openrc.sh
│  │  admin-token.sh
│  │  demo-openrc.sh				#这三个脚本,是执行openstack命令时,需要导出的用户名,密码,keystoneURL等认证信息的脚本.
│  │  hosts							#文件是:/etc/hosts文件的副本, 【需要修改】
│  │  local-openstack.repo
│  │  openstack.repo				#这两个repo文件,是yum源配置文件; local-openstack是采用本地yum源时使用.
									#这个会在0_check_and_config_node_system.sh中检查当前主机是否能直接连入Internet,来决定
									#是采用公网源,还是本地yum源. 不过我推荐使用本地yum源,可能问题会少点.
│  │  local_settings				#此配置文件是"dashboard"的配置文件的副本,脚本会对它内部的标记进行修改,然后,覆盖安装的配置文件.
│  │  logo.txt						#这是此脚本的logo文件,呵呵,我自己设计的,有点丑,不过先凑活用吧.
│  │  mariadb_openstack.cnf			#这是mariadb的配置文件模板,脚本会自动修改它内部的标记,并将它放到/etc/my.conf.d/下面.
│  │  mongod.conf					#这是Mongodb的配置文件副本,内部标记也会被替换,并覆盖安装的配置文件.
│  │  openstack.conf				#【这是此安装脚本的主配置文件,需要修改!!!! 若修改的不对,初始化节点的脚本会检查出一些可能的错误.】
│  │  proxy.conf					#这是Linux上配置代理方式上网的配置文件,若需要则可修改它,并将主配置文件中使用代理的标志设置为True.
│  │  vimrc							#这是一个不重要的配置文件,它是vim的配置文件,主要是开启vim的一些特性,方便查看脚本而已;
									#若需要可将它: mv  vimrc  ~/.vimrc  ,在启动vim即可生效.
│  │  wsgi-keystone.conf			#这是keystone的配置httpd的虚拟主机的配置文件,它将被直接放到/etc/httpd/conf.d/下.
│  │
│  ├─firewalld						#在CentOS7.2上默认采用了firewalld来做为默认防火墙,它支持管理iptables,ip6tables,ebtables,
									#网上说功能很强大,我对它了解有限,个人感觉它比iptables更易用.并且规则添加更便捷了.
									#查看规则依然可以使用iptables来看,或使用firewall-cmd来查看.
						#下面这些xml都是自定义的firewall服务,firewall中服务指:协议,端口,模块(如iptables时使用的ftp模块),源目IP的组合.
						#但一般定义服务时,很少用到模块和源目IP. 下这些自定义服务,也全部仅定义了协议和端口.
						#若需要修改它,可参看/usr/lib/firewalld/下的文件,这是firewall默认载入规则和服务定义的配置文件根目录.
						#xmlschema: 此目录是firewall中各种配置文件如何编写的规则定义文件的目录.
│  │      os_alarming.xml			#它是alarm(OpenStack的监控报警)服务的定义文件.
│  │      os_ceilometer.xml
│  │      os_cinder.xml
│  │      os_glance.xml
│  │      os_heat.xml
│  │      os_keystone.xml
│  │      os_manila.xml
│  │      os_mariadb.xml
│  │      os_memcached.xml
│  │      os_mongodb.xml
│  │      os_neutron.xml
│  │      os_nova.xml
│  │      os_otv.xml				#此服务不是OpenStack的服务,它是一种大二层技术,这里仅为了统一才这样命名,由于此安装脚本将使用
									#VxLAN做为隧道机制来传输VM到neutron-server的流量,并完成获取IP,连入物理网络的功能.
									#这里需要注意: OpenStack默认采用了Cisco私有协议OTV作为封装,而没有直接使用VxLAN来封装传输流量.
│  │      os_vxlan.xml				#VxLAN与OTV类似,都是包裹二层帧,实现跨三层IP网络传输二层帧,实现二层互联的技术.但他们采用的通信端口不同.
│  │      os_rabbitmq.xml
│  │      public.xml				#这是默认区域的配置文件,是上面所有服务添加后,系统自动生成的配置文件,我仅将它拿来做为
									#快速添加规则的模板文件.它并非必须.
│  │
│  ├─openrc_template				#这是OpenStack的openrc文件的模板存放处.
│  │      admin-openrc.sh
│  │      admin-token.sh
│  │      demo-openrc.sh
│  │
│  └─rpm-gpg
│          RPM-GPG-KEY-CentOS-SIG-Cloud
│          RPM-GPG-KEY-EPEL-7
│
├─resource							#这是创建本地yum源所需要的所有rpm包的打包文件 和 cirros镜像.
│      Mitaka-CentOS7.2-0430.tar.gz
│      cirros-0.3.4-x86_64-disk.img
│
└─tmp
│      os.sh			#这是检查OpenStack服务是否启动的脚本,若你的电脑,运行VM很慢,启动OpenStack服务时,总是出错,可使用它.
						#因为,我使用我的笔记本安装OpenStack时,经常因为性能差,导致OpenStack服务启动超时,而失败,但在公司的服务器上
						#却从来没有出现过启动服务失败的情况.
│      addconn.sh 		#这是修改IP和主机名的简单脚本


以上是这个WeZeStack的脚本概述.

WeZeStack存在的缺陷：
1. 在0_check_and_config_node_system.sh这个脚本中,检查etc/openstack.conf 主配置文件时,还存在问题,
   暂时没有解决.
   问题是：通过子网掩码计算网络段,这部分没有完全做到准确,目前仅做了简单实现,还存在如下问题:
   如:本机上配置了:
      eth0:10.1.10.10/16   eth1:10.1.11.10/16 ,这样就无法区分那个是管理IP了.
      因为:16取的话,网络位取出来是:10.1 ,过滤时就会出现两个IP,就很可能出错.
2. fn_inst_componet_complete_prompt	
	它主要使用awk来对传入的英文字符串加边框,实现一个美化的作用.
	但由于awk处理汉字是,一个汉字等同与一个英文字母,故导致汉字处理时,加边框会出错.
	现在我还没有办法判断传入的字符串是汉字还是英文字符, 或者说,不知道如何让awk知道汉字处理时
	要当成2个字符处理。
	
3. 由于本人对OpenStack确实了解有效,没能做出更多的定制化实现.这也是此脚本往后将改进的地方。
4. 此安装脚本无法采用经典的三节点安装方式进行,主因是官方文档没有提供这样的参考,还需要自行摸索.

WeZeStack主要模块安装脚本介绍:
0_check_and_config_node_system.sh
	此脚本将接受入口脚本传入的参数, 来设定当前即将安装的节点是控制/计算/存储节点,
	若选择安装控制节点,则传入的参数就为"controller_node"即控制节点,然后,脚本会调用function中的fn_create_tag_file
	来创建当前节点的标志文件,接着开始根据预定的操作安装控制节点需要初始化安装的所有软件和需要做的操作.
	注:
		所有节点都将做以下事情：
		1.检查系统语言和必须的软件包.
        2.检查主配置文件是否存在可预测的错误。
        3.导入hosts文件,并进行ping测试主机名
        4.非控制节点调用fn_import_os_file函数,读取非控制节点上~/os 文件,获取该节点上的
          上网接口的接口名.  
        5.检查系统版本是否与CentOS7.2-1511的系统环境相近.
          主要查:Kernel=3.10.0-327; python=2.7.5
        6.检查系统资源是否符合Controller或Compute节点的最低配置要求.
          即:Controller=RAM4G,DISK5G,NIC2; Compute:RAM2G,DISK5G,NIC2
        7.检查主机名,并根据配置文件中设定的主机名来修改主机名.
          注:修改完主机名后,还需要导入hosts文件内容.
        8.修改系统设置:将SELinux修改为仅警告不阻止(permissive) 和 导入允许访问OpenStack服务的firewall规则.
        9.检查yum源配置.
        10.安装未安装但必须的软件
        11.更新系统中所有可更新的软件.
        12.初始化admin-token.sh admin-openrc.sh demo-openrc.sh
	仅这两件事控制节点做的与其他节点不同.
        13.Controller节点将安装并配置mairadb/rabbitmq/memcached.
        14.配置NTP服务,(注:Controller:将被配置为NTP服务端,非Controller将为客户端.)

function:
	此脚本是一个函数库脚本.它主要实现了以下函数:
	1. log生成函数.
		fn_warn_or_info_log : 主要功能是判断上条指令执行是否成功,成功则调用fn_info_log,否则调用fn_warn_log
		fn_err_or_info_log : 功能类似上面的.区别是,fn_err_log执行后,后调用exit 1, 退出脚本.
		fn_info_log
		fn_warn_log
		fn_err_log
		fn_log
	2. 统一执行命令的调用函数.
		fn_exec_eval : 它接收-w:即调用fn_warn_or_info_log来判断执行是否成功,默认采用fn_err_or_info_log
						同时,它会检查若当前执行的是yum install则,判断是否需要使用代理.
	3. 统一启动服务的函数:
		fn_exec_systemctl : 它主要做三件事:
							1. 创建开启自启动. 2.启动服务. 3.等待5秒,尝试重启,并检查重启是否成功.若重启失败则退出.
	4. 统一创建数据库的函数:
		fn_create_db : 它主要完成各组件数据库的创建并授权,然后,导出"SHOW_数据库名_TABLES"为环境变量,
						当执行完数据库同步命令后,使用fn_exec_eval "$SHOW_数据库名_TABLES" 来显示导入的数据表.
	5. 统一创建service/endpoint/domain/project/role/user和对user的授权的函数:
		fn_create_service_and_endpoint	:它主要完成检查是否已存在将要创建的service和endpoint,若不存在则创建.
		fn_create_domain_project_role	:它主要完成检查是否已存在要创建的domain, project, role, 若不存在则创建.
		fn_create_user_and_grant	:它主要完成检查 用户是否存在,用户所属于的domain是否存在,将授权给user的role是否
									存在,以及role所属的project是否存在,若检查正常,则创建user并授权.
	6. 统一执行openstack-config命令的函数:
		fn_check_file_and_backup	:执行openstack-config修改配置文件前,需要先调用此函数完成配置文件的备份并导出
									环境变量: SRV_CONF_FILE ,来保存当前即将被修改的配置文件.
		fn_exec_openstack-config 	:它就是实际执行openstack-config命令来修改服务配置文件的函数.
	7. 统一提示安装成功与否的提示函数:
		fn_inst_componet_complete_prompt	:它主要使用awk来对传入的英文字符串加边框,实现一个美化的作用.
											注: 由于awk处理汉字是,一个汉字等同与一个英文字母,故导致汉字处理时,加边框会出错.
	8. 其它的功能函数:
		fn_exec_sleep
		fn_create_password_report	:此函数主要完成涉及到密码的操作,将该操作记录到: $HOME/openstack_passwd_report.txt 这里.
		fn_create_tag_file
		fn_check_tag_file
		fn_check_auth_var	:此函数主要完成: 检查当前是否导入了openrc认证文件,以便后续执行openstack-config 或 openstack等命令是不出错.
		
下面这些脚本都需要在控制节点上执行安装动作.
1_install_keystone.sh
2_install_glance.sh
3_install_nova.sh
4_install_neutron.sh
5_install_dashboard.sh
6_prepare_create_vm.sh
7_install_cinder.sh
8_install_manila.sh
9_install_ceilometer.sh
10_install_heat.sh

这两个为非控制节点需要执行的脚本.
计算和存储节点安装需要注意:
	在安装计算或存储节点时,需要事先提供os文件,以便可自动获取外网接口名.
	os文件的内容：
		echo "外网接口名" > ~/os
		
5_3-4-9_install_compute_node.sh
	计算节点安装需要注意:
	firewall这块需要特别注意,若你想创建超过4个VM,你需要修改/usr/lib/firewalld/services/vnc-server.xml
	因为,脚本默认使用这个服务配置文件,来添加firewall的富规则,它里面默认只开启了5900~5903这4个端口,所以
	你若想同时启动多个VM,就需要多放行以下端口了。
10_7-8-9_install_storage_node.sh


时间: 2016-7-19
作者: ZhangChaoFeng
