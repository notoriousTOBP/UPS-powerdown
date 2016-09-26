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
	$username = "root"
#Import secure password
	$password = cat $psscriptroot\securestring.txt | convertto-securestring
#Create credential PSObject
	$creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
#Import Xenserver module 
	Import-Module XenServerPSModule
#Connect to XenServer
	connect-xenserver -url $args[0] -creds $creds
get-xenvm | where{$_.power_state -eq "Running" -and $_.name_label -notlike "Control domain*"} | select name_label >>c:\test.txt
disconnect-xenserver
