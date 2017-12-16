# Global Config
#$volumes = @("TUK-NonReplicated-NI","TUK-Exchange16-A-NI","TUK-Exchange16-B-NI")
$vms = @("[TUK-NONREPLICATED-NI] TUK-AD03/TUK-AD03.vmx","[TUK-NONREPLICATED-NI] TUK-GC03/TUK-GC03.vmx","[TUK-EXCHANGE16-A-NI] TUK-EXCH1601/TUK-EXCH1601.vmx","[TUK-EXCHANGE16-A-NI] TUK-EXCH1602/TUK-EXCH1602.vmx","[TUK-EXCHANGE16-B-NI] TUK-EXCH1603/TUK-EXCH1603.vmx","[TUK-EXCHANGE16-B-NI] TUK-EXCH1604/TUK-EXCH1604.vmx")
$volumes = @("TESTLABTEST")
$initiatorname = "TESTLAB"
$labHost = "tuk-vm26.columbiabank.com"
$snapname = "testlabsnapshot"
# Connection Information
#Testing loops
foreach ($volume in $volumes) {
    
    #Declarations
    $newVolume = "$volume-CLONE"
    
    write-host "We will clone $volume using a snapshot named $snapname to $newVolume"
    write-host "we will be removing the initiators from $newVolume and adding the initiator group $initiatorname"
    write-host "we will be renaming the resulting snapshot datastore using " + 'snap*volume'
    write-host "We should return no datastores: "
    get-datastore -name "snap*$volume" 
    write-host "if any datastores are above, abort"
    write-host ""
}
write-host ""
foreach ($vm in $vms) {
    
    #Extract vm and datastore
    $vmreg = $vm -match '^\[(?<DATASTORE>.+)\].+\/(?<VMNAME>.+)\.vmx$'
    $newDatastoreName = "[" + $Matches.DATASTORE + "-CLONE" + "]"
    $newVMName = $Matches.VMNAME + "-CLONE"
    $VMName = $Matches.VMNAME + "-CLONE"
    # Set a variable with the VM path
    $newPath = $vm -replace "\[.+\]", $newDatastoreName
    
    write-host "we will be adding $newPath to inventory with the name $VMName to $labhost"
    write-host "the following should not return any production results: "
    try 
        {
            get-vm -name $newVMname -erroraction stop
            write-host "Found $newVMname"
        }
    catch
        {
           write-host "Found nothing!"
        } 
    write-host ""
}
$answer = read-host 'Continue (y/n)? '
if ($answer -ne 'y') {break}

write-host "continued"


# Clone and Present Volumes
foreach ($volume in $volumes) {
    
    if ($volume -eq "") {break}
    
    #Declarations
    $newVolume = "$volume-CLONE"
    
    #Test Section
    write-host "$volume"
    write-host "$newVolume"
    
    
    #Create nimble snapshot and load in to a variable
    $snap = New-NSSnapshot -name $snapname -vol_id $(Get-NSVolume -name $volume).id
    
    # I don't think we need this
    #$snap = Get-NSSnapshot -vol_name TESTLABTEST -name testsnapshot
    
    #Clone volumes from snapshot
    New-NSClone -name "$newVolume" -base_snap_id $snap.id -clone $true
    
    # remove all access records of new volume
    Get-NSAccessControlRecord | Where-Object {$_.vol_name -eq "$newVolume"} | %{remove-NSaccessControlRecord -id $_.id}
    
    #Add $initiatorName to new cloned volume
    New-NSAccessControlRecord -vol_id $(Get-NSVolume -name "$newVolume").id -initiator_group_id $(Get-NSInitiatorGroup -name $initiatorName).id
    Set-NSVolume -name "$newVolume" -online:$true
    
    #Rescan the HBA
    Get-VMhost -name $labHost| Get-VMHostStorage -RescanAllHba
    
    # Resignature volume
    $esxcli = get-esxcli -vmhost $labHost
    start-sleep -seconds 5
    $esxcli.storage.vmfs.snapshot.resignature("$volume")
    
    
    #Rename Volume
    start-sleep -seconds 5
    
    get-datastore -name "snap*$volume"  | set-datastore -name $newVolume
    
    
}
#Add VMs to inventory
foreach ($vm in $vms) {
    
    if ($vm -eq "") {break}
    
    #Extract vm and datastore
    $vmreg = $vm -match '^\[(?<DATASTORE>.+)\].+\/(?<VMNAME>.+)\.vmx$'
    $newDatastoreName = "[" + $Matches.DATASTORE + "-CLONE" + "]"
    $newVMName = $Matches.VMNAME + "-CLONE"
    $VMName = $Matches.VMNAME + "-CLONE"
    # Set a variable with the VM path
    $newPath = $vm -replace "\[.+\]", $newDatastoreName
    
    # Add VM to inventory
    new-vm -VMFilepath $newpath -vmhost $labhost -name $newVMName
    # Fix the network adapter
    start-sleep -seconds 2
    $oldNetworkAdapter = get-vm -name $newVMname | get-networkadapter
    $newNetworkAdapter = "ISOLATED-" + $oldNetworkAdapter.NetworkName
    get-vm -name $newVMname | get-networkadapter | set-networkadapter -portgroup $newNetworkAdapter 
}




#Other examples of spinning down the lab:
#Stop VM
#get-vm -name gameserver-clone |stop-vm
#get-vm -name gameserver-clone |remove-inventory -confirm:$false
#Remove a datastore
#get-datastore -name snap-* |remove-datastore -confirm:$false -vmhost esx2.lab.local
#Insert remove LUN from storage commands
# Rescan Datastore
#Get-Cluster -Name “Production” | Get-VMHost | Get-VMHostStorage -RescanAllHba
# Starting the VM and answering the questions
#get-vm -name gameserver-clone |start-vm
#get-vm -name gameserver-clone |Get-VMQuestion | Set-VMQuestion –defaultoption -confirm:$false
