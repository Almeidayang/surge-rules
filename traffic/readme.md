依据https://surge.tel/09/2549/, 做了修改,替换成 vnstat 统计的流量

通过将原来粗暴读取系统网卡文件的逻辑替换为 `vnstat`，你可以很方便且更精准地统计**本月**的服务器流量。这不仅避免了 VPS 重启导致流量统计清零的问题，也简化了脚本中复杂的单位换算代码。

下面是为修改好的 `traffic.sh` 脚本，以及相关的部署说明：

### 第一步：确保 VPS 上已安装并运行 vnstat
`vnstat` 是一款专门用于记录网络流量的工具。如果你的服务器还没有安装，请先执行以下命令安装并启动它：
```bash
sudo apt update
sudo apt install vnstat -y
sudo systemctl enable --now vnstat
```
*(注：`vnstat` 安装后开始收集流量，所以它不能追溯你安装之前的用量，安装完之后的流量都会被按月精准记录。)*

### 第二步：修改运行脚本
原教程里的文件是 `/root/traffic.sh`。请将里面的内容清空，替换为下面这份经过 `vnstat` 改造的代码：

```bash
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
```

### 第三步：重启服务使之生效
修改并保存 `traffic.sh` 后，你需要重启守护进程使新的脚本生效。执行：

```bash
# 重新加载并重启 traffic 服务
sudo systemctl daemon-reload
sudo systemctl restart traffic

# 查看服务是否在正常运行
sudo systemctl status traffic
```

### 主要更改点说明：
1. **去掉了繁杂的 `calculate` 运算函数及写入本地 `tx/rx` 缓存记录的逻辑**：由 `vnstat` 的持久化数据代替，直接输出当月网络传输量。
2. **单位兼容修复 (`sed 's/iB/B/g'`)**：因为 vnstat 默认输出带有 `GiB` 和 `MiB`，但原版 Surge 面板的 JS 脚本（`CatVPS.js`）往往是通过匹配 `GB` / `MB` 进行换算的。这一步能保证在 Surge 里完美显示并正确计算月剩余流量。
3. **补充了错误捕获**：稍微优化了获取 `ip a` 、`top` 和 `free` 信息时可能引发的报错信息泄露，让后台服务更稳定运行。
