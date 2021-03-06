######################################################
# Name: VMBackup to External Storage [CloneWars.ps1] #
# Desc: Backups VMs from CSV & Exports to Filer      #
######################################################
#                                                    #
# *Reads CSV                                         #
# *Gets VMs Home Datastore							 #						
# *Performs Snapshot								 #
# *Performs Clone from Above Snapshot				 #
# *Exports Clone as OVA	                             #
# *Deletes SnapShot     							 #
# *Writes To Log									 #
# *Recurses through CSV						     	 #
# *Sends Email with Log to SS when complete 		 #
#                                                    #
######################################################
# Date: 20/05/2015                                   #
# Auth: jameseymail@hotmail.co.uk                    #
######################################################

#VCentre DNS Name
$VCDNS ="VC2.ad.mmu.ac.uk"

#Export Location
$ExportLoc = "\\ascfiler1\vm_repository\CloneTest\AutoExport\Test"

#Create PS-Drive Mapping from Datastore to the above location
New-PSDrive -Name Y -PSProvider filesystem -Root $ExportLoc

#Clear Screen
clear-host

# Load PowerCLI Snapin & Print Header
Write-host "Loading PowerCLI" -ForeGroundColor Blue
$VMwareLoaded = $(Get-PSSnapin | ? {$_.Name -like "*VMware*"} ) -ne $null
If ($VMwareLoaded) { }
Else
{
Add-PSSnapin -Name "VMware.VimAutomation.Core" | Out-Null
}

# Connect to CLI VCenter
Connect-VIserver -server $VCDNS

# Import CSV of VMs to be backed up
$FullVMList = @(Import-CSV C:\CloneWars\mybackups.csv)

# Performing Snapshot-Clone-Rename-Copy & Delete
Foreach($machine in $FullVMList){

# Recurse through CSV to obtain SourceVM Variable
$SourceVM = Get-VM $machine.MasterVM

# Get Target Datastore 
$TargetDS = Get-Datastore -VM $SourceVM

# Backup Folder to keep your Backups
$BACKUP_FOLDER = "Backup"

# vCenter Server
$vCenterServer="vc2.ad.mmu.ac.uk"

# Set Date format for clone names
$CloneDate = Get-Date -Format "ddMMyyyy-hhmmss"

# Check VM Parameter if no VM is specified then the script ends here.
If (($SourceVM -eq $Null ) -or ($TargetDS -eq $Null)) {
Write-Host "Error: SourceVM Not Found - Please try again"
Write-Host "Error: DataStore Not Found Please try again" -ForeGroundColor White
Exit }

#Functions to check whether a VM or DS Exists
function ExistVM([string] $VMName) {
Get-VM | Foreach-Object {$FullVMList += $_.Name}

if ( $FullVMList.Contains( $VMName ) ) {
$true
} else {
$false
}
}

function ExistDS([string] $DSName) {
Get-DataStore | Foreach-Object { $FullDSList += $_.Name }

if ( $FullDSList.Contains( $DSName ) ) {
$true
} else {
$false
}
}

# PowerCLI Header
Write-host "Loading PowerCLI" -ForeGroundColor Red
$VMwareLoaded = $(Get-PSSnapin | ? {$_.Name -like "*VMware*"} ) -ne $null
If ($VMwareLoaded) { }
Else
{
Add-PSSnapin -Name "VMware.VimAutomation.Core" | Out-Null
}

# Connect vCenter Server
Write-host "Connecting vCenter" -ForeGroundColor Yellow
Connect-VIserver -server $vCenterServer | Out-Null

# Lets Rock [Snapshot -> Clone -> Timestamp -> Delete]
if ( ExistVM( $SourceVM ) -and ExistDS( $TargetDS ) ) 
{

$VM = Get-VM $SourceVM

Write-Host -foregroundcolor Green " + Creating SnapShot " $SourceVM

$CloneSnap = $VM | New-SnapShot -Name "$CloneDate-$SourceVM-CloneSnapShot"
$VMView = $VM | Get-View
$CloneFolder=$VMView.Parent
$CloneSpec=New-Object Vmware.Vim.VirtualMachineCloneSpec
$CloneSpec.SnapShot=$VMView.SnapShot.CurrentSnapShot
$CloneSpec.Location=New-Object Vmware.Vim.VirtualMachineRelocateSpec
$CloneSpec.Location.Datastore=$(Get-Datastore -Name $TargetDS | Get-View).MoRef
$CloneSpec.Location.Transform=[Vmware.Vim.VirtualMachineRelocateTransformation]::Sparse
$CloneName = "$VM-$CloneDate-BAK"

Write-Host -foregroundcolor Green " + Cloning " $SourceVM "into" $CloneName

$VMView.CloneVM($CloneFolder,$CloneName,$CloneSpec) | Out-Null

Write-Host -foregroundcolor Green " + Moving to Folder " $BACKUP_FOLDER

Move-VM $CloneName -Destination $BACKUP_FOLDER | Out-Null

#################
#  OVA EXPORT   #
#################

#Export as OVA File
Write-host "Exporting "$CloneName" as OVA File" -ForeGroundColor Yellow
Write-host "(This will NOT overwrite any previous OVA Backups)" -ForeGroundColor Yellow
Get-VM -Name $CloneName | Export-VApp -Destination $ExportLoc

$OVAName = $CloneName + ".OVF" 

Get-VM $CloneName | Out-Null
Write-Host -foregroundcolor Green " + Exporting as " $OVAName ..
Get-Snapshot -VM $( Get-VM -Name $VM ) -Name $CloneSnap | Remove-Snapshot -confirm:$false

#Define OVF Name on Disk
$ExportedOVA = $ExportLoc + "\" + $CloneName + "\" + $OVAName

#write-host $ExportedOVA

#Check if OVF exists on Disk
if (Test-Path( $ExportedOVA ) ) {

Write-Host -ForegroundColor Blue " + $SourceVM has been Cloned into $CloneName & Exported as $ExportedOVA!"
} else {

Write-Host -foregroundcolor Red " + ERROR: $ExportedOVA could not be Backed Up!"
}
} else {
Write-Host -foregroundcolor Red " + ERROR: VirtualMachine ($VM2Backup) , DataStore ($TargetDS) does not exist or Export Location ($ExportedOVA) is inaccessible!"
}

#Delete VM Snapshot
Get-VM $CloneName | Out-Null
Write-Host -foregroundcolor Green " + Deleting SnapShot .. "
Get-Snapshot -VM $( Get-VM -Name $VM ) -Name $CloneSnap | Remove-Snapshot -confirm:$false

if ( ExistVM( $CloneName ) ) {

Write-Host -ForegroundColor Yellow " + $SourceVM has been Cloned into $CloneName "
} else {

Write-Host -foregroundcolor Red " + ERROR: $SourceVM could not be Backed Up!"

#} else {
#Write-Host -foregroundcolor Red " + ERROR: Either VirtualMachine ($VM2Backup) or DataStore ($TargetDS) does not exist!"
}

#################
# Email Results #
#################

#Set Date format for emails
$timecomplete = (Get-Date -f "HH:MM")
$timestart = @() 
$emailFrom = "j.lockwood@mmu.ac.uk"
$emailTo = "j.lockwood@mmu.ac.uk"
$subject = "[$vm - Backup Complete]"
$body = "Backup Details
-------------
VM Name:",$SourceVM,"
Clone Name:",$CloneName,"
Target Datastore:", $TargetDS,"
Time Started:", $timestart,"
Time Completed:", $timecomplete
$FullVMList
$smtpServer = "outlook.mmu.ac.uk"
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($emailFrom,$emailTo,$subject,$body)

#Write Results to Log File (Append)
#"VM:" + $SourceVM + "," + "DS:" + $TargetDS + "," + "OVAName:" + $OVAName + "," + "ExportLocation:" + $ExportLoc + "," | out-file -filepath c:\clonewars\log.txt -append -width 200
#+ "TimeComplete:" $timecomplete + "," + "TimeStarted:" $timestart
}

#Disconnect from vCentre
Write-host "Closing vCenter session " -ForeGroundColor Yellow
Disconnect-VIServer -$VCDNS -Confirm:$false