#!/usr/bin/env zsh

# ================================
# 一键安装 Docker Compose V2 (macOS)
# wget -qO- http://t.zfdang.com/install-docker-compose-in-macos.sh | bash
# ================================

# 1️⃣ 检测 docker CLI 是否已安装
if ! command -v docker &>/dev/null; then
  echo "⚠️ Docker CLI 未安装，请先安装 Docker 或 Docker Desktop"
  exit 1
fi

# 2️⃣ 检测 docker compose 插件是否已存在
if docker compose version &>/dev/null; then
  echo "✅ Docker Compose V2 已安装："
  docker compose version
  exit 0
fi

# 3️⃣ 确保 CLI 插件目录存在
mkdir -p ~/.docker/cli-plugins

# 4️⃣ 获取系统架构
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH="x86_64"
elif [[ "$ARCH" == "arm64" ]]; then
  ARCH="aarch64"
else
  echo "⚠️ 未知架构: $ARCH"
  exit 1
fi

# 5️⃣ 下载 Docker Compose V2
COMPOSE_VERSION="v2.29.2"
DOWNLOAD_URL="https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-darwin-$ARCH"

echo "⬇️ 正在下载 Docker Compose V2 ($COMPOSE_VERSION) ..."
curl -SL "$DOWNLOAD_URL" -o ~/.docker/cli-plugins/docker-compose

# 6️⃣ 赋予执行权限
chmod +x ~/.docker/cli-plugins/docker-compose

# 7️⃣ 移除 macOS Gatekeeper 限制
xattr -d com.apple.quarantine ~/.docker/cli-plugins/docker-compose 2>/dev/null

# 8️⃣ 验证安装
echo "✅ 安装完成，检测版本："
docker compose version

# 9️⃣ 提示信息
echo "现在可以使用 'docker compose up' 来启动服务了！"
