#!/bin/bash

RemoteKVM=cap
StoragePool=/sandbox/KVMMigration
ExcludedNetworks="default kop"

# Get the ID of the remote KVM and remove the double-quote if any
#    centos7: ID="centos"
#    ovirt 4: ID="centos"
#    ubuntu: ID=ubuntu
#    powerKVM: ID=ibm_powerkvm
temp=`ssh root@$RemoteKVM "grep \"^ID=\" /etc/os-release" | awk -F= '{print \$2}'`
temp="${temp%\"}"
RemoteID="${temp#\"}"

echo
echo "####################################################################"
echo
echo "the Remote system \"$RemoteKVM\" type is: $RemoteID"
echo

echo "####################################################################"
echo "IMPORTING THE NETWORKS TO THE DESTINATION..."
echo

echo
echo "--> getting the list of networks to import"
ListOfNetworks=""
for i in `virsh net-list --all | awk '{print $1}' | egrep -v 'Name|-------'`
do
  if [[ $ExcludedNetworks != *"$i"* ]]; then
    ListOfNetworks="$i $ListOfNetworks"
  fi
done
echo "Network List to Import : $ListOfNetworks"

echo "--> Generating the files needed to import the networks into $StoragePool/Networks"
mkdir -p $StoragePool/Networks
for i in $ListOfNetworks
do
  mkdir $StoragePool/Networks/$i
  virsh net-dumpxml $i > $StoragePool/Networks/$i/$i.xml
  Bridge=`virsh net-info $i | grep "^Bridge:" | awk -F: '{print $2}' | xargs`
  echo $Bridge > $StoragePool/Networks/$i/BridgeName
  VLANFile=`grep -l "BRIDGE=\"$Bridge\"" /etc/sysconfig/network-scripts/ifcfg-*`
  echo $VLANFile | awk -F"ifcfg-" '{print $2}' > $StoragePool/Networks/$i/VlanName
  awk -F. '{print $2}' $StoragePool/Networks/$i/VlanName > $StoragePool/Networks/$i/VlanID
done

echo "---> Copying the $StoragePool/Networks dir to the host $RemoteKVM"
rsync -av $StoragePool/Networks root@$RemoteKVM:$StoragePool

echo "---> Deleting $StoragePool/Networks from local source as not needed anymore"
rm -rf $StoragePool/Networks
