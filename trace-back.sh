#!/bin/bash

# apt -y install unzip

# install nexttrace
if [ ! -f "/usr/local/bin/nexttrace" ]; then
    curl nxtrace.org/nt | bash
fi

## start to use nexttrace

next() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}


ip_list=(219.141.147.210 202.106.50.1 221.179.155.161 202.96.209.133 210.22.97.1 211.136.112.200 14.116.138.218 210.21.196.6 120.196.165.24 61.139.2.69 119.6.6.6 211.137.96.205)
ip_addr=(北京电信 北京联通 北京移动 上海电信 上海联通 上海移动 深圳电信 深圳联通 深圳移动 成都电信 成都联通 成都移动)

ip_len=${#ip_list[@]}
for i in $(seq 0 $((ip_len - 1)))
do
	echo ${ip_addr[$i]}
	nexttrace -M ${ip_list[$i]}
	next
done
