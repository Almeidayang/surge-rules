#!/bin/bash

if [ "$1" = "--help" ]; then
  cat << EOF
$0 网卡名称
--help 打印帮助菜单
EOF
  exit 0
fi

if  [ -z "$1" ]; then
  if ip a >/dev/null 2>&1 ; then
    interface=$(ip a | grep mtu | awk -F ':' '{print $2}' | head -n 2 | tail -n +2 | awk -F ' ' '{print $1}')
  else
    interface=eth0
  fi
else
  interface=$1
fi

# 确保工作目录在 /root，这样 caddy 才能准确暴露 /root 下的 traffic 文件
# cd /root || exit

# 杀掉可能卡住占用端口的旧 caddy 进程
# killall caddy 2>/dev/null

# traffic 文件目录（不再放 /root）
TRAFFIC_DIR="/var/www"
TRAFFIC_FILE="${TRAFFIC_DIR}/traffic"

# 确保目录存在
mkdir -p "$TRAFFIC_DIR"

# 启动 caddy 服务
# nohup caddy file-server --browse --listen :41955 >/dev/null 2>&1 &
# 脚本只负责写 /root/traffic，Caddy 负责提供文件服务。
while true; do
  #CPU_USAGE=$(top -b -n 1 | grep Cpu | awk '{print $2}' | cut -f 1 -d "%" | sed 's/\..*//g')
  #CPU_SYS=$(top -b -n 1 | grep Cpu | awk '{print $4}' | cut -f 1 -d "%" | sed 's/\..*//g')
  #CPU=$(expr ${CPU_USAGE:-0} + ${CPU_SYS:-0} 2>/dev/null || echo 0)
  #CPU_USER=$(top -b -n1 | grep "Cpu" | awk -F',' '{print $1}' | awk '{print int($2)}')
  #CPU_SYS=$(top -b -n1 | grep "Cpu" | awk -F',' '{print $2}' | awk '{print int($1)}')
  #CPU=$((CPU_USER + CPU_SYS))

  CPU_LINE=$(top -b -n1 | grep "Cpu")

  # 提取 user 和 sys 的整数部分（不会出现两行）
  CPU_USER=$(echo "$CPU_LINE" | awk -F',' '{print int($1)}')
  CPU_SYS=$(echo "$CPU_LINE" | awk -F',' '{print int($2)}')

  # 如果为空则设为 0
  CPU_USER=${CPU_USER:-0}
  CPU_SYS=${CPU_SYS:-0}

  # 计算 CPU
  CPU=$((CPU_USER + CPU_SYS))

  #强制去掉所有不可见字符
  CPU=$(echo "$CPU" | tr -d '\n' | tr -d '\r')


  MEM_TOTAL=$(free -m | awk -F '[ :]+' 'NR==2{print $2}')
  MEM_USER=$(free -m | awk -F '[ :]+' 'NR==2{print $3}')
  MEM=$(expr ${MEM_USER:-0} \* 100 / ${MEM_TOTAL:-1} 2>/dev/null || echo 0)

  VNSTAT_LINE=$(vnstat -i "$interface" --oneline 2>/dev/null)

  if [ -n "$VNSTAT_LINE" ]; then
    NIC_RX_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $9}' | sed 's/iB/B/g')
    NIC_TX_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $10}' | sed 's/iB/B/g')
    NIC_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $11}' | sed 's/iB/B/g')
  else
    NIC_RX_ALL="0 B"
    NIC_TX_ALL="0 B"
    NIC_ALL="0 B"
  fi

  # 去掉了 clear 避免产生 TERM environment 报错日志
  #echo "网卡: $interface | 发送: ${NIC_TX_ALL} 接收: ${NIC_RX_ALL} 总计: ${NIC_ALL} | CPU: ${CPU}% 内存: ${MEM}%"
  printf "网卡: %s | 发送: %s 接收: %s 总计: %s | CPU: %s%% 内存: %s%%\n" \
  "$interface" "$NIC_TX_ALL" "$NIC_RX_ALL" "$NIC_ALL" "$CPU" "$MEM"

  # 强制写入绝对路径 /root/traffic
  cat << EOF > "$TRAFFIC_FILE"
{
  "in": "${NIC_RX_ALL}",
  "out": "${NIC_TX_ALL}",
  "all": "${NIC_ALL}",
  "cpu": "${CPU}%",
  "mem": "${MEM}%",
  "last_exec_time": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF


  sleep 10
done
