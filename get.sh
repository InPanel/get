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

RED='\033[0;31m'
GREEN='\033[0;32m'
GREENS='\033[5;32m'
BLUE='\033[1;34m'
DARK='\033[1;30m'
NC='\033[0m'
INP='[\033[1;30mINPANEL\033[0m]'
OK='\033[0;32mOK\033[0m'

# Check if user is root
if [ $(id -u) != "0" ]; then
    printf "${INP}: ${RED}Aborted, must be run as root${NC}\n"
    exit 1
fi

inpanel_bin='/usr/local/bin/inpanel'
inpanel_init='/etc/init.d/inpanel'
inpanel_path='/usr/local/inpanel'
inpanel_port=8888
ipaddress="0.0.0.0"
username='admin'
password='admin'
repository='https://github.com/inpanel/inpanel'

system_os="Unsupported"
system_arch="Unknown"

download_file_tag="v1.1.1b25"
download_file_ext=".tar.gz"

printf "${INP}: ===========${DARK}START${NC}============\n"

# 系统信息 OS and version
function init_system_info() {
    # NOTE: `uname -m` is more accurate and universal than `arch`
    # See https://en.wikipedia.org/wiki/Uname
    uname_s="$(uname)"
    if [ $uname_s ]; then
        system_os=$uname_s
    else
        printf "${INP}: Unsupported or unknown OS: ${uname_s}\n"
        return 6
    fi

    uname_m="$(uname -m)"
    if [ $uname_m ]; then
        system_arch=$uname_m
    else
        printf "${INP}: Unsupported or unknown architecture: ${uname_m}\n"
    fi

    uname_r="$(uname -r)"
    printf "${INP}: System: $system_os $system_arch ${uname_r}\n"
}

# 安装依赖
function fun_dependent() {
    if [ -f /usr/bin/yum ]; then
        printf "${INP}: Install Dependents...\n"
        yum install -y -q wget net-tools vim psmisc rsync libxslt-devel GeoIP GeoIP-devel gd gd-devel python2
    # elif [ -f /usr/bin/apt-get ]; then
    #     apt-get install -y wget net-tools vim psmisc rsync libxslt-devel GeoIP GeoIP-devel gd gd-devel python2
    else
        printf "${INP}: Aborted, ${RED}Unsupported!${NC}\n"
        exit 2
    fi

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
        printf "${INP}: Aborted, could not find curl or wget\n"
        return 7
    fi

    # latest tag
    download_file_tag="$(${download_get} https://api.github.com/repos/inpanel/inpanel/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"//g' | sed 's/tag_name: //g')"
    # download_file_url="${repository}/releases/download/${download_file_tag}${download_file_ext}"
    download_file_url="${repository}/archive/refs/tags/${download_file_tag}${download_file_ext}"

    printf "${INP}: Download Latest InPanel\n"
    printf "${INP}: Version:    ${download_file_tag}\n"
    printf "${INP}: URL:        $download_file_url\n"
    printf "${INP}: Directory:  ${inpanel_path}\n"

    # 检查文件夹/创建
    test ! -d "${inpanel_path}" && mkdir "${inpanel_path}"

    printf "${INP}: Downloading..."
    ${download_get} "$download_file_url" | tar zx -C "${inpanel_path}" --strip-components 1
    printf "${OK}\n"

    # 添加执行权限
    if [ -f "${inpanel_path}"/config.py ]; then
        chmod +x "${inpanel_path}"/config.py
    fi
    if [ -f "${inpanel_path}"/server.py ]; then
        chmod +x "${inpanel_path}"/server.py
    fi
    # link init
    chmod +x "${inpanel_path}"/scripts/init.d/centos/inpanel
    if [ -f "${inpanel_init}" ]; then
        rm -f "${inpanel_init}"
    fi
    ln -s "${inpanel_path}"/scripts/init.d/centos/inpanel $inpanel_init

    chmod +x "${inpanel_path}"/scripts/bin/inpanel
    # link bin
    if [ -f "${inpanel_bin}" ]; then
        rm -f "${inpanel_bin}"
    fi
    ln -s "${inpanel_path}"/scripts/bin/inpanel $inpanel_bin

    printf "${INP}: download successful\n"
}

# 设置账号
function fun_set_username() {
    printf "${INP}: Enter Admin Username [default: ${username}]: "
    read in_name
    if [ $in_name ]; then
        username=$in_name
    fi
    printf "${INP}: Admin Username is: ${BLUE}${username}${NC}\n"
    # 修改配置
    if [ -e "${inpanel_path}"/config.py ]; then
        ${inpanel_path}/config.py username ${username}
        printf "${INP}: Admin Username Saved.\n"
    fi
    return username
}

# 设置密码
function fun_set_password() {
    printf "${INP}: Enter Admin Password [default: ${password}]: "

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

    if [ $password_input ]; then
        password=$password_input
    fi

    printf "${INP}: Admin Password is: ${BLUE}${password}${NC}\n"
    # 修改配置
    if [ -f "${inpanel_path}"/config.py ]; then
        "${inpanel_path}"/config.py password "${password}"
        printf "${INP}: Admin Password Saved.\n"
    fi
    return password
}

# 设置端口
function fun_set_port() {
    printf "${INP}: Enter Listen Port [default: ${inpanel_port}]: "
    read in_port
    if [ $in_port ]; then
        inpanel_port=$in_port
    fi
    # 修改配置
    if [ -f "${inpanel_path}"/config.py ]; then
        "${inpanel_path}"/config.py port "${inpanel_port}"
    fi
    printf "${INP}: InPanel Port ${BLUE}${inpanel_port}${NC}\n"
    return inpanel_port
}

# 设置防火墙
function fun_set_firewall() {
    printf "${INP}: Configure Firewall..."
    if [ -f /usr/sbin/ufw ]; then
        ufw allow "${inpanel_port}"/tcp
        ufw allow "${inpanel_port}"/udp
        ufw reload
    fi

    # if [ -f /etc/firewalld/firewalld.conf ]; then
    #     firewall-cmd --permanent --zone=public --add-port="${inpanel_port}"/tcp
    #     systemctl restart firewalld.service
    if [ -f /etc/sysconfig/firewalld ]; then
        default_zone=$(firewall-cmd --get-default-zone)

        firewall-cmd --permanent --zone="${default_zone}" --add-port="${inpanel_port}"/tcp
        firewall-cmd --permanent --zone="${default_zone}" --add-port="${inpanel_port}"/udp
        firewall-cmd --reload
    fi
    if [ -f /etc/init.d/iptables ]; then
        iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport "${inpanel_port}" -j ACCEPT
        iptables -I INPUT -p udp -m state --state NEW -m udp --dport "${inpanel_port}" -j ACCEPT
        /etc/init.d/iptables save
    fi
    printf "${OK}\n"
}

# 获取IP地址
function fun_set_ip() {
    printf "${INP}: Checking Server IP..."
    ipaddress=$(curl -s http://ip.42.pl/raw)
    printf "${OK}\n"
    printf "${INP}: InPanel IP ${BLUE}${ipaddress}${NC}\n"
}

# 成功
function fun_success() {
    printf "${INP}:\n"
    printf "${INP}: ============================\n"
    printf "${INP}: *                          *\n"
    printf "${INP}: *     ${GREEN}INSTALL COMPLETED${NC}    *\n"
    printf "${INP}: *                          *\n"
    printf "${INP}: ============================\n"
    printf "${INP}:\n"
    printf "${INP}: The URL of InPanel is: \n"
    printf "${INP}: ${BLUE}http://${ipaddress}:${inpanel_port}${NC}\n"
    printf "${INP}:\n"
    printf "${INP}: ${GREENS}Wish you a happy life !${NC}\n"
    printf "${INP}:\n"
    printf "${INP}: ============${DARK}END${NC}=============\n"
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
