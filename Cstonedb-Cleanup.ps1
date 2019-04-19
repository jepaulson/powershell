<#
.SYNOPSIS
    Cleanup ECWIFS Group Volume Location after a 30 Day period

.DESCRIPTION
    This script will delete the cstone.db and cstone.log files older than 30 days from "\\ecwifs\grp-vol2\Cstone Support Logs\".
    It will run daily and then email RMM@idexx.com daily reports.

.AUTHORs
    Joshua Paulson

.NOTES
    ~Version History~
    Date            Version     Who                 Description
   1/14/2018        0.1.0       Joshua Paulson      Started creation with script requirments
   
     
#>
# ********** Notes ***********

### $to_be_deleted = Get-ChildItem -Path $path | Where {($_.Name -match "cstone.db") -or ($_.Name -match "cstone.log") -and ($_.LastWriteTime  -lt (Get-Date).AddDays(-$age))}
### $files = Get-ChildItem -Path $path | Where {($_.Name -match "cstone.db") -or ($_.Name -match "cstone.log")}
### $age = "30"

# ********** Variables **********

$range = (Get-Date).AddDays(-30)
$path = "C:\Test"
$date = Get-Date -Format "M.d.yyyy"

# ********** Email Variables **********

$smtp = 'smtp.idexx.com'
$to = 'eauclaireIT@idexx.com'
$from = 'sparrow@idexx.com'
$subject = 'Cornerstone Log Cleanup'
$body = 'Please see attached log for daily cleanup'
$log = "C:\test\log_$date.txt"
$cc = "Joshua-Paulson@idexx.com"


# *** Script ***


# Start Logging

Start-Transcript "C:\test\log_$date.txt"


# Gather files older than 30 days

$files = Get-ChildItem -Path $path -Recurse | Where {($_.Name -match "cstone.db") -or ($_.Name -match "cstone.log") -and ($_.LastWriteTime -lt $range)}


# Write files to be deleted to host/log

if ($files -ne $null) {
    Write-Host "`n"
    Write-Host "The following files have been deleted:"
    $files | Format-Table -Property Name, LastWriteTime -GroupBy Directory
}
else {
    Write-Host "No deletions today"
}

# Stop Logging
Stop-Transcript

# Delete Items
$files | Remove-Item -Recurse

# Send email to requested distribution list

Send-MailMessage -From $from -To $to -Subject $subject -Body $body -SmtpServer $smtp -Attachments $log -BodyAsHtml -Priority High -Cc $cc
