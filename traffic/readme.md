依据https://surge.tel/09/2549/, 做了修改,替换成 vnstat 统计的流量

其中的步骤也做必要的记录:

#### apt 软件源列表并安装 Caddy
apt update
apt install caddy
### 编写服务
vim /etc/systemd/system/traffic.service

将下面内容粘贴进去后保存

```[Unit]
Description=traffic
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/
ExecStart=/root/traffic.sh
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=multi-user.target
```

### 编写运行程序
vim /root/traffice.sh

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

```#!/bin/sh

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
```
说明：此代码是通过VPS的49155端口进行监控，请确保该端口的开放，如果你熟悉代码，也可以根据自己需要进行修改

运行
进行完上述步骤后，执行下面指令运行

systemctl enable --now traffic

可以通过 bash traffic.sh 来直接运行
通过 systemctl status traffic 来查看服务状态
如果发现出来的时间不对，可以通过 timedatectl set-timezone Asia/Shanghai 来将vps时区调整为东八区。

### 第三步：重启服务使之生效
修改并保存 `traffic.sh` 后，你需要重启守护进程使新的脚本生效。执行：

```bash
# 重新加载并重启 traffic 服务
sudo systemctl daemon-reload
sudo systemctl restart traffic

# 查看服务是否在正常运行
sudo systemctl status traffic
```
Surge模块安装
将下面内容复制到本地模块中：
```
#!name=CatVPS
#!desc=监控VPS流量信息和处理器、内存占用情况
#!author= 面板和脚本部分@wuhu_zzz VPS端部分 @ATRI0828 由 @整点猫咪 进行整理
#!howto=将模块内容复制到本地后根据自己VPS IP地址及端口修改 http://127.0.0.1:49155/traffic 部分进行使用ddl=后面接你的VPS到期时间，total=输入你的VPS每月流量数目
[Panel]
Cat VPS = script-name=CatVPS
[Script]
CatVPS = type=generic,script-path=https://raw.githubusercontent.com/getsomecat/GetSomeCats/Surge/script/CatVPS.js, argument = url=http://127.0.0.1:49155/traffic&title=Cat VPS&icon=bolt.horizontal.icloud.fill&low=#06D6A0&mid=#FFD166&high=#EF476F&ddl=2100-01-01&total=10TB
```

将其中的 http://127.0.0.1:49155/traffic部分根据自己上面教程部分改为自己的VPS IP和端口即可使用。


### 主要更改点说明：
1. **去掉了繁杂的 `calculate` 运算函数及写入本地 `tx/rx` 缓存记录的逻辑**：由 `vnstat` 的持久化数据代替，直接输出当月网络传输量。
2. **单位兼容修复 (`sed 's/iB/B/g'`)**：因为 vnstat 默认输出带有 `GiB` 和 `MiB`，但原版 Surge 面板的 JS 脚本（`CatVPS.js`）往往是通过匹配 `GB` / `MB` 进行换算的。这一步能保证在 Surge 里完美显示并正确计算月剩余流量。
3. **补充了错误捕获**：稍微优化了获取 `ip a` 、`top` 和 `free` 信息时可能引发的报错信息泄露，让后台服务更稳定运行。
