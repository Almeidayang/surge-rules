#!/bin/sh

if [ "$1" = "--help" ]; then
  cat << EOF
$0 网卡名称
--help 打印帮助菜单
EOF
  exit 0
fi

if [ -z "$1" ]; then
  if ip a >/dev/null 2>&1 ; then
    interface=$(ip a | grep mtu | awk -F ':' '{print $2}' | head -n 2 | tail -n +2 | awk -F ' ' '{print $1}')
  else
    interface=eth0
  fi
else
  interface=$1
fi

cd /root || exit
killall caddy 2>/dev/null
nohup caddy file-server --browse --listen :41955 >/dev/null 2>&1 &

while true; do
  # 加上 head -n 1 确保无论几个核心，都只抓取第一行总计信息
  CPU_USAGE=$(top -b -n 1 | grep -i 'Cpu' | head -n 1 | awk '{print $2}' | cut -f 1 -d "%" | sed 's/\..*//g')
  CPU_SYS=$(top -b -n 1 | grep -i 'Cpu' | head -n 1 | awk '{print $4}' | cut -f 1 -d "%" | sed 's/\..*//g')
  CPU=$(expr ${CPU_USAGE:-0} + ${CPU_SYS:-0} 2>/dev/null || echo 0)
  
  # 暴力清除可能混入的换行符和空格，确保严格对齐
  CPU=$(echo "$CPU" | tr -d '[:space:]')

  MEM_TOTAL=$(free -m | awk -F '[ :]+' 'NR==2{print $2}')
  MEM_USER=$(free -m | awk -F '[ :]+' 'NR==2{print $3}')
  MEM=$(expr ${MEM_USER:-0} \* 100 / ${MEM_TOTAL:-1} 2>/dev/null || echo 0)
  # 同样清理内存的换行符
  MEM=$(echo "$MEM" | tr -d '[:space:]')

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

  echo "网卡: $interface | 发送: ${NIC_TX_ALL} 接收: ${NIC_RX_ALL} 总计: ${NIC_ALL} | CPU: ${CPU}% 内存: ${MEM}%"

  echo "{" > /root/traffic
  echo "  \"in\": \"${NIC_RX_ALL}\"," >> /root/traffic
  echo "  \"out\": \"${NIC_TX_ALL}\"," >> /root/traffic
  echo "  \"all\": \"${NIC_ALL}\"," >> /root/traffic
  echo "  \"cpu\": \"${CPU}%\"," >> /root/traffic
  echo "  \"mem\": \"${MEM}%\"," >> /root/traffic
  echo "  \"last_exec_time\": \"$(date '+%Y-%m-%d %H:%M:%S')\"" >> /root/traffic
  echo "}" >> /root/traffic

  sleep 10
done
