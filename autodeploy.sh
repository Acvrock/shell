#!/bin/bash

#该脚本实现本机编译打包，上传编译包到服务器，重启服务器 tomcat 功能
#################################################################################
#编译相关信息
#备份目录
backup_d=/Working/packagebackup
#项目目录
project_d=/Working/project
#项目名称列表
projectNames="project-seller project-admin"
#临时目录
temp_d=/tmp/autodeploy
#本次编译标示
build_time=$(date +%Y-%m-%d_%H-%M-%S)

#################################################################################
#SFTP 配置信息
#用户名
USER=root
#密码
PASSWORD=
#SFTP 目录
DESDIR=/root/packagebackup
# SFTP 服务器 IP
IP=192.168.1.2
#################################################################################

#################################################################################
#部署配置
#tomcat 路径，顺序和上面的项目名称对应
tomcat_paths="/usr/apache-tomcat-9.0.0.M1-1 /usr/apache-tomcat-9.0.0.M1-2"
#################################################################################

#判断目录是否存在，如果不存在就创建目录
d_judge(){
    [ ! -d $1 ] && mkdir -p $1
}

d_judge $backup_d
d_judge $temp_d

#发送全量 war 到服务器
send_war(){
## 发送文件到远程服务器 do send war to test server
for projectName in  $projectNames ;do
    #发送文件 (关键部分）
lftp -u ${USER},${PASSWORD} sftp://${IP} <<EOF
cd ${DESDIR}/
mkdir ${build_time}
cd ${build_time}
put $temp_d/$projectName.war
by
EOF
echo "发送全量 war 文件到服务器成功，路径：${DESDIR}/${build_time}/$projectName.war"
done
}

#上传文件完毕，重启tomcat
restart_tomcat(){

projectNamesArray=($projectNames)
tomcatPathsArray=($tomcat_paths)
length=${#projectNamesArray[@]}

for ((i=0; i<$length; i++))
do
ssh ${USER}@${IP} << eeooff

"ps" -ef|"grep" ${tomcatPathsArray[$i]}/bin|"grep" java|"awk" '{print \$2}'
${tomcatPathsArray[$i]}/bin/shutdown.sh >/dev/null
"sleep" 2s
"ps" -ef|"grep" ${tomcatPathsArray[$i]}/bin|"grep" tomcat|"awk" '{print \$2}'|"xargs" kill -9  >/dev/null
"rm" -rf ${tomcatPathsArray[$i]}/webapps/*
"sleep" 1s
"cp" ${DESDIR}/${build_time}/${projectNamesArray[$i]}.war ${tomcatPathsArray[$i]}/webapps/
"sleep" 5s
"nohup" ${tomcatPathsArray[$i]}/bin/startup.sh &
if [ $? -eq 0 ]; then
"echo" "启动tomcat 成功 ${tomcatPathsArray[$i]} "
else
"echo" "启动tomcat 失败 ${tomcatPathsArray[$i]} "
"exit" 1
fi

exit
eeooff
done
}

#备份全量 war 文件到本机的备份目录，以便下次增量匹配
backup_war(){
#生成差异包成功后，把本次编译好的包拷贝到备份目录
out_d=$backup_d/$build_time
d_judge $out_d
for projectName in  $projectNames ;do
#echo "$projectName"
cp $temp_d/$projectName.war $out_d/
cp $temp_d/$projectName.patch $out_d/
if [ $? -eq 0 ]; then
echo "备份 $projectName.war、$projectName.patch  到$out_d/ 成功"
else
echo "备份 $projectName.war、$projectName.patch 到$out_d/ 失败"
fi
done
}

#拷贝 war 文件到本机的临时目录
copy_war_to_out_d(){
for projectName in  $projectNames ;do
cp $project_d/$projectName/target/$projectName.war $temp_d/
if [ $? -eq 0 ]; then
echo "拷贝 $projectName.war 到$temp_d/ 成功"
else
echo "拷贝 $projectName.war 到$temp_d/ 失败"
fi
done
}

#发送增量补丁到服务器
send_patchfile(){
# 发送文件到远程服务器 do send war to test server
for projectName in  $projectNames ;do
#发送文件 (关键部分）
lftp -u ${USER},${PASSWORD} sftp://${IP} <<EOF
cd ${DESDIR}/
mkdir ${build_time}
cd ${build_time}
put $temp_d/$projectName.patch
by
EOF
echo "发送增量 patch 到服务器成功，路径：${DESDIR}/${build_time}/$projectName.patch"
done
}

#生成差异包
build_patchfile(){
for projectName in  $projectNames ;do
bsdiff $backup_d/$local_last_d/$projectName.war $temp_d/$projectName.war $temp_d/$projectName.patch
if [ $? -eq 0 ]; then
echo "在本地生成差异包成功 $local_last_d/$projectName.war >> $projectName.patch "
else
echo "在本地生成差异包失败 $local_last_d/$projectName.war >> $projectName.patch "
exit 1
fi
done
}

#在服务器进行补丁合并，生成全量 war
patch_warfile(){
# 远程部署 todo
ssh ${USER}@${IP} << eeooff
for projectName in  $projectNames ;do
"bspatch" ${DESDIR}/${local_last_d}/\$projectName.war ${DESDIR}/${build_time}/\$projectName.war ${DESDIR}/${build_time}/\$projectName.patch
echo "在服务器上合并差异包成功：${local_last_d}/$projectName.war+${build_time}/$projectName.patch=${build_time}/$projectName.war"
done
exit
eeooff
echo done!
}

#清理临时文件
clear_d(){
# clear temp dir 需要特别慎重检查
rm -rf ${temp_d}
#清理project
cd $project_d && mvn clean >/dev/null
echo "清理文件成功"
}


echo "开始编译源码"
#编译程序
cd $project_d && mvn clean -P package -Dmaven.compile.fork=true -Dmaven.test.skip=true 1>$temp_d/mavenout 2>$temp_d/mavenerr
#打印一下编译结果
awk '$4=="SUCCESS" {print $0}' $temp_d/mavenout
#判断编译是否成功
awk '$2=="BUILD" && $3=="SUCCESS" {print $0}' $temp_d/mavenout | grep "BUILD SUCCES" && issuccess=true

if $issuccess; then
    #获取远程存在的备份 war 包
    server_backup_d=$(ssh ${USER}@${IP}  << eeooff
                        "ls" -lt "$DESDIR" | "grep" ^d | "awk" '{print \$9}'
                        exit
                    eeooff)
    
    #取第一个本地备份包，判断远程备份目录里是否存在
    local_last_d=$(ls -lt $backup_d | grep ^d | head -n 1 | awk '{print $9}')
    isresult=$(echo $server_backup_d | grep "${local_last_d}")
    if [ ! -n "$isresult" ];then
            echo "本地没有备份文件 准备直接上传 war 包"
            echo "拷贝编译好的war到临时目录"
            copy_war_to_out_d
            echo "发送全量war包到服务器"
            send_war
            echo "重启tomcat"
            restart_tomcat
            echo "备份war文件"
            backup_war
    fi
    echo "拷贝编译好的war到临时目录"
    copy_war_to_out_d
    echo "开始生成差异包"
    build_patchfile
    echo "发送差异包到服务器"
    send_patchfile
    echo "由差异包生成安装包"
    patch_warfile
    echo "重启tomcat服务器"
    restart_tomcat
    echo "备份war文件"
    backup_war
    echo "清理临时文件"
    clear_d
    exit 1
else
    echo "Maven 编译失败 "
    exit 1
fi


