#!/bin/sh

if [ "$1" == "--help" ];then
  cat << EOF
$0 网卡名称
--help 打印帮助菜单
EOF
  exit 0
fi

# 自动获取网卡名称逻辑
if [ -z "$1" ];then
  if ip a >/dev/null 2>&1 ; then
    interface=$(ip a | grep mtu | awk -F ':' '{print $2}' | head -n 2 | tail -n +2 | awk -F ' ' '{print $1}')
  else
    interface=eth0
  fi
else
  interface=$1
fi

# 后台启动 caddy（注意：原教程默认端口是 49155，如果你的 Surge 配置写的是 41955，请把这里改成 :41955）
nohup caddy file-server --browse --listen :49155 >/dev/null 2>&1 &

while true; do
  # 1. 保持原有的 CPU / 内存使用率计算逻辑
  CPU_USAGE=$(top -b -n 1 | grep Cpu | awk '{print $2}' | cut -f 1 -d "%" | sed 's/\..*//g')
  CPU_SYS=$(top -b -n 1 | grep Cpu | awk '{print $4}' | cut -f 1 -d "%" | sed 's/\..*//g')
  CPU=$(expr $CPU_USAGE + $CPU_SYS 2>/dev/null || echo 0)
  
  MEM_TOTAL=$(free -m | awk -F '[ :]+' 'NR==2{print $2}')
  MEM_USER=$(free -m | awk -F '[ :]+' 'NR==2{print $3}')
  MEM=$(expr $MEM_USER \* 100 / $MEM_TOTAL 2>/dev/null || echo 0)

  # 2. 使用 vnstat 获取当前月的流量统计
  # --oneline 格式中，分号分隔的第9、10、11列分别是本月的: 接收(rx)、发送(tx)、总流量(total)
  VNSTAT_LINE=$(vnstat -i "$interface" --oneline 2>/dev/null)
  
  if [ -n "$VNSTAT_LINE" ]; then
    # sed 's/iB/B/g' 主要是将 GiB, MiB 转换为 GB, MB，防止 Surge 的 JS 脚本因不兼容带 'i' 的单位而显示错误
    NIC_RX_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $9}' | sed 's/iB/B/g')
    NIC_TX_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $10}' | sed 's/iB/B/g')
    NIC_ALL=$(echo "$VNSTAT_LINE" | awk -F ';' '{print $11}' | sed 's/iB/B/g')
  else
    # 如果 vnstat 尚未生成数据或获取失败时的默认值
    NIC_RX_ALL="0 B"
    NIC_TX_ALL="0 B"
    NIC_ALL="0 B"
  fi

  clear
  echo "网卡流量监控 (vnstat 本月流量统计)"
  echo "----------------------------------------"
  echo "网卡: $interface"
  echo "发送: ${NIC_TX_ALL}  接收: ${NIC_RX_ALL}  总流量: ${NIC_ALL}"
  echo "CPU使用率: ${CPU}%  内存使用率: ${MEM}%"

  # 3. 输出 JSON 文件供 Surge 通过 Caddy 下载读取
  echo "{" > ./traffic
  echo "  \"in\": \"${NIC_RX_ALL}\"," >> ./traffic
  echo "  \"out\": \"${NIC_TX_ALL}\"," >> ./traffic
  echo "  \"all\": \"${NIC_ALL}\"," >> ./traffic
  echo "  \"cpu\": \"${CPU}%\"," >> ./traffic
  echo "  \"mem\": \"${MEM}%\"," >> ./traffic
  echo "  \"last_exec_time\": \"$(date '+%Y-%m-%d %H:%M:%S')\"" >> ./traffic
  echo "}" >> ./traffic

  # 休眠 10 秒钟后进入下一次刷新
  sleep 10
done
