These scripts are provided as-is. They are provided only in order to illustrate a way to automate the migration of several VMs from an IBM PowerKVM 3.1 system to a “distribution standard” KVM system.
The author of this technical guide will neither provide any support for these scripts nor be responsible for any virtual machines lost when using these scripts.

The scripts are available in those two repositories:

*https://gitlab.com/fmoyen/PowerKVM-Migration-Scripts
*https://github.com/fmoyen/PowerKVM-Migration-Scripts

## Variables / notes
*RemoteKVM :* The hostname (or IP address) of the KVM destination host

*StoragePool :* the directory where the virtual machines disk images reside

##KVMNetworkExport.bash

Purpose :

KVMNetworkExport.bash (which needs to be run onto the PowerKVM system) will gather the libvirt networks definitions and will copy them onto the KVM destination Host.
KVMNetworkImport.bash will then need to be run onto the KVM destination Host in order to redefine the libvirt networks.

##KVMNetworkImport.bash

Purpose :

KVMNetworkImport.bash (which needs to be run onto the KVM destination system) will use the libvirt network definitions (collected using the KVMNetworkExport.bash script) in order to recreate all these libvirt networks.

##KVMNetworkImport.bash

Purpose :

KVMNetworkImport.bash (which needs to be run onto the KVM destination system) will use the libvirt network definitions (collected using the KVMNetworkExport.bash script) in order to recreate all these libvirt networks.
