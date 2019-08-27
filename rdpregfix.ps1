$regpath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'

New-ItemProperty $regpath -Name "MaxTokenSize" -PropertyType "DWORD" -Value "48000"