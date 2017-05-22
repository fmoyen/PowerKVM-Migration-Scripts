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

echo
echo "####################################################################"
echo "CREATING THE NETWORKS..."
echo

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
  BridgeName="Kb`echo $TrunkAdapter | cut -c 3-`-${VlanID}"

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

