
#!/bin/bash

# setup_server.sh
# 这个脚本用于安装和配置 vnStat 流量监控 API 的服务器环境。

# 在任何错误时退出
set -e

# 默认变量（您可以根据需要修改）
DEFAULT_APP_PORT=5000
DEFAULT_APP_HOST="::"
DEFAULT_APP_DIR="/opt/vnstat_api"
DEFAULT_PYTHON_VERSION="python3"

# 函数定义

function show_menu() {
    echo "欢迎使用 vnStat API 一键安装脚本！"
    echo "请选择要执行的操作："
    echo "1) 安装"
    echo "2) 卸载"
    echo "3) 退出"
    read -p "请输入选项 [1-3]: " choice
    case $choice in
        1)
            main
            ;;
        2)
            uninstall
            ;;
        3)
            exit 0
            ;;
        *)
            echo "无效的选项，请重试。"
            show_menu
            ;;
    esac
}

function install_packages() {
    echo "更新软件包列表..."
    sudo apt-get update

    echo "安装 vnStat..."
    sudo apt-get install -y vnstat

    echo "安装 Python 和 pip..."
    sudo apt-get install -y $PYTHON_VERSION $PYTHON_VERSION-pip

    echo "安装 virtualenv..."
    sudo $PYTHON_VERSION -m pip install virtualenv
}

function setup_vnstat() {
    echo "配置 vnStat 监控所有可用的网络接口..."

    # 获取所有可用的网络接口
    interfaces=$(ls /sys/class/net | grep -v lo)

    for interface in $interfaces; do
        # 检查 vnStat 是否监控该接口
        if ! sudo vnstat -i $interface > /dev/null 2>&1; then
            echo "将接口 $interface 添加到 vnStat..."

            # 为接口创建数据库
            sudo vnstat -i $interface --create
        else
            echo "接口 $interface 已由 vnStat 监控。"
        fi
    done

    # 重启 vnStat 服务
    sudo systemctl restart vnstat
}

function setup_app() {
    echo "在 $APP_DIR 设置应用程序目录"

    # 创建应用程序目录
    sudo mkdir -p $APP_DIR
    sudo chown $USER:$USER $APP_DIR

    # 下载 app.py 到应用程序目录
    echo "下载 app.py..."
    curl -fsSL https://raw.githubusercontent.com/8730062/ipv6-/refs/heads/main/app.py -o $APP_DIR/app.py

    echo "创建 Python 虚拟环境..."
    cd $APP_DIR
    $PYTHON_VERSION -m virtualenv venv

    echo "激活虚拟环境并安装依赖..."
    source venv/bin/activate
    pip install Flask

    deactivate
}

function setup_service() {
    echo "为 Flask 应用程序设置 systemd 服务..."

    SERVICE_FILE="/etc/systemd/system/vnstat_api.service"

    sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=vnStat API 服务
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/app.py
Restart=always
Environment=APP_HOST=$APP_HOST
Environment=APP_PORT=$APP_PORT

[Install]
WantedBy=multi-user.target
EOF

    echo "重新加载 systemd 守护进程..."
    sudo systemctl daemon-reload

    echo "启用并启动 vnStat API 服务..."
    sudo systemctl enable vnstat_api.service
    sudo systemctl start vnstat_api.service
}

function open_firewall_port() {
    echo "在防火墙中打开端口 $APP_PORT..."

    # 检查是否安装了 UFW
    if command -v ufw > /dev/null; then
        sudo ufw allow $APP_PORT
    else
        echo "未检测到 UFW 防火墙。如果您使用其他防火墙，请确保端口 $APP_PORT 已打开。"
    fi
}

function uninstall() {
    echo "正在卸载 vnStat API 服务..."

    # 停止并禁用服务
    sudo systemctl stop vnstat_api.service
    sudo systemctl disable vnstat_api.service

    # 删除服务文件
    sudo rm -f /etc/systemd/system/vnstat_api.service

    # 重新加载 systemd 守护进程
    sudo systemctl daemon-reload

    # 删除应用程序目录
    sudo rm -rf $APP_DIR

    echo "卸载完成。"
}

function main() {
    # 提示用户进行配置

    read -p "请输入 Flask 应用程序监听的地址（默认：$DEFAULT_APP_HOST）： " APP_HOST_INPUT
    APP_HOST=${APP_HOST_INPUT:-$DEFAULT_APP_HOST}

    read -p "请输入 Flask 应用程序监听的端口（默认：$DEFAULT_APP_PORT）： " APP_PORT_INPUT
    APP_PORT=${APP_PORT_INPUT:-$DEFAULT_APP_PORT}

    read -p "请输入应用程序安装的目录（默认：$DEFAULT_APP_DIR）： " APP_DIR_INPUT
    APP_DIR=${APP_DIR_INPUT:-$DEFAULT_APP_DIR}

    read -p "请输入要使用的 Python 版本（默认：$DEFAULT_PYTHON_VERSION）： " PYTHON_VERSION_INPUT
    PYTHON_VERSION=${PYTHON_VERSION_INPUT:-$DEFAULT_PYTHON_VERSION}

    install_packages
    setup_vnstat
    setup_app
    setup_service
    open_firewall_port

    echo "设置完成。vnStat API 服务正在运行。"
    echo "您可以通过 http://[您的IPv6地址]:$APP_PORT/api/traffic 访问它。"
}

show_menu
