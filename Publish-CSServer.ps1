<#
.SYNOPSIS
   Publish a new CS server or refresh an old one
.DESCRIPTION
   This script will create a new AD user, clear the local RDU Group,
   add the newly created AD users to the RDU group and clear the user
   profiles on the server. 
.PARAMETER <paramName>
   -Computer
   		Name of the server to modify
   -CustomerName
   		Descriptive name of Customer
   -UserName
   		AD Logon user name to create
   -Password
   		password for the AD account. Must meet Domain policy for complexity
   -UserCount [optional]   
   		How many AD users do you require
.EXAMPLE
   ./Publish-CSServer.ps1 vm-cstone-99 "Animal Hospital 111" cs_animal .idexx123. 3
.NOTES
    ~Version History~
    Date            Version     Who                 Description
    06/24/2014      0.1.0       Shawn Markham       Recreated/Reworked from scripts built by Terry Schuttle
    07/28/2014      0.1.1       Shawn Markham       Released for UAT in Eau Claire
    07/29/2014      0.1.2       Shawn Markham       Working issues with AD User creation function
    07/29/2014      0.1.3       Shawn Markham       Added loop in local group function to wait for AD.
    07/29/2014      0.1.4       Shawn Markham       Added function to get a singular DC for all operations

#>

param (
	[string]$computer,
	[string]$customerName,
	[string]$userName,
	[string]$password,
	[int]$userCount = 1
)

# ******************* Variables *******************

[string]$domainName = "NISCO-DOM"
[string]$dcName = "ecwi-ecdc2.eauclaire.namerica.idexxi.com"
[string]$domainDNS = "eauclaire.namerica.idexxi.com"
[string]$groupName = "Remote Desktop Users"
[string]$userOU = "OU=ExternalCornerstoneUsers,OU=IdexxUsers,DC=eauclaire,DC=namerica,DC=idexxi,DC=com"

# ************* Verify the values  ****************

# Verify all args passed, get them, or exit with error
If(!$computer -or !$customerName -or !$userName -or !$password) {
	Write-Warning "A vm name, customer name, username, and password must be passed from the command line."
	Write-Warning 'Example: ./Publish-CSServer.ps1 vm-cstone-99 "Animal Hospital 111" cs_animal idexx123 3'
	Break
	}

#can we access the computer that was passed in the arguments
If ($computer -ne $Env:Computername) { 
	Write-Host "Verifying that $computer is online"
    If (!(Test-Connection -comp $computer -count 1 -quiet)) { 
        Write-Warning "$computer is not accessible, please try a different computer or verify it is powered on."
        Break
        } 
    } 

#Verify that the destination OS Version is 6.0 and above, otherwise the script will fail 
Try {     
    Write-Host "Verifying OS version of $computer"
    If ((Get-WmiObject -ComputerName $computer Win32_OperatingSystem -ea stop).Version -lt 6.0) { 
        Write-Warning "The Operating System of the computer is not supported.`nClient: Vista and above`nServer: Windows 2008 and above."
        Break
        } 
    } 
Catch { 
    Write-Warning "$($error[0])"
    Break
    } 

# ******************* Main Code *******************

Function main {
	#$dcName = Get-DC $DomainDNS

	# Provision AD User Object
	Create-UserObj $dcName $customerName $userCount $userName $password $userOU
	
	#Remove all users from the Remote Desktop Users Group
	Remove-GroupMembers $computer $groupName

	#Remove user profiles on remote server
	Remove-Profile $computer

	#Add the desired number of users back into the Remote Desktop Users Group
	for($i=1; $i -le $userCount; $i++) {
		do {
			$status = Add-GroupMembers $dcName $computer $groupName $UserName$i
		} while($status -eq $false)
	}
}

# ******************* Called Functions *******************

#Get a Domain Controller
Function Get-DC {
	param (
		[string]$Domain
	)
	$DoaminDCs = @()
	$PotentialDCs = @()
	foreach($ip in [System.Net.Dns]::GetHostEntry($Domain).AddressList) {
		$DoaminDCs += $($([System.Net.Dns]::GetHostEntry($ip).HostName).split("."))[0]
		}
	# Check connectivity to each DC
	ForEach ($DoaminDC in $DoaminDCs) {
		# Create a new TcpClient object
		$TCPClient = New-Object System.Net.Sockets.TCPClient
	
		# Try connecting to port 389 on the DC
		$Connect = $TCPClient.BeginConnect($DoaminDC,389,$null,$null)
	
		# Wait 250ms for the connection
		$Wait = $Connect.AsyncWaitHandle.WaitOne(250,$False)                      
	
		# If the connection was succesful add this DC to the array and close the connection
		If ($TCPClient.Connected) {
			# Add the FQDN of the DC to the array
			$PotentialDCs += $DoaminDC
	
			# Close the TcpClient connection
			$Null = $TCPClient.Close()
		}
	}
	# Pick a random DC from the list of potentials
	$DC = $PotentialDCs | Get-Random
	Write-Host "Using $DC server for the $Domain DC"
	# Return the DC
	Return $DC
}


#create user objects in AD
Function Create-UserObj {
	param (
		[string]$dcName,
		[string]$customerName,
		[int]$userCount,
		[string]$logonName,
		[string]$userPassword,
		[string]$userOU
	)
	
	$usersOU = [ADSI] "LDAP://$dcName/$userOU"
	$expirationDate = [datetime]::Now.AddDays(90)
	for($i=1; $i -le $userCount; $i++) {
		Try {
			Write-Host "Creating AD user $logonName$i"
			$newUser = $usersOU.Create("user", "CN=" + $customerName + " " + $i)
			$newUser.SetInfo()
			$newUser.description = "(HRID:-2)"
			$newUser.psbase.InvokeSet("AccountExpirationDate", $expirationDate)
			$newUser.sAMAccountname = $logonName + $i
			$newUser.userPrincipalName = $logonName + $i + "@eauclaire.namerica.idexxi.com"
			$newUser.DisplayName = $customerName + " " + $i
			$newUser.psbase.InvokeSet("AccountDisabled", $false)
			$newUser.psbase.Invoke("setpassword" ,$userPassword)
			$newUser.SetInfo()
			$newUser.sAMAccountname = $logonName + $i
			$newUser.SetInfo()
		}
		Catch {
			Write-Warning "There was a problem creating AD user $logonName$i `n$($error[0])"
		}
	}
}

#Remove members from a group
Function Remove-GroupMembers {
	param (
		[string]$computer,
		[string]$localGroupName
	)
	
	Try {
		if([ADSI]::Exists("WinNT://$computer/$localGroupName,group")) {  
			$group = [ADSI]("WinNT://$computer/$localGroupName,group")  
			$members = $group.psbase.invoke("Members")
			$members |  ForEach-Object {
				$AdsPath = $_.GetType().InvokeMember("Adspath", 'GetProperty', $null, $_, $null)
				$group.remove("$AdsPath")
				Write-Host "removing $AdsPath from $LocalGroupName on $computer"
			}
		}
	}
	Catch {
		Write-Warning "There was a problem removing users from $LocalGroupName `n$($error[0])"
	}
}

#Adds users back into the local group
Function Add-GroupMembers {
	param (
		[string]$dcName,	
		[string]$computer,
		[string]$localGroupName,
		[string]$UserName
	)
	if([ADSI]::Exists("WinNT://$computer/$localGroupName,group")) {  
		$objGroup = [ADSI]("WinNT://$computer/$localGroupName,group")
		Try {
			$objGroup.PSBase.Invoke("Add","WinNT://$dcName/$domainName/$userName")
			Write-Host "Adding $userName to $localGroupName"
			return $true
		}
		Catch {
			Write-Warning "There was a problem adding $userName to $localGroupName `n$($error[0])"
			return $false
		}
	}
}

# Remove unwanted user profile folders
Function Remove-Profile {
	param(
		[string]$computer
	)
	$userProfiles = Get-WMIObject Win32_UserProfile -ComputerName $computer -filter "LocalPath Like 'C:\\Users\\%'" -ea stop 
	$savedProfiles = @("srv_tsmcstone", "All Users", "Default User", "Public", "Default", "NetworkService", "LocalService", "systemprofile")
	if ($userProfiles) {
		:userProfile
		foreach ($userProfile in $userProfiles) {
			:savedProfile
			foreach ($savedProfile in $savedProfiles) {
				if($userProfile.localPath.Contains($savedProfile)) {
					continue userProfile
				}
			}
			Write-Host "Deleting user profile $userProfile.localPath"
			try {
				(Get-WMIObject win32_userprofile -ComputerName $computer| where {$_.LocalPath -like $userProfile.localPath}).delete()
			}
			Catch {
				Write-Warning "Problem deleting $userProfile.localPath `n$($error[0])"
			}
		}
	}
}

main
