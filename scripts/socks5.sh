#!/bin/sh
random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c15
	echo
}
NETWORK_INTERFACE_NAME=$(ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/0.8.13.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.8.13
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    touch /usr/local/etc/3proxy/3proxy.pid
    groupadd --gid 65535 3proxy
    useradd --uid 65535 --gid 3proxy -s /bin/false -l -M 3proxy
    chown 65535:65535 /usr/local/etc/3proxy/3proxy.pid
    chkconfig 3proxy on
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
pidfile /usr/local/etc/3proxy/3proxy.pid
nserver 8.8.8.8
maxconn 500
nscache 65536
nscache6 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 262144
flush
auth none
$(awk -F "/" '{print "auth none\n" \
"socks -6 -n -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig '${DEFAULTNET}' inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}
#echo "Disable firewall"
#systemctl stop firewalld && systemctl disable firewalld && systemctl stop 3proxy && systemctl disable 3proxy
echo "installing apps"
yum -y install gcc make wget net-tools bsdtar zip >/dev/null

install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
DEFAULTNET=$(ip -o -4 route show to default | awk '{print $5}')
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(ip addr show dev ${NETWORK_INTERFACE_NAME} | sed -e's/^.*inet6 \([^ ]*\)\/.*$/\1/;t;d' | head -1| cut -f1-4 -d':')

echo "Default net interface = ${DEFAULTNET}"
echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))
firewall-cmd --zone=public --permanent --add-port ${FIRST_PORT}-${LAST_PORT}/tcp
firewall-cmd --reload
gen_data >$WORKDIR/data.txt
#gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/sysctl.conf <<EOF
fs.file-max=500000
EOF

sysctl -w fs.file-max=500000
sysctl -p

cat >>/etc/rc.local <<EOF
#bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65536
service 3proxy start
EOF

bash /etc/rc.local

gen_proxy_file_for_user

zip ${WORKDIR}/proxy.zip proxy.txt
echo "Done! ${WORKDATA}"

#upload_proxy
