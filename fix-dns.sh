#!/bin/bash
set -e

echo "=== 初始 DNS 配置 ==="
resolvectl status

TARGET_DNS="8.8.8.8 1.1.1.1"

echo "=== 检查并修改 systemd-resolved 全局 DNS ==="
RESOLVED_CONF="/etc/systemd/resolved.conf"

if ! grep -q "DNS=" $RESOLVED_CONF 2>/dev/null; then
    sudo sed -i '/^\[Resolve\]/a DNS=8.8.8.8 1.1.1.1' $RESOLVED_CONF
else
    sudo sed -i "s/^#\?DNS=.*/DNS=8.8.8.8 1.1.1.1/" $RESOLVED_CONF
fi

if ! grep -q "FallbackDNS=" $RESOLVED_CONF 2>/dev/null; then
    sudo sed -i '/^\[Resolve\]/a FallbackDNS=9.9.9.9' $RESOLVED_CONF
else
    sudo sed -i "s/^#\?FallbackDNS=.*/FallbackDNS=9.9.9.9/" $RESOLVED_CONF
fi

sudo systemctl restart systemd-resolved
echo "systemd-resolved 已更新为: $TARGET_DNS"

echo ""
echo "=== 检查并修改 Netplan 配置 ==="
for f in /etc/netplan/*.yaml; do
    echo "处理 $f ..."
    # 禁用 DHCP 下发的 DNS
    if grep -q "dhcp4:" $f; then
        sudo sed -i "s/dhcp4: *yes/dhcp4: yes\n      dhcp4-overrides:\n        use-dns: false/" $f
    fi
    # 添加或修改 nameservers
    if grep -q "nameservers:" $f; then
        sudo sed -i "/nameservers:/,/^[^ ]/ s/addresses:.*/addresses: [8.8.8.8, 1.1.1.1]/" $f
    else
        sudo sed -i "/dhcp4: yes/a \      nameservers:\n        addresses: [8.8.8.8, 1.1.1.1]" $f
    fi
done

echo "应用 Netplan 配置..."
sudo netplan apply

echo ""
echo "=== 当前 DNS 配置 ==="
resolvectl status
