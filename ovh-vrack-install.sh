#!/bin/bash
#
# Configure Debian Server inside OVH VRACK (eg. nginx behind Cisco ACE LoadBalancer (LB))
#
# This script setups hostname, puppet, interfaces configuration and launch puppet.
#
# It assumes comes configured with an interface with a public IP ethX.
#
# This script setup a second interface connected to Virtual rack and 
# optional can set interface aliases for the public or private addresses.
#
# After setup install puppets and let it take care from there.
#
# To use it just copy it into a new server and run:
# ./ovh-vrack-install.sh HOST_FQDN VLAN_ID VLAN_ADDR [alias_inet_failover=IP_ADDRESS] [alias_vlan=IP_ADDRESS]
#
# It assumes everything. If VLAN address starts with 172.16, netmask is 255.40.0.0, if 10. is 255.0.0.0.
# Aliases can be repeated as much as you want
#
# Arguments:
# HOST_FQDN => Full Qualified Domain Name, eg: nsis.il.critical0.tguhost.com
# VLAN_ID => VLAN ID for OVH Virtual Rack        
# VLAN_ADDR => VLAN IP for nginx server to communicate with load balancer and virtual rack network.
# alias_inet_failover=IP_ADDRESS => Use this as many times as you want to add aliases to ethX configured as IP Failover
# alias_vlan=IP_ADDRESS => Use this as many times as you want to add aliases to VLAN. 
#
#
# Interfaces created by this script
# ethX.$VLAN_ID   => VLAN Interface
#


############# Script Config

# Read args
HOST_FQDN=$1
VLAN_ID=$2
VLAN_ADDR=$3

IF_FILE="/etc/network/interfaces"
IF_TEMPFILE="/tmp/interfaces"
IF_BACKUP="/etc/network/interfaces.pre-init"
HOSTS_BACKUP="/etc/hosts.pre-init"
HOSTNAME_BACKUP="/etc/hostname.pre-init"

NEXT_INET_ALIAS=0
NEXT_VLAN_ALIAS=0

PUPPET_SRV="puppet.guruhub.com.uy"
PUPPET_ENV="production"

IFACE=`ifconfig  |grep ^eth|awk '{ print $1 }'`

############# Script Functions

function validate_ip() {
	# It receives an IP and do a simple check
	# If second argument comes and it's '1' then will check IP belong to OVH VRACK Ranges.
	local ip=$1
	local stat=$1
	local vrack=$2
	if [[ "$1" == "" ]]; then
		return 1;
	fi
	if [[ $vrack -eq 1 ]]; then 
		VLAN_NETMASK=""
		if [[ $ip =~ ^172.16 ]]; then
			VLAN_NETMASK="255.240.0.0"
		elif [[ $ip =~ ^10. ]]; then
			VLAN_NETMASK="255.0.0.0"
		else 
			warndie "VLAN_ADDR does not match any known address range"
		fi
	fi
	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        	OIFS=$IFS
	        IFS='.'
	        ip=($ip)
	        IFS=$OIFS
	        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
        	    && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
	        stat=$?
    	fi
   	return $stat
}

function warndie() {
	local msg=$1
	echo "Error: $msg"
	show_usage
	exit 1
}

function show_usage() {
	echo 
	echo "Usage: $0 HOST_FQDN VLAN_ID VLAN_ADDR [alias_inet_failover=IP_ADDRESS] [alias_vlan=IP_ADDRESS]"
	echo 
	echo "Arguments:"
	echo " HOST_FQDN => Full Qualified Domain Name, eg: nsis.il.critical0.tguhost.com"
	echo " VLAN_ID => VLAN ID for OVH Virtual Rack"
	echo " VLAN_ADDR => VLAN IP for nginx server to communicate with load balancer and virtual rack network."
	echo " alias_inet_failover=IP_ADDRESS => Use this as many times as you want to add aliases to ethX."
	echo " alias_vlan=IP_ADDRESS => Use this as many times as you want to add aliases to VLAN."
	echo
}
	
############# FIRST: Validate...
# 
#
# Check host_fqdn is comming
if [ "$HOST_FQDN" == "" ]; then
	warndie "FQDN not recognized..."
fi
# Check the smell it's not our own shit
if `grep -q "Starts interfaces configuration done automagically by" $IF_FILE`; then
	warndie "Mmmmm... No, thanks. I already saw this movie"
fi
if ! validate_ip $VLAN_ADDR 1; then
	warndie "VLAN_ADDR not valid, received: '$VLAN_ADDR'"
fi

echo "Arguments validation OK!"

###### SECOND: Backup everything it's going to be changed

FIXED_RANDOM=$RANDOM
# Save interfaces backup
if [ -f "$IF_BACKUP" ]; then 
	IF_BACKUP="/tmp/interfaces.pre-init."$FIXED_RANDOM
	echo "Backup already exist, interfaces backup saved into $IF_BACKUP instead."
fi
cp /etc/network/interfaces $IF_BACKUP

# Save hosts backup
if [ -f "$HOSTS_BACKUP" ]; then 
	HOSTS_BACKUP="/tmp/interfaces.pre-init."$FIXED_RANDOM
	echo "Backup already exist, interfaces backup saved into $HOSTS_BACKUP instead."
fi
cp /etc/hosts $HOSTS_BACKUP

# Save hostnames backup
if [ -f "$HOSTNAME_BACKUP" ]; then 
	HOSTNAME_BACKUP="/tmp/hostname.pre-init."$FIXED_RANDOM
	echo "Backup already exist, interfaces backup saved into $HOSTNAME_BACKUP instead."
fi
cp /etc/hostname $HOSTNAME_BACKUP


# Remove old temp if any
if [ -f "$IF_TEMPFILE" ]; then
	rm -f $IF_TEMPFILE
fi

####### Fun starts now!
#
# Enable vlan support if not already done
if [ ! -f "/proc/sys/net/ipv4/conf/${IFACE}.${VLAN_ID}/proxy_arp_pvlan" ]; then
	vconfig add $IFACE $VLAN_ID
fi


today=`date`

# Add header to interfaces temp file.
echo "
#
# Starts interfaces configuration done automagically by $0
# Script run on $today (version last update from puppet-setup.git/debian/)
# 
" >> $IF_TEMPFILE

# We need to add first all aliases of ethX if any before vrack IP's.
for argument in "$@"
do
	if [[ $argument =~ ^alias_inet_failover ]]; then
		# User want more IP's fail over configured for internet traffic.
		IP_ADDR=""
		IP_ADDR=`echo $argument|awk -F '=' '{ print $2 }'`
		if ! validate_ip $IP_ADDR; then
			warndie "Extra FailOver IP NOT VALID, received IP='$IP_ADDR'"
		fi
		# Add interface alias for this IP.
		echo "# Alias #$NEXT_INET_ALIAS interface for direct internet IP Failover
auto $IFACE:$NEXT_INET_ALIAS
iface $IFACE:$NEXT_INET_ALIAS inet static
        address $IP_ADDR
        netmask 255.255.255.255
#" >> $IF_TEMPFILE

		NEXT_INET_ALIAS=$(( $NEXT_INET_ALIAS + 1 ))
		
	fi
done

# Add Vlan Interface
echo "
# Vlan Interface for Virtual Rack traffic
auto $IFACE.$VLAN_ID
iface $IFACE.$VLAN_ID inet static
        address $VLAN_ADDR
        netmask $VLAN_NETMASK
        vlan_raw_device $IFACE
#
" >> $IF_TEMPFILE

VLAN_NETMASK_USED=$VLAN_NETMASK

# We need to add all aliases of vlan if any
for argument in "$@"
do
	if [[ $argument =~ ^alias_vlan ]]; then
		# User want more IP's fail over configured for internet traffic.
		IP_ADDR=""
		IP_ADDR=`echo $argument|awk -F '=' '{ print $2 }'`
		VLAN_NETMASK=""
		if ! validate_ip $IP_ADDR 1; then
			warndie "Extra VLAN IP NOT VALID, received IP='$IP_ADDR'"
		fi
		# Would current route support this new interface IP? We need to know
		# if this is the first time we are referring to these segment or not.
		# If true, a propper netmask should be added to get linux create the 
		# routes for us.
		for nm in $VLAN_NETMASK_USED; do
			if [ "$VLAN_NETMASK" == "$nm" ]; then
				# We already configured this netmask, no netmask then.
				VLAN_NETMASK="255.255.255.255"
			else
				VLAN_NETMASK_USED="$VLAN_NETMASK_USED $VLAN_NETMASK"
			fi
		done
		
		# Add interface alias for this IP.
		echo "
# Vlan Interface for Load Balancer traffic Version IL:
auto $IFACE.$VLAN_ID:$NEXT_VLAN_ALIAS
iface $IFACE.$VLAN_ID:$NEXT_VLAN_ALIAS inet static
        address $IP_ADDR
        netmask $VLAN_NETMASK
        vlan_raw_device $IFACE
" >> $IF_TEMPFILE
		
		NEXT_VLAN_ALIAS=$(( $NEXT_VLAN_ALIAS + 1 ))
	fi
done

# Configure FQDN
echo $HOST_FQDN > /etc/hostname
/bin/hostname -F /etc/hostname

# Regenerate ssh keys for host
rm /etc/ssh/ssh_host* -f
dpkg-reconfigure openssh-server


# Configure basic hosts
echo "127.0.0.1   $HOST_FQDN localhost

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
" > /etc/hosts

# Add backports repository to use puppet 2.8.18 from there
echo 'deb http://backports.debian.org/debian-backports squeeze-backports main' >> /etc/apt/sources.list.d/backports.list

# On fresh OVH servers usually there is a missing upgrade on mdadm that will 
# popup debconf questions, next line came to avoid that:

debconf-set-selections <<EOF
# Do you want to start MD arrays automatically?
mdadm mdadm/autostart boolean false
# MD arrays needed for the root filesystem:
mdadm mdadm/initrdstart string none
EOF

apt-get update
apt-get upgrade -y
apt-get install -y git-core

# for puppet 2.7.18
# http://raphaelhertzog.com/2010/09/21/debian-conffile-configuration-file-managed-by-dpkg/
apt-get -o Dpkg::Options::="--force-confnew" -t squeeze-backports install -y puppet

sleep 10

cat <<EOF > /etc/puppet/puppet.conf
[main]
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=$vardir/lib/facter
templatedir=$confdir/templates
server=this_server
runinterval=1800
pluginsync=true
report=true

[agent]
pluginsync=true
report=true
environment=this_env
EOF

sed -i "s/this_env/$PUPPET_ENV/" /etc/puppet/puppet.conf
sed -i "s/this_server/$PUPPET_SRV/" /etc/puppet/puppet.conf
sed -i 's/START=no/START=yes/' /etc/default/puppet

# Append new interface config
cat $IF_TEMPFILE >> $IF_FILE
# Restart network configuration
/etc/init.d/networking restart

# Launch puppet
puppetd

