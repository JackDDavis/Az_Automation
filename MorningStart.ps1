<#
.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.
#>

########################################################################################################
## CAT Lab Daily Start
# Author: Jack Davis

########################################################################################################

# Modifiable variables
$SubscriptionName   = 'Microsoft Azure Internal Consumption'
$tenant             = #tenant GUID
$RunAsAppId         = #RunAs ID
$RunAsCertThumb     = #RunAs Thumbpirnt
$rg                 = 'CAT_LitterBox' # targeted Resoure Group
$vmExcludes         = 'NDES' # , 'cmdpmp01', 'cmps01' #  VMs Exclusions

########################################################################################################

# Connect with RunAs account
Connect-AzAccount -ServicePrincipal -Tenant $tenant  -ApplicationId $RunAsAppId -CertificateThumbprint $RunAsCertThumb
Select-AzSubscription -SubscriptionName $SubscriptionName

########################################################################################################

$subscriptionId                 = (Get-AzSubscription -SubscriptionName $SubscriptionName).Id
$rgLocation                     = (Get-AzResourceGroup -Name $rg).Location
$resourceType                   = 'Microsoft.DevTestLab/schedules'
$scheduledShutdownRID           = "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/$resourceType/shutdown-computevm"
$azVMState                      = Get-AzVM -ResourceGroupName $rg -Status | Where-Object {$vmExcludes -notcontains $_.name} | Select-Object Name, PowerState # Current State of all virtual machines
$vmDesiredState                 = 'VM running'
$weekEnd                        = 'Saturday','Sunday' #Days in which you'd usually not schedule a lab run
$currentHour                    = (Get-Date).TimeOfDay.Hours
$workdayStart                   = 8 #8:00am
$workdayEnd                     = 19 #7:00pm

########################################################################################################

if (((Get-Date).DayOfWeek -notin $Weekend -and (($currentHour -ge $workdayStart) -and ($currentHour -lt $workdayEnd)))){
    foreach ($vm in $azVMState) {
        $VmName             = $vm.Name
        $VMResourceId       = (Get-AzVM -ResourceGroupName $rg -Name $VMName).Id
        $vmShutdownCheck    = "$scheduledShutdownRID-$vmName"
        $ipName             = "$vmName-ip"
        # Checks for & creates Auto-Shutdown policy if it doesn't exist
        if (-not (Get-AzResource -ResourceId "$vmShutdownCheck" -ErrorAction SilentlyContinue)) {
            Write-Verbose -Message "Creating Auto-Shutdown policy for $vmName" -Verbose
            $Properties = @{}
            $Properties.Add('status', 'Enabled')
            $Properties.Add('taskType', 'ComputeVmShutdownTask')
            $Properties.Add('dailyRecurrence', @{'time'= 2100})
            $Properties.Add('timeZoneId', "Eastern Standard Time")
            $Properties.Add('notificationSettings', @{status='Disabled'; timeInMinutes=15})
            $Properties.Add('targetResourceId', "$VMResourceId")
            
            New-AzResource -Location $rgLocation -ResourceId $ScheduledShutdownResourceId  -Properties $Properties  -Force
        }
        # Check PowerState for 'VM Running'
        if ($vm.PowerState -ne $vmDesiredState) {
            # Start virtual machine
            Start-AzVM -ResourceGroupName $rg -Name $VmName -Verbose
            $ipaddy = (Get-AzPublicIpAddress | Where-Object {$_.Name -eq $ipName}).IpAddress
            # Write updated status & list associated IP address
            Write-Verbose -Message "$VmName started successfully. Please connect using the following address: $ipaddy" -Verbose
        }
    }    
}