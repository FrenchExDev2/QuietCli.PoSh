$path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
New-ItemProperty -Path $path -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force
Get-ItemPropertyValue -Path $path -Name LongPathsEnabled
