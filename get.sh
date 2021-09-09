#!/bin/sh
#
#   InPanel Installer Script
#
#   Copyright (c) 2021, Jackson Dou
#   All rights reserved.
#
#   GitHub: https://github.com/inpanel/get
#   Issues: https://github.com/inpanel/get/issues
#   Requires: bash, cp, rm, tr, type, grep, sed, curl/wget, tar (or unzip on OSX and Windows)
#
#   This script installs InPanel to your path.
#   Usage:
#
#       $ curl -fsSL https://raw.githubusercontent.com/inpanel/get/main/get.sh | bash
#       or
#       $ wget -qO- https://raw.githubusercontent.com/inpanel/get/main/get.sh | bash
#
#   In automated environments, you may want to run as root.
#   If using curl, we recommend using the -fsSL flags.
#
#   This should work on Linux, Mac, and BSD systems, and hopefully Windows with Cygwin. Please open an issue if you notice any bugs.
#
#   This script is distributed under the terms of the MIT License.
#   The full license can be found in 'LICENSE'.

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo '[INPANEL]: Aborted, must be run as root'
    exit 1
fi

# 默认值
initd_script='/etc/init.d/inpanel'
work_path='/usr/local/inpanel'
work_port=8888
ipaddress="0.0.0.0"
username='admin'
password='admin'
repository='https://github.com/inpanel/inpanel'

system_os="unsupported"
system_arch="unknown"

download_file_tag="v1.1.1b25"
download_file_ext=".tar.gz"

echo '[INPANEL]: ===========START============'

# 系统信息 OS and version
function init_system_info() {
    # NOTE: `uname -m` is more accurate and universal than `arch`
    # See https://en.wikipedia.org/wiki/Uname
    unamem="$(uname -m)"
    case $unamem in
    *aarch64*)
        system_arch="arm64"
        ;;
    *64*)
        system_arch="amd64"
        ;;
    *86*)
        system_arch="386"
        ;;
    *armv5*)
        system_arch="armv5"
        ;;
    *armv6*)
        system_arch="armv6"
        ;;
    *armv7*)
        system_arch="armv7"
        ;;
    *)
        echo "[INPANEL]: Aborted, unsupported or unknown architecture: $unamem"
        return 2
        ;;
    esac

    unameu="$(tr '[:lower:]' '[:upper:]' <<<$(uname))"
    if [[ $unameu == *DARWIN* ]]; then
        system_os="Darwin"
    elif [[ $unameu == *LINUX* ]]; then
        system_os="Linux"
    elif [[ $unameu == *FREEBSD* ]]; then
        system_os="FreeBSD"
    elif [[ $unameu == *NETBSD* ]]; then
        system_os="NetBSD"
    elif [[ $unameu == *OPENBSD* ]]; then
        system_os="OpenBSD"
    elif [[ $unameu == *WIN* || $unameu == MSYS* ]]; then
        # Should catch cygwin
        system_os="Windows"
        download_file_ext=".zip"
    else
        echo "[INPANEL]: Aborted, unsupported or unknown OS: $uname"
        return 6
    fi
    echo "[INPANEL]: System: $system_os $system_arch"
}

# 安装依赖
function fun_dependent() {
    echo '[INPANEL]: Install Dependents...'
    yum install -y -q wget net-tools vim psmisc rsync libxslt-devel GeoIP GeoIP-devel gd gd-devel python2

    python_path=$(which python)
    if [ ! $python_path ]; then
        python2_path=$(which python2)
        ln -s "${python2_path}" /usr/bin/python
    fi
}

# 下载安装包到指定位置
function fun_download() {
    if type -p curl >/dev/null 2>&1; then
        download_get='curl -fsSL'
    elif type -p wget >/dev/null 2>&1; then
        download_get='wget -qO-'
    else
        echo '[INPANEL]: Aborted, could not find curl or wget'
        return 7
    fi

    # latest tag
    download_file_tag="$(${download_get} https://api.github.com/repos/inpanel/inpanel/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"//g' | sed 's/tag_name: //g')"
    # download_file_url="${repository}/releases/download/${download_file_tag}${download_file_ext}"
    download_file_url="${repository}/archive/refs/tags/${download_file_tag}${download_file_ext}"

    echo '[INPANEL]: Download Latest InPanel'
    echo "[INPANEL]: Version:    ${download_file_tag}"
    echo "[INPANEL]: URL:        $download_file_url"
    echo "[INPANEL]: Directory:  ${work_path}"

    # 检查文件夹/创建
    test ! -d "${work_path}" && mkdir "${work_path}"

    echo '[INPANEL]: Downloading...'
    ${download_get} "$download_file_url" | tar zx -C "${work_path}" --strip-components 1

    # 添加执行权限
    if [ -f "${work_path}"/config.py ]; then
        chmod +x "${work_path}"/config.py
    fi
    if [ -f "${work_path}"/server.py ]; then
        chmod +x "${work_path}"/server.py
    fi
}

# 设置账号
function fun_set_username() {
    read -p "[INPANEL]: Enter Admin Username [default: ${username}]: " in_name
    if [ $in_name ]; then
        username=$in_name
    fi
    echo "[INPANEL]: Admin Username is: ${username}"
    # 修改配置
    if [ -e "${work_path}"/config.py ]; then
        ${work_path}/config.py username ${username}
        echo '[INPANEL]: Admin Username Saved.'
    fi
}

# 设置密码
function fun_set_password() {
    printf "[INPANEL]: Enter Admin Password [default: ${password}]: "

    # 使用 while 循环隐式地从标准输入每次读取一个字符，且反斜杠不做转义字符处理
    # 然后将读取的字符赋值给变量 in_pwd
    password_input=''
    while IFS= read -r -s -n1 in_pwd; do
        # 如果读入的字符为空，则退出 while 循环
        if [ -z $in_pwd ]; then
            echo
            break
        fi
        # 如果输入的是退格或删除键，则移除一个字符
        if [[ $in_pwd == $'\x08' || $in_pwd == $'\x7f' ]]; then
            [[ -n $password_input ]] && password_input=${password_input:0:${#password_input}-1}
            printf '\b \b'
        else
            password_input+=$in_pwd
            printf '*'
        fi
    done

    # echo "password_input: ${password_input}"
    if [ $password_input ]; then
        password=$password_input
    fi

    echo "[INPANEL]: Admin Password is: ${password}"
    # 修改配置
    if [ -f "${work_path}"/config.py ]; then
        "${work_path}"/config.py password "${password}"
        echo '[INPANEL]: Admin Password Saved.'
    fi
}

# 设置端口
function fun_set_port() {
    read -p "[INPANEL]: Enter Listen Port [default: ${work_port}]: " in_port
    if [ $in_port ]; then
        work_port=$in_port
    fi
    # 修改配置
    if [ -f "${work_path}"/config.py ]; then
        "${work_path}"/config.py port "${work_port}"
    fi
    echo "[INPANEL]: Port ${work_port}"
}

# 设置防火墙
function fun_set_firewall() {
    echo '[INPANEL]: Configure Firewall...'
    if [ -f /usr/sbin/ufw ]; then
        ufw allow "${work_port}"/tcp
        ufw allow "${work_port}"/udp
        ufw reload
    fi

    # if [ -f /etc/firewalld/firewalld.conf ]; then
    #     firewall-cmd --permanent --zone=public --add-port="${work_port}"/tcp
    #     systemctl restart firewalld.service
    if [ -f /etc/sysconfig/firewalld ]; then
        default_zone=$(firewall-cmd --get-default-zone)

        firewall-cmd --permanent --zone="${default_zone}" --add-port="${work_port}"/tcp
        firewall-cmd --permanent --zone="${default_zone}" --add-port="${work_port}"/udp
        firewall-cmd --reload
    fi
    if [ -f /etc/init.d/iptables ]; then
        iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport "${work_port}" -j ACCEPT
        iptables -I INPUT -p udp -m state --state NEW -m udp --dport "${work_port}" -j ACCEPT
        /etc/init.d/iptables save
    fi
}

# 获取IP地址
function fun_set_ip() {
    ipaddress=$(curl -s http://ip.42.pl/raw)
    echo "[INPANEL]: IP ${ipaddress}"
}

# 成功
function fun_success() {
    echo '[INPANEL]:'
    echo '[INPANEL]: ============================'
    echo '[INPANEL]: *                          *'
    echo '[INPANEL]: *     INSTALL COMPLETED    *'
    echo '[INPANEL]: *                          *'
    echo '[INPANEL]: ============================'
    echo '[INPANEL]:'
    echo '[INPANEL]: The URL of your InPanel is: '
    echo "[INPANEL]: http://${ipaddress}:${work_port}"
    echo '[INPANEL]:'
    echo '[INPANEL]: Wish you a happy life !'
    echo '[INPANEL]:'
    echo '[INPANEL]: ============END============='
}

init_system_info
fun_dependent
fun_download
fun_set_username
fun_set_password
fun_set_ip
fun_set_port
fun_set_firewall
fun_success
