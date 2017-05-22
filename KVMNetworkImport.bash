#!/bin/bash

StoragePool=/sandbox/KVMMigration

if [ $# -eq 1 ]
then
  TrunkAdapter=$1
else
  echo
  echo "Please give the Trunk adapter (Ex: enP3p3s0f0)"
  echo
  exit 1
fi

# Get the ID of the local KVM and remove the double-quote if any
#    centos7: ID="centos"
#    ovirt 4: ID="centos"
#    ubuntu: ID=ubuntu
#    powerKVM: ID=ibm_powerkvm
temp=`grep "^ID=" /etc/os-release | awk -F= '{print \$2}'`
temp="${temp%\"}"
LocalID="${temp#\"}"

echo "####################################################################"
echo
echo "the Local system type is: $LocalID"
echo

echo
echo "####################################################################"
echo "CREATING THE SYSTEM NETWORKS..."
echo

if [ $LocalID == "centos" ]
then
  echo "---> Deactivating the NetworkManager"
  systemctl stop NetworkManager
  systemctl disable NetworkManager
  echo "---> Deactivating the interface $TrunkAdapter from /etc/sysconfig/network-scripts/ifcfg-$TrunkAdapter"
  sed -i.ORIGIN "/^ONBOOT/d" /etc/sysconfig/network-scripts/ifcfg-$TrunkAdapter
  echo "ONBOOT=no" >> /etc/sysconfig/network-scripts/ifcfg-$TrunkAdapter

  echo "---> Generating the \"ifcfg\" files needed into /etc/sysconfig/network-scripts/"
  for NetworkName in `cd $StoragePool/Networks; ls -d *`
  do
    VlanNameOLD=`cat $StoragePool/Networks/$NetworkName/VlanName`
    BridgeNameOLD=`cat $StoragePool/Networks/$NetworkName/BridgeName`

    VlanID=`cat $StoragePool/Networks/$NetworkName/VlanID`
    VlanName="${TrunkAdapter}.${VlanID}"
    BridgeName="kb`echo $TrunkAdapter | cut -c 3-`-${VlanID}"

    cat <<EOT >> /etc/sysconfig/network-scripts/ifcfg-${VlanName}
DEVICE="${VlanName}"
VLAN="yes"
ONBOOT="yes"
BRIDGE="${BridgeName}"
EOT

    cat <<EOT >> /etc/sysconfig/network-scripts/ifcfg-${BridgeName}
DEVICE="${BridgeName}"
ONBOOT="yes"
TYPE="Bridge"
EOT

   sed "s/$BridgeNameOLD/$BridgeName/g" $StoragePool/Networks/$NetworkName/$NetworkName.xml > $StoragePool/Networks/$NetworkName/${NetworkName}-NEW.xml
  done

  echo "---> Restarting the network/libvirt/qemu daemons"
  systemctl restart network
  systemctl restart libvirtd

elif [ $LocalID == "ubuntu" ]
then
  echo "---> Removing the interface $TrunkAdapter from /etc/network/interfaces"
  sed  -i.ORIGIN "/$TrunkAdapter/,/^\s*$/{d}" /etc/network/interfaces
  echo "---> Check /etc/network/interfaces.d is included into /etc/network/interfaces"
  grep 'source /etc/network/interfaces.d/\*.cfg' /etc/network/interfaces > /dev/null 2>&1
  if [ `echo $?` -ne 0 ]
  then
    echo "source /etc/network/interfaces.d/*.cfg" >> /etc/network/interfaces
  fi

  echo "---> Generating the files needed into /etc/network/interfaces.d"
  for NetworkName in `cd $StoragePool/Networks; ls -d *`
  do
    VlanNameOLD=`cat $StoragePool/Networks/$NetworkName/VlanName`
    BridgeNameOLD=`cat $StoragePool/Networks/$NetworkName/BridgeName`
  
    VlanID=`cat $StoragePool/Networks/$NetworkName/VlanID`
    VlanName="${TrunkAdapter}.${VlanID}"
    BridgeName="kb`echo $TrunkAdapter | cut -c 3-`-${VlanID}"
  
    cat <<EOT >> /etc/network/interfaces.d/${VlanName}.cfg
auto ${VlanName}
iface ${VlanName} inet manual
   vlan-raw-device $TrunkAdapter
EOT
  
    cat <<EOT >> /etc/network/interfaces.d/${BridgeName}.cfg
auto $BridgeName
iface $BridgeName inet manual
    bridge_ports ${VlanName}
    bridge_stp off
EOT
  
   sed "s/$BridgeNameOLD/$BridgeName/g" $StoragePool/Networks/$NetworkName/$NetworkName.xml > $StoragePool/Networks/$NetworkName/${NetworkName}-NEW.xml
  done
  
  echo "---> Restarting the network/libvirt/qemu daemons"
  systemctl restart networking 
  systemctl restart libvirt-bin.service
  systemctl restart qemu-kvm.service
  systemctl restart libvirtd.service
fi

echo
echo "####################################################################"
echo "DEFINING THE VIRSH NETWORKS..."
echo

echo "---> Creating the networks under virsh"
for NetworkName in `cd $StoragePool/Networks; ls -d *`
do
  virsh net-define $StoragePool/Networks/$NetworkName/${NetworkName}-NEW.xml
  virsh net-autostart ${NetworkName}
  virsh net-start ${NetworkName}
done
virsh net-list --all
  
echo "---> Deleting $StoragePool/Networks as not needed anymore"
rm -rf $StoragePool/Networks
  
