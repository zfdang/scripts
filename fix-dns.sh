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
for NETPLAN_FILE in /etc/netplan/*.yaml; do
    echo "处理文件: $NETPLAN_FILE"

    BACKUP_FILE="${NETPLAN_FILE}.bak.${DATE_TAG}"
    echo "  -> 备份到: $BACKUP_FILE"
    sudo cp "$NETPLAN_FILE" "$BACKUP_FILE"

    echo "  -> 清理旧的 nameservers..."
    sudo sed -i '/nameservers:/,/^[^ ]/d' "$NETPLAN_FILE"

    echo "  -> 插入新的 DNS..."
    sudo awk -v dns="$TARGET_DNS" '
    /set-name:/ {
        print $0
        print "      nameservers:"
        print "        addresses: " dns
        next
    }
    {print}
    ' "$NETPLAN_FILE" | sudo tee "$NETPLAN_FILE.tmp" >/dev/null

    sudo mv "$NETPLAN_FILE.tmp" "$NETPLAN_FILE"
done

echo "应用 Netplan 配置..."
sudo netplan apply


echo ""
echo "=== 当前 DNS 配置 ==="
resolvectl status
