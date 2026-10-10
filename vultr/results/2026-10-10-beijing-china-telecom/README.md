# Vultr 北京中国电信宽带测试结果

2026 年 10 月 10 日，从北京的中国电信宽带网络测试 Vultr 的 33 个公开
Looking Glass 节点。32 个节点回复了 ping，全部 33 份路由日志都出现目标 IP。
按本次收到的 ping 回复计算，东京平均延迟最低，为 115.130 ms，但 3 次采样
中有 1 次未回复；法兰克福为 152.654 ms，洛杉矶为 173.555 ms，均收到 3 次回复。

这是单次、少量采样结果，适合作为北京电信用户选节点时的初步参考。
实际云服务器的路由、时段和服务表现可能不同，其他网络应重新运行脚本。

## 测试条件

| 项目 | 条件 |
| --- | --- |
| 测试源 | 北京，中国电信宽带；由测试者提供 |
| 测试时段 | 2026-10-10 约 15:32–15:37，UTC+8；按日志文件创建和修改时间确定 |
| 操作系统 | macOS 15.8.1，arm64 |
| Python | 3.11.5 |
| 路由工具 | NextTrace 1.7.1，Homebrew 构建；本机无独立 nt 命令，脚本自动使用 nexttrace |
| 地址族 | IPv4 |
| 测试目标 | 33 个 Vultr 官方 Looking Glass 的 Test IPv4，2026-10-10 核对 |
| ping | 每节点 3 次，系统默认发送间隔，单次等待 1000 ms；56 字节 ICMP 数据 |
| ping 总超时 | 每节点 11 秒，即 count × 2 + 5 |
| 路由探测 | ICMP，最多 30 跳，每跳 3 次探测，单次探测超时 1000 ms |
| 路由总超时 | 每节点 30 秒 |
| 执行顺序 | 单线程逐个测试；各节点并非同时采样 |
| GeoIP 数据源 | NextTrace 日志显示 LeoMoeAPI；ASN 和地理位置为该工具提供的注释 |
| VPN 或 TUN | 未记录 |
| 有线或 Wi-Fi、宽带套餐、当时网络负载 | 未记录 |

此次运行的脚本命令（整理目录前）：

```bash
python3 vultr-test.py --count 3 --trace-timeout 30 --output /tmp/vultr-network-20261010
```

每个目标实际执行以下形式的命令，原始参数也保存在日志首行：

```bash
/sbin/ping -n -c 3 -W 1000 <IPv4>
/opt/homebrew/bin/nexttrace -4 -M -C -m 30 -q 3 --timeout 1000 <IPv4>
```

`-W 1000` 是 macOS 的毫秒参数；脚本在 Linux 使用 `-W 1`。
路由命令的 30 秒总超时由 Python 控制。本次路由命令均正常退出，未触发总超时。

## 延迟与丢包汇总

按平均延迟升序排列；均值只包含收到回复的 ping。丢包率来自每个节点的 3 次
采样，33.3% 代表 1 次未回复，66.7% 代表 2 次未回复，不能直接当作长期丢包率。
CSV 保留执行顺序及最小、平均、最大延迟和命令状态。

[下载汇总 CSV](summary.csv)

| 机房代码 | 城市 | 测试 IPv4 | 平均延迟 ms | ping 丢包率 | 日志 |
| --- | --- | --- | ---: | ---: | --- |
| NRT | Tokyo | 108.61.201.151 | 115.130 | 33.3% | [ping](logs/NRT-ping.txt) · [路由](logs/NRT-route.txt) |
| FRA | Frankfurt | 108.61.210.117 | 152.654 | 0.0% | [ping](logs/FRA-ping.txt) · [路由](logs/FRA-route.txt) |
| LAX | Los Angeles | 108.61.219.200 | 173.555 | 0.0% | [ping](logs/LAX-ping.txt) · [路由](logs/LAX-route.txt) |
| SJC | Silicon Valley | 104.156.230.107 | 177.447 | 66.7% | [ping](logs/SJC-ping.txt) · [路由](logs/SJC-route.txt) |
| STO | Stockholm | 70.34.194.86 | 195.002 | 33.3% | [ping](logs/STO-ping.txt) · [路由](logs/STO-route.txt) |
| YTO | Toronto | 149.248.50.81 | 235.688 | 0.0% | [ping](logs/YTO-ping.txt) · [路由](logs/YTO-route.txt) |
| WAW | Warsaw | 70.34.242.24 | 236.121 | 33.3% | [ping](logs/WAW-ping.txt) · [路由](logs/WAW-route.txt) |
| HNL | Honolulu | 208.72.154.76 | 238.211 | 0.0% | [ping](logs/HNL-ping.txt) · [路由](logs/HNL-route.txt) |
| MEX | Mexico City | 216.238.66.16 | 243.674 | 0.0% | [ping](logs/MEX-ping.txt) · [路由](logs/MEX-route.txt) |
| ICN | Seoul | 141.164.34.61 | 245.490 | 33.3% | [ping](logs/ICN-ping.txt) · [路由](logs/ICN-route.txt) |
| MIA | Miami | 104.156.244.232 | 246.413 | 0.0% | [ping](logs/MIA-ping.txt) · [路由](logs/MIA-route.txt) |
| SEA | Seattle | 108.61.194.105 | 249.584 | 0.0% | [ping](logs/SEA-ping.txt) · [路由](logs/SEA-route.txt) |
| ITM | Osaka | 64.176.34.94 | 250.181 | 0.0% | [ping](logs/ITM-ping.txt) · [路由](logs/ITM-route.txt) |
| DFW | Dallas | 108.61.224.175 | 254.609 | 0.0% | [ping](logs/DFW-ping.txt) · [路由](logs/DFW-route.txt) |
| ATL | Atlanta | 108.61.193.166 | 255.354 | 0.0% | [ping](logs/ATL-ping.txt) · [路由](logs/ATL-route.txt) |
| TLV | Tel Aviv | 64.176.162.16 | 259.000 | 0.0% | [ping](logs/TLV-ping.txt) · [路由](logs/TLV-route.txt) |
| DEL | Delhi NCR | 139.84.162.104 | 265.885 | 0.0% | [ping](logs/DEL-ping.txt) · [路由](logs/DEL-route.txt) |
| CDG | Paris | 108.61.209.127 | 266.133 | 0.0% | [ping](logs/CDG-ping.txt) · [路由](logs/CDG-route.txt) |
| EWR | New Jersey | 108.61.149.182 | 266.884 | 0.0% | [ping](logs/EWR-ping.txt) · [路由](logs/EWR-route.txt) |
| AMS | Amsterdam | 108.61.198.102 | 270.653 | 0.0% | [ping](logs/AMS-ping.txt) · [路由](logs/AMS-route.txt) |
| BOM | Mumbai | 65.20.66.100 | 274.353 | 0.0% | [ping](logs/BOM-ping.txt) · [路由](logs/BOM-route.txt) |
| MXP | Milan | 66.245.203.234 | 279.460 | 33.3% | [ping](logs/MXP-ping.txt) · [路由](logs/MXP-route.txt) |
| MAD | Madrid | 208.76.222.30 | 288.989 | 0.0% | [ping](logs/MAD-ping.txt) · [路由](logs/MAD-route.txt) |
| ORD | Chicago | 107.191.51.12 | 289.032 | 0.0% | [ping](logs/ORD-ping.txt) · [路由](logs/ORD-route.txt) |
| LHR | London | 108.61.196.101 | 294.432 | 0.0% | [ping](logs/LHR-ping.txt) · [路由](logs/LHR-route.txt) |
| MAN | Manchester | 64.176.178.136 | 295.156 | 33.3% | [ping](logs/MAN-ping.txt) · [路由](logs/MAN-route.txt) |
| MEL | Melbourne | 67.219.110.24 | 324.641 | 0.0% | [ping](logs/MEL-ping.txt) · [路由](logs/MEL-route.txt) |
| SAO | São Paulo | 216.238.98.118 | 336.699 | 0.0% | [ping](logs/SAO-ping.txt) · [路由](logs/SAO-route.txt) |
| BLR | Bangalore | 139.84.130.100 | 387.834 | 0.0% | [ping](logs/BLR-ping.txt) · [路由](logs/BLR-route.txt) |
| SYD | Sydney | 108.61.212.117 | 408.721 | 0.0% | [ping](logs/SYD-ping.txt) · [路由](logs/SYD-route.txt) |
| SCL | Santiago | 64.176.2.7 | 424.580 | 0.0% | [ping](logs/SCL-ping.txt) · [路由](logs/SCL-route.txt) |
| JNB | Johannesburg | 139.84.226.78 | 452.169 | 0.0% | [ping](logs/JNB-ping.txt) · [路由](logs/JNB-route.txt) |
| SGP | Singapore | 45.32.100.168 | N/A | 100.0% | [ping](logs/SGP-ping.txt) · [路由](logs/SGP-route.txt) |

## 路由结果的解读

全部 33 份路由日志都出现了相应目标 IP，不只是检查命令退出码。
新加坡的 3 次独立 ping 均未收到回复，但路由探测仍显示目标
`45.32.100.168`；因此不能据此判断该节点离线。完整的逐跳 IP、可用 ASN、
地理注释和每跳延迟见上表的路由链接。

中间跳的 `*` 表示该次探测没有收到响应。路由器可能过滤或限制 ICMP 回复，
不能据此判定转发业务流量时丢包。每跳往返时间也不等于这一段链路的单向延迟。
本次结果不包含机房到北京的独立回程探测，也没有测量下载速度、吞吐量或 TCP 延迟。

## 数据与复测

测试 IP 和官方页面对应关系见 [测试地址表](../../vultr-test-ips.tsv)，
节点来源为 [Vultr 官方 Looking Glass](https://sgp-ping.vultr.com/)。
日志中的 `[LAN_SOURCE]`、`[LAN_GATEWAY]`、`[CGNAT_GATEWAY]` 分别代替本机局域网
地址、局域网网关和运营商内网网关；公网路由跳、目标 IP、延迟及命令状态保持原样。
日志去除了行尾空格，CSV 换行统一为 LF；测量值保持原样，结果文件是此次实测快照。

从仓库根目录运行下面的命令，可在自己的网络重新采样；结果应放入新的目录，
并同时记录城市、运营商、VPN 状态、测试时间和参数：

```bash
python3 vultr/vultr-test.py --count 10 --trace-timeout 60 --output ./vultr-results-new
```

脚本默认采样次数为 5、路由总超时为 60 秒，与本报告的 3 次和 30 秒不同。
具体用法见 [脚本说明](../../README.md)。
