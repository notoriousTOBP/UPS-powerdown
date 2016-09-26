<#

.SYNOPSIS
This script shuts down a XenServer Pool, designed for use with Powerchute Network Shutdown.

.DESCRIPTION
The script uses the XenServer powershell module to shutdown each VM in a pool, then each slave host, then finally the pool master.

.EXAMPLE
./xen_shutdown.ps1 http://192.168.100.200

.NOTES
The only required argument is the URL parameter - the IP of the pool master including 'http://'.

#>
<#
The script relies on a file called 'securestring.txt' existing in the same folder as the script itself and containing the Xen host password.
To generate this file:
read-host -assecurestring | convertfrom-securestring | out-file %PATH_OF_SCRIPT\securestring.txt
Then type the password and press enter.

It also relies on the Powershell modules for XenServer from the XenServer SDK.
#>

	$username = "root"
#Import secure password
	$password = cat $psscriptroot\securestring.txt | convertto-securestring
#Create credential PSObject
	$creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
#Import Xenserver module 
	Import-Module XenServerPSModule
#Connect to XenServer
	connect-xenserver -url $args[0] -creds $creds
#Shutdown all running VMs but not control domain VMs:
	get-xenvm | where{$_.power_state -eq "Running" -and $_.name_label -notlike "Control domain*"} | invoke-xenvm -xenaction CleanShutdown
#Disable all hosts in pool but not master:
	get-xenhost | where{$_.opaque_ref -ne @(Get-XenPool).master.opaque_ref} | invoke-xenhost -xenaction disable
#Shutdown all hosts in pool but not master:
	get-xenhost | where{$_.opaque_ref -ne @(Get-XenPool).master.opaque_ref} | invoke-xenhost -xenaction shutdown
#Disable pool master:
	get-xenhost @(Get-XenPool).master | invoke-xenhost -xenaction disable
#Shutdown pool master:
	get-xenhost @(Get-XenPool).master | invoke-xenhost -xenaction shutdown
#Disconnect
	disconnect-xenserver