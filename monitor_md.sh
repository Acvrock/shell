#!/bin/bash

#记录上一次的行数
Last_num_d=/tmp/monitor/lastnum
#日志目录 可以是某目录如：Log_directory=/root/test，或者是多个目录，用空格隔开Log_directory=“/root/test /root/test1”
Log_directorys="/mnt/harddrive/logs/admin/error /mnt/harddrive/logs/seller/error /mnt/harddrive/logs/front/error"
#ERROR log 临时存放目录
Error_log=/tmp/monitor/errorlog

#目录判断
d_judge(){
    [ ! -d $1 ] && mkdir -p $1
}

d_judge $Last_num_d
d_judge $Error_log
for Log_directory in  $Log_directorys ;do
    # 所有日志log文件，除了带 access 的文件，此处的 awk 作用为查出全路径
    for logfile in `ls -1 $Log_directory  |awk '{print i$0}' i=$Log_directory'/'  |grep log |grep -v access` ; do
        #for logfile in `ls $Log_directory |grep log |grep -v access` ; do # 这是查出路径
        #for logfile in `ls $Log_directory` ; do
        # 文件名称不能带斜杠/,所以把文件名转换成不带斜杠的
        logfilemarkfile=`echo $logfile |awk '{gsub("/","-") ; print $0}'`
        #先判断当前日志目录是否为空，为空则直接跳过
        [ ! -s $logfile ] && echo "`date` $logfile is empty" && continue
        #判断记录上一次检查的行数的文件是否存在，不存在则给一个初始值
        [ ! -f "$Last_num_d/$logfilemarkfile" ] && echo 1 > $Last_num_d/$logfilemarkfile
        #将上一次值赋给变量
        last_count=`cat $Last_num_d/$logfilemarkfile`
        #将当前的行数值赋给变量
        current_count=`grep -Fc "" $logfile`
        #判断当前行数跟上一次行数是否相等，相等则退出当前循环
        [ $last_count -eq $current_count ] && echo "`date` $logfile no change" && continue
        #由于日志文件每天都会截断，因此会出现当前行数小于上一次行数的情况，此种情况出现则将上一次行数置1
        [ $last_count -gt $current_count ] && last_count=1
        #截取上一次检查到的行数至当前行数的日志并检索出有ERROR的日志，并重定向到相应的ERROR日志文件
        sed -n "$last_count,$current_count p" $logfile | grep -i ERROR >> $Error_log/$logfilemarkfile && echo "`date` $logfile error " || echo "`date` $logfile changed but no error"
        #判断ERROR日志是否存在且不为空，不为空则说明有错误日志，继而发送报警信息，报警完成后删除错误日志
        [ -s $Error_log/$logfilemarkfile ] && echo -e "$HOSTNAME \n `cat $Error_log/$logfilemarkfile`" | mail -s "$logfile ERROR" XXXXXXXXX@qq.com  && rm -rf $Error_log/$logfilemarkfile
        #结束本次操作之后把当前的行号作为下一次检索的last number
        echo $current_count > $Last_num_d/$logfilemarkfile
    done
done


