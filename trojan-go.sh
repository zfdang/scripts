#!/bin/bash
# trojan-go一键安装脚本
# Author: hijk<https://hijk.art>
# original URL: https://s.hijk.art/trojan-go.sh


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"

res=`which bt 2>/dev/null`
if [[ "$res" != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi

# 以下网站是随机从Google上找到的无广告小说网站，不喜欢请改成其他网址，以http或https开头
# 搭建好后无法打开伪装域名，可能是反代小说网站挂了，请在网站留言，或者Github发issue，以便替换新的网站
SITES=(
http://www.zhuizishu.com/
http://xs.56dyc.com/
#http://www.xiaoshuosk.com/
#https://www.quledu.net/
http://www.ddxsku.com/
http://www.biqu6.com/
https://www.wenshulou.cc/
#http://www.auutea.com/
http://www.55shuba.com/
http://www.39shubao.com/
https://www.23xsw.cc/
#https://www.huanbige.com/
https://www.jueshitangmen.info/
https://www.zhetian.org/
http://www.bequgexs.com/
http://www.tjwl.com/
)

ZIP_FILE="trojan-go"
CONFIG_FILE="/etc/trojan-go/config.json"
ACME_HOME="/root/.acme.sh"
ACME_SH="$ACME_HOME/acme.sh"

WS="false"

colorEcho() {
    local color=$1
    shift
    echo -e "${color}$*${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        echo -e " ${RED}请以root身份执行该脚本${PLAIN}"
        exit 1
    fi

    res=`which yum 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        res=`which apt 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            echo -e " ${RED}不受支持的Linux系统${PLAIN}"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        echo -e " ${RED}系统版本过低，请升级到最新版本${PLAIN}"
        exit 1
    fi
}

status() {
    trojan_cmd="$(command -v trojan-go)"
    if [[ "$trojan_cmd" = "" ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep local_port $CONFIG_FILE|cut -d: -f2| tr -d \",' '`
    res=`ss -ntlp| grep ${port} | grep trojan-go`
    if [[ -z "$res" ]]; then
        echo 2
    else
        echo 3
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

getVersion() {
    VERSION=`curl -fsSL ${V6_PROXY}https://api.github.com/repos/p4gefau1t/trojan-go/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/'| head -n1`
    if [[ ${VERSION:0:1} != "v" ]];then
        VERSION="v${VERSION}"
    fi
}

archAffix() {
    case "${1:-"$(uname -m)"}" in
        i686|i386)
            echo '386'
        ;;
        x86_64|amd64)
            echo 'amd64'
        ;;
        *armv7*|armv6l)
            echo 'armv7'
        ;;
        *armv8*|aarch64)
            echo 'armv8'
        ;;
        *armv6*)
            echo 'armv6'
        ;;
        *arm*)
            echo 'arm'
        ;;
        *mips64le*)
            echo 'mips64le'
        ;;
        *mips64*)
            echo 'mips64'
        ;;
        *mipsle*)
            echo 'mipsle-softfloat'
        ;;
        *mips*)
            echo 'mips-softfloat'
        ;;
        *)
            return 1
        ;;
    esac

	return 0
}

validateProxyUrl() {
    # Require a complete HTTP(S) URL that can be safely used in nginx directives.
    local url=$1
    [[ "$url" =~ ^https?://(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?)(:[0-9]{1,5})?([/?].*)?$ ]] || return 1
    case "$url" in
        *[[:space:]]*|*\;*|*\{*|*\}*|*\"*|*\'*|*\\*|*\$*|*\#*) return 1 ;;
    esac
}

getData() {
    echo ""
    can_change=$1
    if [[ "$can_change" != "yes" ]]; then
        echo " trojan-go一键脚本，运行之前请确认如下条件已经具备："
        echo -e "  ${RED}1. 一个伪装域名${PLAIN}"
        echo -e "  ${RED}2. 伪装域名DNS解析指向当前服务器ip（${IP}）${PLAIN}"
        echo -e "  3. 如果/root目录下有 ${GREEN}trojan-go.pem${PLAIN} 和 ${GREEN}trojan-go.key${PLAIN} 证书密钥文件，无需理会条件2"
        echo " "
        read -p " 确认满足按y，按其他退出脚本：" answer
        if [[ "${answer,,}" != "y" ]]; then
            exit 0
        fi

        echo ""
        while true
        do
            read -p " 请输入伪装域名：" DOMAIN
            if [[ -z "${DOMAIN}" ]]; then
                echo -e " ${RED}伪装域名输入错误，请重新输入！${PLAIN}"
            else
                break
            fi
        done
        colorEcho $BLUE " 伪装域名(host)：$DOMAIN"

        echo ""
        DOMAIN=${DOMAIN,,}
        if [[ -f ~/trojan-go.pem && -f ~/trojan-go.key ]]; then
            echo -e "${GREEN} 检测到自有证书，将使用其部署${PLAIN}"
            CERT_FILE="/etc/trojan-go/${DOMAIN}.pem"
            KEY_FILE="/etc/trojan-go/${DOMAIN}.key"
        else
            resolve=`dig +short ${DOMAIN}`
            res=`echo -n ${resolve} | grep ${IP}`
            if [[ -z "${res}" ]]; then
                echo " ${DOMAIN} 解析结果：${resolve}"
                echo -e " ${RED}伪装域名未解析到当前服务器IP(${IP})!${PLAIN}"
                exit 1
            fi
        fi
    else
        DOMAIN=`grep sni $CONFIG_FILE | cut -d\" -f4`
        CERT_FILE=`grep cert $CONFIG_FILE | cut -d\" -f4`
        KEY_FILE=`grep key $CONFIG_FILE | cut -d\" -f4`
        read -p " 是否转换成WS版本？[y/n]" answer
        if [[ "${answer,,}" = "y" ]]; then
            WS="true"
        fi
    fi

    echo ""
    read -p " 请设置trojan-go密码（不输则随机生成）:" PASSWORD
    [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    colorEcho $BLUE " trojan-go密码：$PASSWORD"
    echo ""
    while true
    do
        read -p " 是否需要再设置一组密码？[y/n]" answer
        if [[ ${answer,,} = "n" ]]; then
            break
        fi
        read -p " 请设置trojan-go密码（不输则随机生成）:" pass
        [[ -z "$pass" ]] && pass=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        echo ""
        colorEcho $BLUE " trojan-go密码：$pass"
        PASSWORD="${PASSWORD}\",\"$pass"
    done

    echo ""
    read -p " 请输入trojan-go端口[100-65535的一个数字，默认443]：" PORT
    [[ -z "${PORT}" ]] && PORT=443
    if [[ "${PORT:0:1}" = "0" ]]; then
        echo -e "${RED}端口不能以0开头${PLAIN}"
        exit 1
    fi
    colorEcho $BLUE " trojan-go端口：$PORT"

    if [[ ${WS} = "true" ]]; then
        echo ""
        while true
        do
            read -p " 请输入伪装路径，以/开头(不懂请直接回车)：" WSPATH
            if [[ -z "${WSPATH}" ]]; then
                len=`shuf -i5-12 -n1`
                ws=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1`
                WSPATH="/$ws"
                break
            elif [[ "${WSPATH:0:1}" != "/" ]]; then
                echo " 伪装路径必须以/开头！"
            elif [[ "${WSPATH}" = "/" ]]; then
                echo  " 不能使用根路径！"
            else
                break
            fi
        done
        echo ""
        colorEcho $BLUE " ws路径：$WSPATH"
    fi

    echo ""
    colorEcho $BLUE " 请选择伪装站类型:"
    echo "   1) 静态网站(位于/usr/share/nginx/html)"
    echo "   2) 小说站(随机选择)"
    echo "   3) 美女站(https://imeizi.me)"
    echo "   4) 高清壁纸站(https://bing.imeizi.me)"
    echo "   5) 自定义反代站点(需以http或者https开头)"
    read -p "  请选择伪装网站类型[默认:高清壁纸站]" answer
    if [[ -z "$answer" ]]; then
        PROXY_URL="https://bing.imeizi.me"
    else
        case $answer in
        1)
            PROXY_URL=""
            ;;
        2)
            len=${#SITES[@]}
            ((len--))
            while true
            do
                index=`shuf -i0-${len} -n1`
                PROXY_URL=${SITES[$index]}
                host=`echo ${PROXY_URL} | cut -d/ -f3`
                ip=`curl -sL https://hijk.art/hostip.php?d=${host}`
                res=`echo -n ${ip} | grep ${host}`
                if [[ "${res}" = "" ]]; then
                    echo "$ip $host" >> /etc/hosts
                    break
                fi
            done
            ;;
        3)
            PROXY_URL="https://imeizi.me"
            ;;
        4)
            PROXY_URL="https://bing.imeizi.me"
            ;;
        5)
            read -p " 请输入反代站点(以http或者https开头)：" PROXY_URL
            if [[ -z "$PROXY_URL" ]]; then
                colorEcho $RED " 请输入反代网站！"
                exit 1
            elif ! validateProxyUrl "$PROXY_URL"; then
                colorEcho $RED " 反代网站必须是完整的http://或https://网址，例如https://blog.zfdang.com！"
                exit 1
            fi
            ;;
        *)
            colorEcho $RED " 请输入正确的选项！"
            exit 1
        esac
    fi
    REMOTE_HOST=`echo ${PROXY_URL} | cut -d/ -f3`
    echo ""
    colorEcho $BLUE " 伪装网站：$PROXY_URL"

    echo ""
    colorEcho $BLUE " 是否允许搜索引擎爬取网站？[默认：不允许]"
    echo "    y)允许，会有更多ip请求网站，但会消耗一些流量，vps流量充足情况下推荐使用"
    echo "    n)不允许，爬虫不会访问网站，访问ip比较单一，但能节省vps流量"
    read -p "  请选择：[y/n]" answer
    if [[ -z "$answer" ]]; then
        ALLOW_SPIDER="n"
    elif [[ "${answer,,}" = "y" ]]; then
        ALLOW_SPIDER="y"
    else
        ALLOW_SPIDER="n"
    fi
    echo ""
    colorEcho $BLUE " 允许搜索引擎：$ALLOW_SPIDER"

    echo ""
    read -p " 是否安装BBR(默认安装)?[y/n]:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    colorEcho $BLUE " 安装BBR：$NEED_BBR"
}

installNginx() {
    echo ""
    colorEcho $BLUE " 安装nginx..."
    if [[ "$BT" = "false" ]]; then
        if [[ "$PMT" = "yum" ]]; then
            $CMD_INSTALL epel-release
            if [[ "$?" != "0" ]]; then
                echo '[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true' > /etc/yum.repos.d/nginx.repo
            fi
        fi
        $CMD_INSTALL nginx
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " Nginx安装失败，请到 https://hijk.art 反馈"
            exit 1
        fi
        systemctl enable nginx
    else
        res=`which nginx 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 您安装了宝塔，请在宝塔后台安装nginx后再运行本脚本"
            exit 1
        fi
    fi
}

startNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl start nginx
    else
        nginx -c /www/server/nginx/conf/nginx.conf
    fi
}

stopNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl stop nginx
    else
        res=`ps aux | grep -i nginx`
        if [[ "$res" != "" ]]; then
            nginx -s stop
        fi
    fi
}

ensureCronService() {
    local cron_service
    if [[ "$PMT" = "yum" ]]; then
        $CMD_INSTALL cronie || return 1
        cron_service=crond
    else
        $CMD_INSTALL cron || return 1
        cron_service=cron
    fi
    systemctl enable "$cron_service" || return 1
    systemctl start "$cron_service" || return 1
    systemctl is-active --quiet "$cron_service"
}

# acme.sh persists challenge hooks, deployment paths and reloadcmd per domain.
setupCertRenewal() {
    if [[ ! -f "$ACME_HOME/${DOMAIN}_ecc/${DOMAIN}.conf" ]]; then
        colorEcho "$YELLOW" " 自备证书不受acme.sh管理，请配置签发方的自动续期和重启钩子。"
        return 0
    fi
    [[ -x "$ACME_SH" ]] || return 1
    ensureCronService || return 1
    "$ACME_SH" --install-cronjob --home "$ACME_HOME" || return 1
    # Verify installation instead of relying on the installer's success message.
    crontab -l | grep -F -- "$ACME_HOME" | grep -q -- '--cron' || return 1

    mkdir -p "$(dirname "$CERT_FILE")" "$(dirname "$KEY_FILE")" || return 1
    touch "$KEY_FILE" || return 1
    chmod 600 "$KEY_FILE" || return 1
    "$ACME_SH" --install-cert -d "$DOMAIN" --ecc \
        --home "$ACME_HOME" \
        --key-file "$KEY_FILE" --fullchain-file "$CERT_FILE" \
        --reloadcmd "systemctl restart trojan-go.service && systemctl is-active --quiet trojan-go.service" || return 1
    colorEcho "$GREEN" " 自动续期已配置；证书更新后将重启trojan-go并检查服务状态。"
}

getCert() {
    mkdir -p "$(dirname "$CONFIG_FILE")" || return 1
    # A configured certificate is reused during reconfiguration, never overwritten.
    if [[ -n "$CERT_FILE" && -n "$KEY_FILE" ]]; then
        if [[ ! -s "$CERT_FILE" || ! -s "$KEY_FILE" ]]; then
            [[ -s /root/trojan-go.pem && -s /root/trojan-go.key ]] || return 1
            cp /root/trojan-go.pem "$CERT_FILE" || return 1
            cp /root/trojan-go.key "$KEY_FILE" || return 1
        fi
    else
        # HTTP-01 standalone only requires port 80, not Trojan-Go's TLS port.
        stopNginx
        if ss -ntlp | grep -qE ':80[[:space:]]'; then
            startNginx
            colorEcho "$RED" " 其他进程占用了80端口，无法签发证书。"
            return 1
        fi
        $CMD_INSTALL socat openssl || { startNginx; return 1; }
        ensureCronService || { startNginx; return 1; }
        if [[ ! -x "$ACME_SH" ]]; then
            local installer
            installer=$(mktemp) || { startNginx; return 1; }
            if ! curl -fsSL https://get.acme.sh -o "$installer" ||
                ! sh "$installer" email=dantifer@gmail.com; then
                rm -f "$installer"
                startNginx
                return 1
            fi
            rm -f "$installer"
        fi
        "$ACME_SH" --upgrade --auto-upgrade || { startNginx; return 1; }
        "$ACME_SH" --set-default-ca --server letsencrypt || { startNginx; return 1; }
        local pre_hook post_hook issue_result
        if [[ "$BT" = "false" ]]; then
            pre_hook="systemctl stop nginx"
            post_hook="systemctl restart nginx"
        else
            pre_hook="if [ -s /www/server/nginx/logs/nginx.pid ]; then nginx -s stop; fi"
            post_hook="nginx -c /www/server/nginx/conf/nginx.conf"
        fi
        "$ACME_SH" --issue -d "$DOMAIN" --keylength ec-256 \
            --pre-hook "$pre_hook" --post-hook "$post_hook" --standalone
        issue_result=$?
        startNginx
        # acme.sh returns 2 when an existing certificate is not due for renewal.
        if [[ "$issue_result" != 0 && "$issue_result" != 2 ]]; then
            colorEcho "$RED" " 获取证书失败，请检查acme.sh输出。"
            return 1
        fi
        CERT_FILE="/etc/trojan-go/${DOMAIN}.pem"
        KEY_FILE="/etc/trojan-go/${DOMAIN}.key"
        # Defer --install-cert/reloadcmd until the service and config are ready.
        cp "$ACME_HOME/${DOMAIN}_ecc/fullchain.cer" "$CERT_FILE" || return 1
        cp "$ACME_HOME/${DOMAIN}_ecc/${DOMAIN}.key" "$KEY_FILE" || return 1
    fi
    chmod 600 "$KEY_FILE" || return 1
    openssl x509 -in "$CERT_FILE" -noout -checkend 0 || return 1
    local cert_public_key key_public_key
    cert_public_key=$(openssl x509 -in "$CERT_FILE" -pubkey -noout) || return 1
    key_public_key=$(openssl pkey -in "$KEY_FILE" -pubout) || return 1
    [[ "$cert_public_key" = "$key_public_key" ]] || {
        colorEcho "$RED" " 证书和私钥不匹配。"
        return 1
    }
}

# Read the paths actually used by the running installation.
loadCertConfig() {
    [[ -s "$CONFIG_FILE" ]] || return 1
    DOMAIN=$(grep '"sni"' "$CONFIG_FILE" | cut -d\" -f4)
    CERT_FILE=$(grep '"cert"' "$CONFIG_FILE" | cut -d\" -f4)
    KEY_FILE=$(grep '"key"' "$CONFIG_FILE" | cut -d\" -f4)
    [[ -n "$DOMAIN" && -n "$CERT_FILE" && -n "$KEY_FILE" ]]
}

renewCert() {
    loadCertConfig || return 1
    if [[ -z "$DOMAIN" || ! -f "$ACME_HOME/${DOMAIN}_ecc/${DOMAIN}.conf" ]]; then
        colorEcho "$RED" " 未找到此域名的acme.sh ECC签发记录，无法自动续期自备证书。"
        return 1
    fi
    configureTrojanService || return 1
    setupCertRenewal || return 1
    local result
    "$ACME_SH" --renew -d "$DOMAIN" --ecc --home "$ACME_HOME"
    result=$?
    [[ "$result" = 0 || "$result" = 2 ]]
}

configNginx() {
    if [[ -n "$PROXY_URL" ]] && ! validateProxyUrl "$PROXY_URL"; then
        colorEcho "$RED" " 反代网址无效，未修改Nginx配置：$PROXY_URL"
        return 1
    fi
    mkdir -p /usr/share/nginx/html
    if [[ "$ALLOW_SPIDER" = "n" ]]; then
        echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
        echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
        ROBOT_CONFIG="    location = /robots.txt {}"
    else
        ROBOT_CONFIG=""
    fi
    if [[ "$BT" = "false" ]]; then
        if [[ ! -f /etc/nginx/nginx.conf.bak ]]; then
            mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        fi
        res=`id nginx 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            user="www-data"
        else
            user="nginx"
        fi
        cat > /etc/nginx/nginx.conf<<-EOF
user $user;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    server_tokens off;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    gzip                on;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF
    fi

    mkdir -p $NGINX_CONF_PATH
    if [[ "$PROXY_URL" = "" ]]; then
        cat > $NGINX_CONF_PATH${DOMAIN}.conf<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;

    $ROBOT_CONFIG
}
EOF
    else
        cat > $NGINX_CONF_PATH${DOMAIN}.conf<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;
        proxy_set_header Accept-Encoding '';
        sub_filter "$REMOTE_HOST" "$DOMAIN";
        sub_filter_once off;
    }
    
    $ROBOT_CONFIG
}
EOF
    fi
}

downloadFile() {
    SUFFIX=`archAffix`
    DOWNLOAD_URL="${V6_PROXY}https://github.com/p4gefau1t/trojan-go/releases/download/${VERSION}/trojan-go-linux-${SUFFIX}.zip"
    wget -O /tmp/${ZIP_FILE}.zip $DOWNLOAD_URL
    if [[ ! -f /tmp/${ZIP_FILE}.zip ]]; then
        echo -e "{$RED} trojan-go安装文件下载失败，请检查网络或重试${PLAIN}"
        exit 1
    fi
}

configureTrojanService() {
    mkdir -p /etc/systemd/system/trojan-go.service.d || return 1
    cat > /etc/systemd/system/trojan-go.service.d/reload.conf <<'EOF' || return 1
[Service]
Restart=on-failure
RestartSec=5s
ExecReload=
# Queue a restart: a blocking restart of this same unit would deadlock reload.
ExecReload=/bin/systemctl --no-block restart trojan-go.service
EOF
    systemctl daemon-reload
}

replaceTrojanBinary() {
    local source=$1 target=${2:-/usr/bin/trojan-go} staged
    # Stage beside the destination so rename is atomic, even while it is running.
    staged=$(mktemp "${target}.XXXXXX") || return 1
    if ! cp "$source" "$staged" || ! chmod 755 "$staged" ||
        ! mv -f "$staged" "$target"; then
        rm -f "$staged"
        return 1
    fi
}

installTrojan() {
    rm -rf /tmp/${ZIP_FILE}
    unzip /tmp/${ZIP_FILE}.zip -d /tmp/${ZIP_FILE} || return 1
    replaceTrojanBinary "/tmp/${ZIP_FILE}/trojan-go" || return 1
    cp /tmp/${ZIP_FILE}/example/trojan-go.service /etc/systemd/system/ || return 1
    sed -i '/User=nobody/d' /etc/systemd/system/trojan-go.service
    configureTrojanService || return 1

    systemctl enable trojan-go
    rm -rf /tmp/${ZIP_FILE}

    colorEcho $BLUE " trojan-go安装成功！"
}

configTrojan() {
    mkdir -p /etc/trojan-go
    cat > $CONFIG_FILE <<-EOF
{
    "run_type": "server",
    "local_addr": "::",
    "local_port": ${PORT},
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "${CERT_FILE}",
        "key": "${KEY_FILE}",
        "sni": "${DOMAIN}",
        "alpn": [
            "http/1.1"
        ],
        "session_ticket": true,
        "reuse_session": true,
        "fallback_addr": "127.0.0.1",
        "fallback_port": 80
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "prefer_ipv4": false
    },
    "mux": {
        "enabled": false,
        "concurrency": 8,
        "idle_timeout": 60
    },
    "websocket": {
        "enabled": ${WS},
        "path": "${WSPATH}",
        "host": "${DOMAIN}"
    },
    "mysql": {
      "enabled": false,
      "server_addr": "localhost",
      "server_port": 3306,
      "database": "",
      "username": "",
      "password": "",
      "check_rate": 60
    }
}
EOF
}

setSelinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

setFirewall() {
    res=`which firewall-cmd 2>/dev/null`
    if [[ $? -eq 0 ]]; then
        systemctl status firewalld > /dev/null 2>&1
        if [[ $? -eq 0 ]];then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            if [[ "$PORT" != "443" ]]; then
                firewall-cmd --permanent --add-port=${PORT}/tcp
            fi
            firewall-cmd --reload
        else
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -p tcp --dport 443 -j ACCEPT
                if [[ "$PORT" != "443" ]]; then
                    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
                fi
            fi
        fi
    else
        res=`which iptables 2>/dev/null`
        if [[ $? -eq 0 ]]; then
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -p tcp --dport 443 -j ACCEPT
                if [[ "$PORT" != "443" ]]; then
                    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
                fi
            fi
        else
            res=`which ufw 2>/dev/null`
            if [[ $? -eq 0 ]]; then
                res=`ufw status | grep -i inactive`
                if [[ "$res" = "" ]]; then
                    ufw allow http/tcp
                    ufw allow https/tcp
                    if [[ "$PORT" != "443" ]]; then
                        ufw allow ${PORT}/tcp
                    fi
                fi
            fi
        fi
    fi
}

installBBR() {
    if [[ "$NEED_BBR" != "y" ]]; then
        INSTALL_BBR=false
        return
    fi
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        echo " BBR模块已安装"
        INSTALL_BBR=false
        return
    fi
    res=`hostnamectl | grep -i openvz`
    if [[ "$res" != "" ]]; then
        echo  " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        echo " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    if [[ "$PMT" = "yum" ]]; then
        if [[ "$V6_PROXY" = "" ]]; then
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
            rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
            $CMD_INSTALL --enablerepo=elrepo-kernel kernel-ml
            $CMD_REMOVE kernel-3.*
            grub2-set-default 0
            echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
            INSTALL_BBR=true
        fi
    else
        $CMD_INSTALL --install-recommends linux-generic-hwe-16.04
        grub-set-default 0
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        INSTALL_BBR=true
    fi
}

install() {
    getData

    $PMT clean all
    [[ "$PMT" = "apt" ]] && $PMT update
    #echo $CMD_UPGRADE | bash
    $CMD_INSTALL wget vim unzip tar gcc openssl
    $CMD_INSTALL net-tools
    if [[ "$PMT" = "apt" ]]; then
        $CMD_INSTALL libssl-dev g++
    fi
    res=`which unzip 2>/dev/null`
    if [[ $? -ne 0 ]]; then
        echo -e " ${RED}unzip安装失败，请检查网络${PLAIN}"
        exit 1
    fi

    installNginx
    setFirewall
    getCert || { colorEcho "$RED" " 证书准备失败。"; return 1; }
    configNginx || return 1

    echo " 安装trojan-go..."
    getVersion
    downloadFile
    installTrojan || return 1
    configTrojan || return 1

    setSelinux
    installBBR
    setupCertRenewal || { colorEcho "$RED" " 自动续期配置失败。"; return 1; }

    start || return 1
    showInfo

    bbrReboot
}

bbrReboot() {
    if [[ "${INSTALL_BBR}" == "true" ]]; then
        echo  
        echo " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

update() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    echo " 安装最新版trojan-go"
    getVersion
    downloadFile
    installTrojan || return 1
    loadCertConfig || return 1
    setupCertRenewal || return 1

    stop
    start
}

uninstall() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    echo ""
    read -p " 确定卸载trojan-go？[y/n]：" answer
    if [[ "${answer,,}" = "y" ]]; then
        domain=`grep sni $CONFIG_FILE | cut -d\" -f4`
        
        stop
        rm -rf /etc/trojan-go
        rm -rf /usr/bin/trojan-go
        systemctl disable trojan-go
        rm -rf /etc/systemd/system/trojan-go.service

        if [[ "$BT" = "false" ]]; then
            systemctl disable nginx
            $CMD_REMOVE nginx
            if [[ "$PMT" = "apt" ]]; then
                $CMD_REMOVE nginx-common
            fi
            rm -rf /etc/nginx/nginx.conf
            if [[ -f /etc/nginx/nginx.conf.bak ]]; then
                mv /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
            fi
        fi

        rm -rf $NGINX_CONF_PATH${domain}.conf
        # Remove only this domain, preserving other certificates and cron jobs.
        if [[ -x "$ACME_SH" && -f "$ACME_HOME/${domain}_ecc/${domain}.conf" ]]; then
            "$ACME_SH" --remove -d "$domain" --ecc
        fi
        rm -rf /etc/systemd/system/trojan-go.service.d
        systemctl daemon-reload
        echo -e " ${GREEN}trojan-go卸载成功${PLAIN}"
    fi
}

start() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    stopNginx
    startNginx || return 1
    systemctl restart trojan-go || return 1
    sleep 2
    port=`grep local_port $CONFIG_FILE|cut -d: -f2| tr -d \",' '`
    res=`ss -ntlp| grep ${port} | grep trojan-go`
    if [[ "$res" = "" ]]; then
        colorEcho $RED " trojan-go启动失败，请检查端口是否被占用！"
        return 1
    else
        colorEcho $BLUE " trojan-go启动成功"
    fi
}

stop() {
    stopNginx
    systemctl stop trojan-go
    colorEcho $BLUE " trojan-go停止成功"
}


restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    stop
    start
}

reconfig() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    line1=`grep -n 'websocket' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    WS=`sed -n "${line11}p" $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    getData true
    setFirewall
    getCert || { colorEcho "$RED" " 证书准备失败。"; return 1; }
    configTrojan || return 1
    configNginx || return 1
    configureTrojanService || return 1
    setupCertRenewal || { colorEcho "$RED" " 自动续期配置失败。"; return 1; }
    stop
    start || return 1
    showInfo

    bbrReboot
}


showInfo() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    domain=`grep sni $CONFIG_FILE | cut -d\" -f4`
    port=`grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    line1=`grep -n 'password' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    password=`sed -n "${line11}p" $CONFIG_FILE | tr -d \"' '`
    line1=`grep -n 'websocket' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    ws=`sed -n "${line11}p" $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    echo ""
    echo -n " trojan-go运行状态："
    statusText
    echo ""
    echo -e " ${BLUE}trojan-go配置文件: ${PLAIN} ${RED}${CONFIG_FILE}${PLAIN}"
    echo -e " ${BLUE}trojan-go配置信息：${PLAIN}"
    echo -e "   IP：${RED}$IP${PLAIN}"
    echo -e "   伪装域名/主机名(host)/SNI/peer名称：${RED}$domain${PLAIN}"
    echo -e "   端口(port)：${RED}$port${PLAIN}"
    echo -e "   密码(password)：${RED}$password${PLAIN}"
    if [[ $ws = "true" ]]; then
        echo -e "   websocket：${RED}true${PLAIN}"
        wspath=`grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        echo -e "   ws路径(ws path)：${RED}${wspath}${PLAIN}"
    fi
    echo ""
}

showLog() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    journalctl -xen -u trojan-go --no-pager
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}trojan-go一键安装脚本${PLAIN}                  #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""

    echo -e "  ${GREEN}1.${PLAIN}  安装trojan-go"
    echo -e "  ${GREEN}2.${PLAIN}  安装trojan-go+WS"
    echo -e "  ${GREEN}3.${PLAIN}  更新trojan-go"
    echo -e "  ${GREEN}4.  ${RED}卸载trojan-go${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}5.${PLAIN}  启动trojan-go"
    echo -e "  ${GREEN}6.${PLAIN}  重启trojan-go"
    echo -e "  ${GREEN}7.${PLAIN}  停止trojan-go"
    echo " -------------"
    echo -e "  ${GREEN}8.${PLAIN}  查看trojan-go配置"
    echo -e "  ${GREEN}9.  ${RED}修改trojan-go配置${PLAIN}"
    echo -e "  ${GREEN}10.${PLAIN} 查看trojan-go日志"
    echo -e "  ${GREEN}11.${PLAIN} 修复自动续期并检查证书更新"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-11]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            WS="true"
            install
            ;;
        3)
            update
            ;;
        4)
            uninstall
            ;;
        5)
            start
            ;;
        6)
            restart
            ;;
        7)
            stop
            ;;
        8)
            showInfo
            ;;
        9)
            reconfig
            ;;
        10)
            showLog
            ;;
        11)
            renewCert
            ;;
        *)
            echo -e "$RED 请选择正确的操作！${PLAIN}"
            exit 1
            ;;
    esac
}

checkSystem

action=$1
[[ -z $1 ]] && action=menu
case "$action" in
    menu|update|uninstall|start|restart|stop|showInfo|showLog|renewCert)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [menu|update|uninstall|start|restart|stop|showInfo|showLog|renewCert]"
        ;;
esac
