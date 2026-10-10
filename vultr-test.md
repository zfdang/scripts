# Vultr 延迟与路由测试

截至 2026-10-10，逐个读取 [Vultr 官方 Looking Glass](https://sgp-ping.vultr.com/)
的机房选择器和各机房页面的 `Test IPv4`，共确认 33 个公开测试节点。
地址与来源保存在 `vultr-test-ips.tsv`；它是查询当天的快照，地址变化时可重新
访问对应 Looking Glass 核实并更新。机房代码沿用官方选择器，例如东京 NRT、
大阪 ITM、首尔 ICN。

## 使用

需要 Python 3.8+、ping 和 [NextTrace](https://github.com/nxtrace/NTrace-core)。
脚本优先调用 PATH 中的 `nt`，其次是 `nexttrace`；shell 的 alias/function
不能作为独立可执行文件被 Python 调用，可以用 `--nt-command` 指定实际文件。
macOS 可使用 `brew install nexttrace`。Linux 的原始套接字权限不足时以 sudo
运行，并通过 `--nt-command /实际路径/nexttrace` 指定命令。

```bash
# 查看所有机房、测试 IPv4 和对应官方页面
python3 vultr-test.py --list

# 从运行脚本的本机，测试全部机房的延迟和路由
python3 vultr-test.py

# 只测指定机房；可用代码或城市名（不区分大小写）
python3 vultr-test.py --location SGP,NRT,ITM,ICN,LAX

# 指定 nt 的实际可执行文件
python3 vultr-test.py --nt-command /usr/local/bin/nt

# ICMP 被过滤时，尝试 TCP 443 路由探测；ping 仍然使用 ICMP
python3 vultr-test.py --trace-protocol tcp

# 只测延迟，或增加采样次数、路由总超时
python3 vultr-test.py --ping-only --count 10
python3 vultr-test.py --count 10 --trace-timeout 120
```

默认每个机房发送 5 次 ping；逐个执行路由探测，最多 30 跳，每条路由总超时
60 秒。Linux/macOS 的 ping 等待参数分别使用秒/毫秒。全部测试需要数分钟，
无响应节点较多时更久。测试只发送小探测包，不下载测速文件，也不自动安装软件。

结果默认写入当前目录下新建的 `vultr-results-时间戳`，可用 `--output` 指定
一个尚不存在的目录，避免覆盖旧结果：

- `summary.csv`：机房、IP、丢包率、最小/平均/最大延迟、ping 和路由退出状态。
- `机房代码-ping.txt`：原始 ping 输出。
- `机房代码-route.txt`：nt/nexttrace 的逐跳路由输出，包括可用的 ASN/地理信息。

控制台最后按平均延迟排序。无法测出延迟时显示 N/A，不会填入虚构数据。
单个节点失败或超时会保留部分日志并继续测试后续节点。退出码 0 表示命令均
成功，1 表示至少一次探测失败/超时，2 表示参数或依赖错误，130 表示手动中断。
`trace_status=ok` 仅表示路由命令成功退出，是否抵达目标需查看逐跳日志；
中间跳的 `*` 通常表示未回复探测，不能直接认定业务流量丢包。

NextTrace 默认可能访问其 GeoIP 服务。VPN、代理的 TUN 模式和系统路由都会
影响实际探测出口。本脚本测量的是本机到节点的去程和往返延迟，不是机房回程。
