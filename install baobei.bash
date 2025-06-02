#!/bin/bash

config_dir="/usr/local/etc/xray"
xray_bin="/usr/local/bin/xray"
flag_file="$config_dir/.checked"

check_dependencies() {
    if [ -f "$flag_file" ]; then
        return
    fi

    echo "🔧 初始化依赖中..."
    apt install -y curl jq qrencode

    if [ ! -f "$xray_bin" ]; then
        echo "⏬ 安装 Xray 中..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"
    fi

    if [ ! -f "/etc/systemd/system/xray@.service" ]; then
        echo "⚙️ 创建 systemd 多实例模板..."
        cat > /etc/systemd/system/xray@.service <<EOF
[Unit]
Description=Xray Instance %i
After=network.target

[Service]
ExecStart=${xray_bin} -config ${config_dir}/%i.json
Restart=on-failure
User=nobody
LimitNPROC=1000
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reexec
        systemctl daemon-reload
    fi

    mkdir -p "$config_dir"
    touch "$flag_file"
    echo "✅ 初始化完成"
}

create_instance() {
    echo "🔐 正在生成 UUID..."
    uuid=$($xray_bin uuid)
    echo "✅ UUID: $uuid"

    echo "🔐 正在生成 Reality 密钥对..."
    key_output=$($xray_bin x25519)
    private_key=$(echo "$key_output" | grep 'Private key' | awk '{print $3}')
    public_key=$(echo "$key_output" | grep 'Public key' | awk '{print $3}')

    echo "✅ 私钥: $private_key"
    echo "✅ 公钥: $public_key"

    read -p "📦 端口号: " port
    read -p "📦 shortId（可空）: " shortIds
    read -p "📦 SNI（如 speed.cloudflare.com）: " sni
    read -p "📦 域名（如 your.domain.com）: " domain

    last_index=$(ls $config_dir/*.json 2>/dev/null | grep -oP '\d+(?=\.json)' | sort -n | tail -1)
    new_index=$((last_index + 1))
    config_file="$config_dir/$new_index.json"

    cat > "$config_file" <<EOL
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$sni:443",
          "xver": 0,
          "serverNames": [
            "$sni"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$shortIds"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOL

    echo "🔁 启动实例 xray@$new_index"
    systemctl enable xray@"$new_index"
    systemctl restart xray@"$new_index"

    fp="chrome"
    echo ""
    echo "✅ Reality 节点链接："
    link="vless://$uuid@$domain:$port?encryption=none&flow=xtls-rprx-vision&security=reality&fp=$fp&sni=$sni&pbk=$public_key&sid=$shortIds&type=tcp&headerType=none&alpn=h2"
    echo "$link"
    echo ""
    echo "📱 节点二维码："
    echo "$link" | qrencode -t ANSIUTF8
    echo ""
}

manage_instance() {
    read -p "请输入实例编号（如 2 表示 xray@2）: " index

    echo "管理操作："
    echo "1. 查看状态"
    echo "2. 重启"
    echo "3. 设置开机自启"
    echo "4. 停止运行"
    echo "5. 返回"
    read action

    case $action in
        1) systemctl status xray@"$index" ;;
        2) systemctl restart xray@"$index"; echo "✅ 已重启 xray@$index" ;;
        3) systemctl enable xray@"$index"; echo "✅ 已设置开机自启 xray@$index" ;;
        4) systemctl stop xray@"$index"; echo "✅ 已停止 xray@$index" ;;
        5) echo "返回主菜单" ;;
        *) echo "❌ 无效操作" ;;
    esac
}

delete_instance() {
    echo "🗑️ 现有实例："
    for file in $(ls $config_dir/*.json 2>/dev/null | sort -V); do
        num=$(basename "$file" .json)
        echo "编号：$num"
    done

    read -p "请输入要删除的编号（如 3 表示删除 xray@3）： " choice

    if [ -f "$config_dir/$choice.json" ]; then
        systemctl stop xray@"$choice"
        systemctl disable xray@"$choice"
        rm -f "$config_dir/$choice.json"
        echo "✅ 实例 xray@$choice 已删除"
    else
        echo "❌ 找不到该编号对应配置"
    fi
}

# 主菜单入口
check_dependencies

while true; do
    echo ""
    echo "🧰 Reality 多实例管理器"
    echo "1. 创建新节点"
    echo "2. 管理已有实例（状态/重启/自启/停止）"
    echo "3. 删除实例"
    echo "4. 退出"
    read -p "请选择操作编号：" choice

    case $choice in
        1) create_instance ;;
        2) manage_instance ;;
        3) delete_instance ;;
        4) echo "👋 再见！"; exit 0 ;;
        *) echo "❌ 无效输入" ;;
    esac
done
