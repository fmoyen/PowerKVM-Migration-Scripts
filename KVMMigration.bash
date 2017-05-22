#!/bin/bash

RemoteKVM=cap
StoragePool=/sandbox/KVMMigration

# Get the ID of the remote KVM and remove the double-quote if any
#    centos7: ID="centos"
#    ovirt 4: ID="centos"
#    ubuntu: ID=ubuntu
#    powerKVM: ID=ibm_powerkvm
temp=`ssh root@$RemoteKVM "grep \"^ID=\" /etc/os-release" | awk -F= '{print \$2}'`
temp="${temp%\"}"
RemoteID="${temp#\"}"

# Specific case: HostOS (which is centos)
if [ $RemoteID == "centos" ]
then
  if ssh root@$RemoteKVM "test -e /etc/open-power-host-os-release"
  then
    RemoteID="hostos"
  fi
fi

clear
echo "####################################################################"
echo
echo "the Remote system \"$RemoteKVM\" type is: $RemoteID" 
echo

if [ $# -eq 1 ]
then 
  ListOfVMs=$1
else
  ListOfVMs=`virsh list --all --name | grep KVM`
fi

echo "####################################################################"
echo "MIGRATING..."
echo
echo "Please find hereunder the list of VMs that are going to be migrated to the host $RemoteKVM"
echo
echo -e " --> \c"; echo $ListOfVMs
echo
echo "Do you confirm ? (CTRL+C if not)"
read a
echo "OK... Migrating"


for i in $ListOfVMs
do
  echo
  echo "#################################################"
  echo $i
  echo "#################################################"

  #-----------------------------------------------------------------------------------------------------------------------------------------
  # Source : Stop the VM, Generate the xml files, copy them to Destination

  echo "---> Stopping $i"
  virsh destroy $i >/dev/null 2>&1
  echo "---> Dumping $i into $StoragePool/$i.SOURCE.xml"
  virsh dumpxml $i > $StoragePool/$i.SOURCE.xml

  # Generate the List of Snapshots in the right order (snapshot-list --tree order)
  # (needed when recreating snapshots, roots need to be created before leaves)
  ListOfSnaps=""
  for snap in `virsh snapshot-list $i --roots --name;virsh snapshot-list $i --tree | awk -F"+-" '{print $2}'`
  do
    ListOfSnaps="$ListOfSnaps $snap"
  done

  if [ "$ListOfSnaps" != "" ]
  then
    echo "---> Dumping the following snapshots: $ListOfSnaps"
    for snap in $ListOfSnaps
    do
      virsh snapshot-dumpxml $i $snap > $StoragePool/$i.SNAP.$snap.SOURCE.xml
    done

    echo -e "---> saving the \"current\" snapshot: \c"
    Current=`virsh snapshot-current $i --name 2>/dev/null`
    echo $Current

  else
    echo "---> No Snapshot defined for the VM"
  fi



  #-----------------------------------------------------------------------------------------------------------------------------------------
  # Source : Adapt the xml files to the new Host OS

  echo "---> Adapting the xml files to the new OS of type $RemoteID"
  if [ $RemoteID == "centos" ]
  then
    sed 's:/usr/bin/qemu-kvm:/usr/libexec/qemu-kvm:g' $StoragePool/$i.SOURCE.xml > $StoragePool/$i.tempo.xml
    sed 's:pseries-2.4:pseries:g' $StoragePool/$i.tempo.xml > $StoragePool/$i.xml
  elif [ $RemoteID == "ubuntu" ]
  then
    sed 's:/usr/bin/qemu-kvm:/usr/bin/kvm:g' $StoragePool/$i.SOURCE.xml > $StoragePool/$i.tempo.xml
    sed 's:pseries-2.4:pseries:g' $StoragePool/$i.tempo.xml > $StoragePool/$i.xml # Optional as pseries-2.4 exists in Ubuntu (benfits from the latest and default machine type)
  elif [ $RemoteID == "hostos" ]
  then
    sed 's:pseries-2.4:pseries:g' $StoragePool/$i.SOURCE.xml > $StoragePool/$i.xml
  fi

  if [ "$ListOfSnaps" != "" ]
  then
    for snap in `echo $ListOfSnaps`
    do
      if [ $RemoteID == "centos" ]
      then
        sed 's:/usr/bin/qemu-kvm:/usr/libexec/qemu-kvm:g' $StoragePool/$i.SNAP.$snap.SOURCE.xml > $StoragePool/$i.SNAP.$snap.tempo.xml
        sed 's:pseries-2.4:pseries:g' $StoragePool/$i.SNAP.$snap.tempo.xml > $StoragePool/$i.SNAP.$snap.xml
      elif [ $RemoteID == "ubuntu" ]
      then
        sed 's:/usr/bin/qemu-kvm:/usr/bin/kvm:g' $StoragePool/$i.SNAP.$snap.SOURCE.xml > $StoragePool/$i.SNAP.$snap.tempo.xml
        sed 's:pseries-2.4:pseries:g' $StoragePool/$i.SNAP.$snap.tempo.xml > $StoragePool/$i.SNAP.$snap.xml # Optional as pseries-2.4 exists in Ubuntu (benfits from the latest and default machine type)
      elif [ $RemoteID == "hostos" ]
      then
        sed 's:pseries-2.4:pseries:g' $StoragePool/$i.SNAP.$snap.SOURCE.xml > $StoragePool/$i.SNAP.$snap.xml
      fi
    done
  fi

  rm -f $StoragePool/${i}*.tempo.xml
  rm -f $StoragePool/${i}*.SOURCE.xml

  echo "---> Copying the $i disk files to the host $RemoteKVM"
  rsync -av --exclude="*.xml" $StoragePool/$i.* root@$RemoteKVM:$StoragePool

  #-----------------------------------------------------------------------------------------------------------------------------------------
  # Destination : Create the VM, Recreate the snapshots, Point to current snapshot, Start the VM

  echo "---> Creating the $i VM onto the host $RemoteKVM"
  virsh -c qemu+ssh://root@$RemoteKVM/system define $StoragePool/$i.xml

  echo "---> Recreating the $i snapshots onto the host $RemoteKVM"
  for snap in `echo $ListOfSnaps`
  do
    if [ $snap == $Current ]
    then
      virsh -c qemu+ssh://root@$RemoteKVM/system snapshot-create $i $StoragePool/$i.SNAP.$snap.xml --redefine --current
      echo " ($snap is the current snapshot for $i VM)"
    else
      virsh -c qemu+ssh://root@$RemoteKVM/system snapshot-create $i $StoragePool/$i.SNAP.$snap.xml --redefine
    fi
  done

  echo "---> Deleting the $i xml files as they are not needed anymore"
  rm -f $StoragePool/$i*.xml

  echo "---> Starting the $i VM onto the host $RemoteKVM"
  virsh -c qemu+ssh://root@$RemoteKVM/system start $i
  echo "-----------------------------------------------------------------"
  echo
done


echo "####################################################################"
echo "DELETING FROM THE SOURCE..."
echo
echo "Now is time to CTRL-C if you don't want to delete VMs from the source"
read a
echo "OK... Deleting"
for i in $ListOfVMs
do
  virsh undefine --snapshots-metadata $i
  rm $StoragePool/$i.*
done
echo
echo "ls -la $StoragePool"
ls -la $StoragePool/
echo

