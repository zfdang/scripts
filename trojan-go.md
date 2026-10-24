# Trojan-Go 证书自动续期

`trojan-go.sh` 使用 acme.sh 管理 Let's Encrypt ECC 证书。安装时会启用
cron/crond、检查续期任务，保存证书部署路径及重启命令。证书续期成功后，
acme.sh 将完整证书链和私钥写入 Trojan-Go 配置使用的路径，再执行
`systemctl restart trojan-go.service` 并检查服务是否运行。

## 已安装的服务器

把更新后的脚本放到运行 Trojan-Go 的 Linux 服务器，以 root 执行一次：

```bash
bash trojan-go.sh renewCert
```

也可选择菜单 11。此操作重新配置定时任务、部署证书并重启服务，然后检查
是否到续期时间；未到期时不会强制重新签发。无需重新安装 Trojan-Go。

服务安装或修复后，`systemctl reload trojan-go` 会异步排队重启服务，使其
读取新证书。reload 命令返回时重启可能尚未完成；自动续期的钩子使用同步
restart，并检查服务状态。

## 运行条件与检查

HTTP-01 standalone 续期要求域名仍指向服务器、公网 TCP 80 可达，服务器
能访问证书签发服务。续期期间 acme.sh 会临时停止 Nginx，并通过 post-hook
恢复；Trojan-Go 无需在签发期间停止。定时任务持续检查，到期前续期，失败
会在后续调度中重试。网络、DNS 或验证长期失败仍可能导致证书过期。

```bash
crontab -l                         # 应有 acme.sh --cron
systemctl status cron             # Debian/Ubuntu；RHEL/CentOS 使用 crond
systemctl status trojan-go
journalctl -u trojan-go -n 50 --no-pager
openssl x509 -in /etc/trojan-go/你的域名.pem -noout -dates
```

手动导入的 `/root/trojan-go.pem` 和 `/root/trojan-go.key` 不具备签发账户和
验证方式，无法仅凭证书自动续期。需要由原签发方自动部署到配置中的证书路径，
部署成功后执行 `systemctl restart trojan-go.service`。`renewCert` 对没有
acme.sh ECC 签发记录的域名会明确报错。

## Nginx 启动失败

若证书部署显示成功，但随后出现 `nginx.service failed`，先检查：

```bash
nginx -t
journalctl -u nginx -n 50 --no-pager
```

`invalid URL prefix` 表示反代网址格式错误。例如 `https:/blog.zfdang.com`
少了一个 `/`，应为 `https://blog.zfdang.com`。备份并修正对应的
`/etc/nginx/conf.d/域名.conf` 后，执行 `nginx -t && systemctl start nginx`。
脚本现在会在收集输入和写入配置前校验反代网址，拒绝此类错误。

## 验证脚本

本地测试不安装软件、不操作真实 systemd 服务、不申请公网证书：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_trojan_go*.py' -v
bash -n trojan-go.sh
shellcheck --severity=error trojan-go.sh
```

程序替换测试需要 C 编译器（`cc`），用于构建临时的运行中程序。
重装或更新时，脚本将新程序写入 `/usr/bin` 下的临时文件，再原子替换
`/usr/bin/trojan-go`，避免直接覆盖运行中程序产生 `Text file busy`。
替换失败会清理临时文件并保留旧程序；成功后由安装或更新流程重启服务。
