<#

.SYNOPSIS
This script shuts down XenServer pools and specified storage servers, designed for use with Powerchute Network Shutdown.

.DESCRIPTION
The script uses the XenServer powershell module to shutdown each VM in a pool, then each slave host, then finally the pool master for each specified pool. 
It then uses plink to remotely shutdown specified storage servers.

.EXAMPLE
./shutdown.ps1 192.168.100.200 172.16.2.45 10.10.10.6

.NOTES
The only required argument is the URL parameter - the IPs of any pool masters to be shutdown, separated by spaces 

#>
<#
The script relies on a file called 'securestring.txt' existing in the same folder as the script itself and containing the Xen host password.
To generate this file:
read-host -assecurestring | convertfrom-securestring | out-file %PATH_OF_SCRIPT\securestring.txt
Then type the password and press enter.

It also relies on the Powershell modules for XenServer from the XenServer SDK and plink.exe existing in System32.
#>
#Set log path
$path = "$psscriptroot\$(get-date -format yyyy-MM-dd-HHmm)"
#Create log directory - output to null to prevent spamming the console
mkdir $path >>$null
#Set log file
$log = "$path\Shutdown.log"
#Import secure password from script root directory
$password = cat $psscriptroot\securestring.txt | convertto-securestring
#Define a variable containing the scriptblock to be used to shut down each pool as a separate job
$xenkill = 
	{
	#Define parameters passed to the scriptblock
	param($master,$path,$username,$password)
	#Set log file
	$log = "$path\$master.log"
	#Add http:// to the begginning of the string containing the master IP address
	$master = $master.insert(0,'http://')
	#Create credential PSObject
	$creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
	#Import Xenserver module 
	Import-Module XenServerPSModule
	#Connect to XenServer
	"$(Get-Date -f "HH:mm:ss") - Connecting to Xenhost $master" >> $log
	try
		{
		connect-xenserver -url $master -creds $creds
		}
	catch
		{
		"$(Get-Date -f "HH:mm:ss") - $master -  Connecting to Xenhost $args FAILED - error returned: $($_)" >> $log; 
		exit
		}
	#Define a variable containing the scriptblock to be used to shut down each VM as a separate job.
	$script = 
		{
		#Define parameters passed to the scriptblock
		param($ip,$creds,$vm,$log,$pool)
		#Connect to XenServer
		connect-xenserver -url $ip -creds $creds
		#Shutdown vm specified in parameter $vm
		try
			{
			get-xenvm $vm.name_label | invoke-xenvm -xenaction cleanshutdown
			}
		catch
			{
			"$(Get-Date -f "HH:mm:ss") - $pool - Shutting down $($vm.name_label) FAILED - error returned: $($_)" >> $log; 
			exit
			}
		}
	#Define a variable containing the pool name for logging
	$pool = @(get-xenpool).name_label
	#Check if $pool is null - may be a standalone host - if so use the hosts name in place of the pool name
	if(!$pool)
		{
		$pool = @(get-xenhost).name_label
		}
	#Shutdown all running VMs but not control domain VMs:
	"$(Get-Date -f "HH:mm:ss") - $pool - Launching VM shutdown jobs" >> $log
	foreach($vm in get-xenvm | where{$_.power_state -eq "Running" -and $_.is_control_domain -eq $false}) 
		{
		"$(Get-Date -f "HH:mm:ss") - $pool - Shutting down $($vm.name_label)" >> $log;
		start-job $script -args $master,$creds,$vm,$log,$pool
		} 
	#Wait until all jobs have finished and VM's are offline
	get-job | wait-job
	"$(Get-Date -f "HH:mm:ss") - $pool - VMs offline. Disabling slave hosts" >> $log
	#Disable all hosts in pool but not master:	
	try
		{
		get-xenhost | where{$_.opaque_ref -ne @(Get-XenPool).master.opaque_ref} | invoke-xenhost -xenaction disable
		}
	catch
		{
		"$(Get-Date -f "HH:mm:ss") - Disabling slave host $($_.name_label) FAILED - error returned: $($_)" >> $log
		}
	"$(Get-Date -f "HH:mm:ss") - $pool - Slave hosts disabled. Shutting down slave hosts" >> $log
	#Shutdown all hosts in pool but not master:
	try
		{
		get-xenhost | where{$_.opaque_ref -ne @(Get-XenPool).master.opaque_ref} | invoke-xenhost -xenaction shutdown
		}
	catch
		{
		"$(Get-Date -f "HH:mm:ss") - Shutting down slave host $($_.name_label) FAILED - error returned: $($_)" >> $log
		}
	"$(Get-Date -f "HH:mm:ss") - $pool - Slave hosts offline. Disabling pool master" >> $log
	#Disable pool master:
	try
		{
		get-xenhost @(Get-XenPool).master | invoke-xenhost -xenaction disable
		}
	catch
		{
		"$(Get-Date -f "HH:mm:ss") - Disabling pool master $args FAILED - error returned: $($_)" >> $log
		}
	"$(Get-Date -f "HH:mm:ss") - $pool - Pool master disabled. Shutting down pool master" >> $log
	#Shutdown pool master:
	try
		{
		get-xenhost @(Get-XenPool).master | invoke-xenhost -xenaction shutdown
		}
	catch
		{
		"$(Get-Date -f "HH:mm:ss") - Shutting down pool master $args FAILED - error returned: $($_)" >> $log
		}
	#Disconnect
	disconnect-xenserver
	#Rename log file to pool name
	mv $log $path\$pool.log
	}

#Loop through IP addresses provided as arguments to the script
foreach($addr in $args)
	{
	"$(Get-Date -f "HH:mm:ss") - Starting pool shutdown on master $addr" >> $log
	#Launch scriptblock to shutdown the pool
	start-job $xenkill -args $addr,$path,"root",$password
	}
"$(Get-Date -f "HH:mm:ss") - Shutdown started on all specified pools, awaiting completion" >> $log
Write-Host "Waiting for all pool masters to be offline..."
get-job | wait-job