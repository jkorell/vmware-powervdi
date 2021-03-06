# ==============================================================================================
# 
# Microsoft PowerShell Script Module
# 
# NAME: PowerVDI
# 
# AUTHOR: Nick Reed (reednj77@gmail.com)
# DATE  : 12/5/2012
# 
# PURPOSE: For automating common VMware View Administrator tasks.
# 
# ==============================================================================================

Try {
    if (-not (Get-PSSnapin VMware.VimAutomation.Core -EA SilentlyContinue)){
        Add-PSSnapin VMware.VimAutomation.Core -EA Stop
    }
}
Catch {
    Write-Error "You must have VMware PowerCLI installed to use this module."  -Category NotInstalled
    return
}

$script:organization=""
$script:defaultdomain=""
$script:domaincontrollerpath=""
$script:powercliLoaded=$false
$script:vcenterConnected=$false
$script:brokerSession=$null
$script:broker=""
$script:credentials=""
$script:defaultvcenter=""
$script:defaultbroker=""
$script:vcenter=""
$script:notConnectedMsg = "`nError: You must be connected to the VDI environment to perform this function. Connect using the Connect-VDI function.`n"
$script:originalWindowTitle = $host.ui.RawUI.WindowTitle
$script:auth="explicit"

Function Confirm-VDIConnected {
    return ($script:brokerSession -and $script:vcenterConnected)
}
Export-ModuleMember Confirm-VDIConnected

Function Connect-VDI {
    <#
    .SYNOPSIS
    Loads the VDI environment.
    .DESCRIPTION
    Connects to a vCenter instance and a View Connection Server instance.
    .EXAMPLE
    Connect-VDI "broker01.example.com"
    .EXAMPLE
    Connect-VDI -broker "broker01.example.com" -vcenter "vcenter.example.com"
    .EXAMPLE
    Connect-VDI broker01 -as domain\username
    .PARAMETER broker
    The FQDN of the View Connection Server you want to manage.
    .PARAMETER vcenter
    THE FQDN of the vSphere server that manages your virtual machines.
    .PARAMETER credential
    Optional.  Pass in a credential object or username to use as authentication to the servers.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$true)]
        [string]$broker = $script:defaultbroker,
        [string]$vcenter = $script:defaultvcenter,
        [alias('as')]
        $credential=""
    )
    
    if (($script:defaultdomain) -and (-not $broker.Contains($script:defaultdomain))){ $broker += $script:defaultdomain }
    
    # Ensure that the PowerCLI snapin is installed and loaded
    if (Get-PSSnapin VMware.VimAutomation.Core -Registered){
        $script:powercliLoaded = $true
        $script:broker = $broker
        $script:vcenter = $vcenter
        if ($credential){
            $script:credentials = Get-Credential -Credential $credential
            $script:auth = "explicit"
            $creds = @{Credential = $script:credentials}
        }else{
            $script:credentials = @{UserName = [Environment]::UserName}
            $script:auth = "implicit"
            $creds = @{}
        }
        $global:error.Clear()
        
        Write-Host "`nConnecting to broker ($script:broker)..." -NoNewline
        $script:brokerSession = (New-PSSession -ComputerName $broker @creds -Name "broker" -EA SilentlyContinue )
        if ($script:brokerSession){
            Invoke-Command -Session $script:brokerSession -ScriptBlock { Add-PSSnapin VMware* -EA SilentlyContinue }
            $ErrorActionPreference = 'SilentlyContinue'
            Import-PSSession -Session $script:brokerSession -Prefix VDI -Module VMware* -AllowClobber -EA SilentlyContinue | Import-Module -Global
            $ErrorActionPreference = 'Continue'
            if ($global:error.count -gt 0){
                Write-Host "Failed" -ForegroundColor Red
                Write-Host ("`nError Message:`n`n{0}`n" -f $global:error[0].ErrorDetails.Message) -ForegroundColor Red -BackgroundColor Black
                return
            }
            Write-Host "Success" -ForegroundColor Green
        }elseif ($global:error[0].ErrorDetails.Message.Contains("Access is denied")){
            Write-Host "Failed (Access Denied)" -ForegroundColor Red
            if ($script:auth -eq "implicit"){
                Connect-VDI $broker -credential (Get-Credential -Credential "")
            }
            return
        }else{
            Write-Host "Failed" -ForegroundColor Red
            Write-Host ("`nError Message:`n`n{0}`n" -f $global:error[0].ErrorDetails.Message) -ForegroundColor Red -BackgroundColor Black
            return 
        }
        
        $global:error.Clear()
        Write-Host "Connecting to vCenter ($script:vcenter)..." -NoNewline
        Connect-VIServer $script:vcenter @creds -EA SilentlyContinue | Out-Null
        if ($global:error.count -eq 0){
            $script:vcenterConnected = $true
            Write-Host "Success`n" -ForegroundColor Green
            $host.ui.RawUI.WindowTitle = "[{0}] Connected to {1} and {2} as {3}" -f $script:organization,$script:vcenter,$script:broker,$script:credentials.UserName
        }else{
            Write-Host "Failed" -ForegroundColor Red
            Write-Host ("`nError Message:`n`n{0}`n" -f $global:error[0].ErrorDetails.Message) -ForegroundColor Red -BackgroundColor Black
        }
    }else{
        Write-Host "Could not find the VMware.VimAutomation.Core snapin.  Make sure you have VMware vSphere PowerCLI installed." -ForegroundColor Red -BackgroundColor Black 
    }
}
New-Alias cvdi Connect-VDI
Export-ModuleMember Connect-VDI

Function Disconnect-VDI {
    <#
    .SYNOPSIS
    Unloads the VDI environment.
    .DESCRIPTION
    Disconnects from vCenter and the View Connection Server.
    .EXAMPLE
    Disconnect-VDI
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()
    
    Write-Host ""
    if ($script:vcenterConnected){
        Write-Host ("Disconnecting from {0}..." -f $script:vcenter) -NoNewline
        Disconnect-VIServer -Server $script:vcenter -Force -Confirm:$false -EA SilentlyContinue
        $script:vcenterConnected = $false
        Write-Host "Done" -ForegroundColor Green
    }
    
    if ($script:brokerSession){
        Write-Host "Disconnecting from $script:broker..." -NoNewline
        Remove-PSSession $script:brokerSession -EA SilentlyContinue
        $script:brokerSession = $null
        Write-Host "Done" -ForegroundColor Green
    }
    $host.ui.RawUI.WindowTitle = $script:originalWindowTitle
}
New-Alias dvdi Disconnect-VDI
Export-ModuleMember Disconnect-VDI

Function Show-VDICommands {
    <#
    .SYNOPSIS
    Lists the commands available in the connected VDI environment.
    .DESCRIPTION
    Lists the VMware View PowerCLI cmdlets available for use.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()

    Write-Host "`nPowerVDI Commands" -ForegroundColor Cyan
    Write-Host "***********************************************" -ForegroundColor Cyan
    Get-Command -Module PowerVDI -CommandType "Function" | 
        Where-Object { "Format-Columns","YesNoPrompt","Add-Pool","Parse-IniFile","Set-PoolOptions" -notcontains $_.Name } | 
        Sort-Object Name | 
        Format-Wide -Column 2 | 
        Out-String
    
    if (Confirm-VDIConnected){
        Write-Host "VMware Broker Commands" -ForegroundColor Cyan
        Write-Host "***********************************************" -ForegroundColor Cyan
        Invoke-Command -Session $script:brokerSession -ScriptBlock {
            Get-Command -Module VMware.View.Broker | Sort-Object Name | Format-Wide -Column 2 | Out-String
         }
         Write-Host "VMware vSphere Commands" -ForegroundColor Cyan
        Write-Host "***********************************************" -ForegroundColor Cyan
        Get-Command -Module VMware.VimAutomation.Core | Sort-Object Name | Format-Wide -Column 2 | Out-String
    }
}
New-Alias shcmd Show-VDICommands
Export-ModuleMember Show-VDICommands

Function Export-Pools {
    <#
    .SYNOPSIS
    Exports pool information to an XML file.
    .DESCRIPTION
    Exports pool information to an XML file.
    .PARAMETER path
    The XML file to be created.
    .PARAMETER pools
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool will be exported.
    .EXAMPLE
    Export-Pools AllPools.xml
    .EXAMPLE
    Export-Pools Pools.xml -pools "Pool1","Pool2"
    .EXAMPLE
    $pools = Get-Pool -pool_id "Pool1","Pool2" 
    Export-Pools Pools.xml -pools $pools 
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$false)]
        [alias('file')]
        [string]$path,
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$false)]
        [alias('pool','pool_id')]
        $pools = "all"
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    Function DisplayNotes {
        if ($onRequestPools){
            Write-Host "`n** Note that automatic pools with a manual naming scheme can not be recreated using the Import-Pools command.`n" -ForegroundColor Yellow
        }
        Write-Host "`n** Note that VMware's PowerShell API does not account for all pool settings.  If you intend" -ForegroundColor Yellow
        Write-Host "** to recreate these exported pools at some point using the Import-Pools command, you will need" -ForegroundColor Yellow
        Write-Host "** to manually configure the following settings through View Administrator after importing:`n" -ForegroundColor Yellow
        Write-Host "`tConnection Server restrictions"
        Write-Host "`tWindows 7 3D Rendering settings" 
        Write-Host "`tMax number of monitors" 
        Write-Host "`tMax resolution of any one monitor" 
        Write-Host "`tAutomatic user assignment" 
        Write-Host "`tThinApp assignments`n" 
    }
    
    Write-Host "`nGathering pools..."
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool
    }elseif (($pools -is [system.string]) -or (($pools -is [system.array]) -and ($pools[0] -is [system.string]))){
        $pools = Get-VDIPool -pool_id $pools
    }
    
    Write-Host "Gathering VM info..."
    $vms = Get-VDIDesktopVM -isInPool "true" | Sort-Object name | Group-Object -Property pool_id -AsHashTable
    
    $onRequestPools = $false
    
    # Add desktops and entitlements to each pool
    $pools | % {
        Write-Host ("   {0}..." -f $_.pool_id) -NoNewline
        if ($_.poolType.toLower().StartsWith("onrequest")){ $onRequestPools = $true }
        $entitlements = Get-VDIPoolEntitlement -pool_id $_.pool_id -EA SilentlyContinue
        $_ | Add-Member -MemberType NoteProperty -Name "Entitlements" -Value $entitlements 
        $_ | Add-Member -MemberType NoteProperty -Name "Desktops" -Value $vms[$_.pool_id]
        Write-Host "Success" -ForegroundColor Green
    }
    
    # Export
    Write-Host ("`nExporting to {0}..." -f $path) -NoNewline
    $pools | Sort-Object pool_id | Export-Clixml $path
    if (Test-Path $path){
        Write-Host "Success`n" -ForegroundColor Green
        DisplayNotes
    }else{
        Write-Host "Failed`n" -ForegroundColor Red
    }
}
New-Alias export-pool Export-Pools
Export-ModuleMember Export-Pools

Function Import-Pools {
    <#
    .SYNOPSIS
    Imports pool information from an XML file.
    .DESCRIPTION
    Imports pool information from an XML file and creates each pool on the broker.
    .PARAMETER path
    The XML file to be imported.
    .PARAMETER pools
    The pool ID(s) of the pools you want to import.
    .PARAMETER settings
    An optional hashtable of parameters that will be passed to the Add-*Pool cmdlet.
    These settings override those imported from the XML file.    
    .EXAMPLE
    Import-Pools AllPools.xml
    .EXAMPLE 
    Import-Pools AllPools.xml -pools "Pool1","Pool2"
    .EXAMPLE
    Import-Pools OnePool.xml -settings @{"defaultProtocol" = "RDP"} 
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$false)]
        [alias('file')]
        [string]$path,
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$false)]
        [alias('pool','pool_id')]
        $pools = "all",
        [Parameter(Mandatory=$false)]
        [hashtable]$settings
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if (Test-Path $path){
        Import-Clixml $path | % { 
            if (($pools -eq "all") -or ($pools -contains $_.pool_id)){
                if ($settings){
                    Add-Pool $_ -settings $settings 
                }else{
                    Add-Pool $_ 
                }
            }
        }
    }else{
        Write-Host "Error.  Could not find file $path" -ForegroundColor Red -BackgroundColor Black
    }
}
New-Alias import-pool Import-Pools 
Export-ModuleMember Import-Pools

Function Show-Pools {
    <#
    .SYNOPSIS
    Displays the ID and Display Name for each pool on the connected broker.
    .DESCRIPTION
    Displays the ID and Display Name for each pool on the connected broker.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    Get-VDIPool | Sort-Object pool_id | Format-Table pool_id, displayName | Out-String
}
New-Alias shp Show-Pools
Export-ModuleMember Show-Pools

Function Confirm-Entitlement {
    <#
    .SYNOPSIS
    Checks if a user or group is entitled on the specified pool.
    .DESCRIPTION
    Given a user or group name and a pool ID, returns true or false depending on if the user or group is entitled on the pool.
    .PARAMETER name
    The name of the user or group to check.
    .PARAMETER pool
    Can be a Pool ID as a string or a pool object.
    .EXAMPLE
    Confirm-Entitlement -name username -pool Pool1
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [alias('username','user')]
        [string]$name,
        [Parameter(Mandatory=$true)]
        [alias('pool_id')]
        $pool
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $userOrGroup = Get-VDIUser -Name $name -EA SilentlyContinue
    if ($userOrGroup){ 
        if ($pool.pool_id){ $pool = $pools.pool_id }
        if (Get-VDIPoolEntitlement -pool_id $pool -EA SilentlyContinue | Where-Object { $_.sid -eq $userOrGroup.sid }){
            return $true
        }
    }
    return $false
}
Export-ModuleMember Confirm-Entitlement

Function Add-Entitlement {
    <#
    .SYNOPSIS
    Entitles a user or group on the specified pool(s).
    .DESCRIPTION
    Given a user or group name and optionally a list of pools, entitles the user or group for each pool.
    .PARAMETER name
    The name of the user or group to entitle.
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, the user or group will be entitled on every pool.
    .EXAMPLE
    Add-Entitlement -name username
    .EXAMPLE
    Add-Entitlement -name username -pools Pool1
    .EXAMPLE
    Add-Entitlement -name username -pools Pool1,Pool2
    .EXAMPLE
    "Pool1","Pool2" | Add-Entitlement username
    .EXAMPLE
    Get-Pool -pool_id "Pool1","Pool2" | Add-Entitlement username
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$false)]
        [alias('username','user')]
        [string]$name,
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$true)]
        [alias('pool','pool_id')]
        $pools = "all"
    )
    
    Begin {
        if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
        $userOrGroup = Get-VDIUser -Name $name -EA SilentlyContinue
        if (-not $userOrGroup){ Write-Host ("ERROR: Could not find user or group named {0}" -f $name) -ForegroundColor Red -BackgroundColor Black; return }
        Write-Host ("`n{0}:" -f $userOrGroup.cn) 
    }
    Process {
        if ($userOrGroup){
            if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
                $pools = Get-VDIPool | % { $_.pool_id }
            }elseif (($pools -is [system.array]) -and ($pools[0] -is [PSCustomObject])){
                $pools = $pools | % { $_.pool_id }
            }elseif ($pools.pool_id){
                $pools = $pools.pool_id
            }
        
            $pools | % {
                Write-Host ("   {0}: " -f $_) -NoNewline
                if (-not (Confirm-Entitlement -name $name -pool $_)){
                    $res = Add-VDIPoolEntitlement -pool_id $_ -sid $userOrGroup.sid -EA SilentlyContinue
                    if (($res.entitlementsAdded) -and ($res.entitlementsAdded -eq 1)){ 
                        Write-Host "Entitled" -ForegroundColor Green 
                    }else{ 
                        Write-Host "Failed" -ForegroundColor Red 
                    }
                }else{
                    Write-Host "Entitled (no change)" -ForegroundColor Green
                }
            }
        }
    }
    End {
        Write-Host	""
    }
}
New-Alias entitle Add-Entitlement
Export-ModuleMember Add-Entitlement

Function Remove-Entitlement {
    <#
    .SYNOPSIS
    Unentitles a user or group on the specified pool(s).
    .DESCRIPTION
    Given a user or group name and optionally a list of pools, unentitles the user or group for each pool.
    .PARAMETER name
    The name of the user or group to unentitle.
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, the user or group will be unentitled on every pool.
    .EXAMPLE
    Remove-Entitlement -name username
    .EXAMPLE
    Remove-Entitlement -name username -pools Pool1
    .EXAMPLE
    Remove-Entitlement -name username -pools Pool1,Pool2
    .EXAMPLE
    "Pool1","Pool2" | Remove-Entitlement username
    .EXAMPLE
    Get-Pool -pool_id "Pool1","Pool2" | Remove-Entitlement username
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$false)]
        [alias('username','user')]
        [string]$name,
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$true)]
        [alias('pool','pool_id')]
        $pools = "all"
    )
    
    Begin {
        if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
        $userOrGroup = Get-VDIUser -Name $name -EA SilentlyContinue
        if (-not $userOrGroup){ Write-Host ("ERROR: Could not find user or group named {0}" -f $name) -ForegroundColor Red -BackgroundColor Black; return }
        Write-Host ("`n{0}:" -f $userOrGroup.cn) 
    }
    Process {
        if ($userOrGroup){
            if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
                $pools = Get-VDIPool | % { $_.pool_id }
            }elseif (($pools -is [system.array]) -and ($pools[0] -is [PSCustomObject])){
                $pools = $pools | % { $_.pool_id }
            }elseif ($pools.pool_id){
                $pools = $pools.pool_id
            }
        
            $pools | % {
                Write-Host ("   {0}: " -f $_) -NoNewline
                if (Confirm-Entitlement -name $name -pool $_){
                    $res = Remove-VDIPoolEntitlement -pool_id $_ -sid $userOrGroup.sid -EA SilentlyContinue
                    if (($res.entitlementsRemoved) -and ($res.entitlementsRemoved -eq 1)){ 
                        Write-Host "Unentitled" -ForegroundColor Green 
                    }else{ 
                        Write-Host "Failed" -ForegroundColor Red 
                    }
                }else{
                    Write-Host "Unentitled (no change)" -ForegroundColor Green
                }
            }
        }
    }
    End {
        Write-Host	""
    }
}
New-Alias unentitle Remove-Entitlement
Export-ModuleMember Remove-Entitlement

Function Show-PoolDatastores {
    <#
    .SYNOPSIS
    Displays the datastores configured for a specified pool.
    .DESCRIPTION
    Displays the datastores configured for a specified pool.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        [alias('pool_id')]
        $pool
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if ($pool -isnot [PSCustomObject]){
        $pool = Get-VDIPool -pool_id $pool
    }
    
    $datastores = $pool.datastoreSpecs.Split(';')
    $stores = @() 
    if ($datastores){
        $datastores | Sort-Object | % {
            $properties = ($_ -replace '\[(\S+)\]([\S\s]+)','$1').Split(',')
            $store = $_ -replace '\[(\S+)\]([\S\s]+)','$2'
            $objStore = New-Object System.Object
            $objStore | Add-Member -Type NoteProperty -Name 'Name' -Value (Split-Path $store -Leaf)
            $objStore | Add-Member -Type NoteProperty -Name 'Types' -Value $properties[1..($properties.length - 1)]
            $objStore | Add-Member -Type NoteProperty -Name 'Overcommit' -Value $properties[0]
            $objStore | Add-Member -Type NoteProperty -Name 'Path' -Value $store
            $stores += $objStore
        }
        $stores | Format-Table -AutoSize -Wrap
    }else{
        Write-Host "No datastores defined."
    }
}
Export-ModuleMember Show-PoolDatastores

Function Add-PoolDatastore {
    <#
    .SYNOPSIS
    Adds a datastore to the configuration of the specified pool(s).
    .DESCRIPTION
    Adds a datastore to the configuration of the specified pool(s).
    .PARAMETER datastore
    The name of the datastore to add.
    .PARAMETER pools
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be updated.
    .PARAMETER usage
    Optional.  How the datastore is to be used.  Can be 'OS,data' or 'replica'.  
    Defaults to 'OS,data'.
    .PARAMETER overcommit
    Optional.  The overcommit strategy to use.  Can be 'None', 'Conservative', 'Moderate', or 'Aggressive'. 
    Defaults to 'None'.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $datastore,
        [Parameter(Mandatory=$false)]
        [alias('pool','pool_id','to')]
        $pools = "all",
        [Parameter(Mandatory=$false)]
        [ValidateSet('OS,data','replica')]
        $usage = 'OS,data',
        [Parameter(Mandatory=$false)]
        [ValidateSet('Conservative','Moderate','Aggressive','None')]
        $overcommit = 'None'
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool
    }else {
        $pools = Get-VDIPool -pool_id $pools
    }
    
    $properties = "[{0},{1}]" -f $overcommit,$usage
    
    Write-Host ''
    foreach ($pool in $pools){
        Write-Host ("   {0}" -f $pool.pool_id) -ForegroundColor Cyan
        Write-Host ("   {0}" -f ('-' * $pool.pool_id.length)) -ForegroundColor Cyan
        if ($pool.datastoreSpecs){
            if (-not $pool.datastoreSpecs.Contains($datastore)){
                $currentDatastoreSpecs = $pool.datastoreSpecs
                $currentDatastores = $currentDatastoreSpecs.Split(';')
                $path = (Split-Path ($currentDatastores[0] -replace '\[(\S+)\]([\S\s]+)','$2') -Parent).Replace('\','/')
                $spec = "{0}{1}/{2}" -f $properties,$path,$datastore
                $newDatastoreSpecs = [string]::Join(';', ($currentDatastores + $spec))
                
                $currentDatastores | % {
                    $props = "[{0}]" -f ($_ -replace '\[(\S+)\]([\S\s]+)','$1')
                    $name = Split-Path $_ -Leaf
                    Write-Host ("   {0,-27} {1}" -f $props,$name)
                }
                Write-Host ("  +{0,-27}+{1}: " -f $properties,$datastore) -NoNewline -ForegroundColor Yellow
                $global:error.Clear()
                Update-VDIAutomaticLinkedClonePool -pool_id $pool.pool_id -DatastoreSpecs $newDatastoreSpecs -EA SilentlyContinue
                
                if ($global:error.count -eq 0){
                    Write-Host "Success" -ForegroundColor Green
                }else{
                    Write-Host "Failed" -ForegroundColor Red
                    Write-Host ("`nError Message:`n`n{0}`n" -f $global:error[0].ToString()) -ForegroundColor Red -BackgroundColor Black
                }
            }else{
                Write-Host ("   Failed ({0} is already using {1})" -f $pool.pool_id,$datastore) -ForegroundColor Red
            }
        }else{
            Write-Host "   Failed (Not a valid pool type)"
        }
        Write-Host ''
    }
}
Export-ModuleMember Add-PoolDatastore

Function Remove-PoolDatastore {
    <#
    .SYNOPSIS
    Removes a datastore from the configuration of the specified pool(s).
    .DESCRIPTION
    Removes a datastore from the configuration of the specified pool(s).
    .PARAMETER datastore
    The name of the datastore to remove.
    .PARAMETER pools
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be updated.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $datastore,
        [Parameter(Mandatory=$false)]
        [alias('pool','pool_id','from')]
        $pools = "all"
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool
    }else {
        $pools = Get-VDIPool -pool_id $pools
    }
    
    Write-Host ''
    foreach ($pool in $pools){
        Write-Host ("   {0}" -f $pool.pool_id) -ForegroundColor Cyan
        Write-Host ("   {0}" -f ('-' * $pool.pool_id.length)) -ForegroundColor Cyan
        if ($pool.datastoreSpecs){
            if ($pool.datastoreSpecs.Contains($datastore)){
                $currentDatastoreSpecs = $pool.datastoreSpecs
                $currentDatastores = $currentDatastoreSpecs.Split(';')
                
                $keep = @()
                $remove = ''
                $currentDatastores | % {
                    $props = "[{0}]" -f ($_ -replace '\[(\S+)\]([\S\s]+)','$1')
                    $name = Split-Path $_ -Leaf
                    if ($name -eq $datastore){
                        $remove = "  -{0,-27}-{1}: " -f $props,$name
                    }else{
                        $keep += $_
                        Write-Host ("   {0,-27} {1}" -f $props,$name)
                    }
                }
                if ($remove){
                    if ($keep){
                        Write-Host $remove -NoNewline -ForegroundColor Yellow
                        $newDatastoreSpecs = [string]::Join(';', $keep)
                        
                        $global:error.Clear()
                        Update-VDIAutomaticLinkedClonePool -pool_id $pool.pool_id -DatastoreSpecs $newDatastoreSpecs -EA SilentlyContinue
                        
                        if ($global:error.count -eq 0){
                            Write-Host "Success" -ForegroundColor Green
                        }else{
                            Write-Host "Failed" -ForegroundColor Red
                            Write-Host ("`nError Message:`n`n{0}`n" -f $global:error[0].ToString()) -ForegroundColor Red -BackgroundColor Black
                        }
                    }else{
                        Write-Host "Failed (Pool requires at least one datastore)`n" -ForegroundColor Red
                    }
                }
            }else{
                Write-Host ("   Failed ({0} isn't using {1})" -f $pool.pool_id,$datastore) -ForegroundColor Red
            }
        }else{
            Write-Host "   Failed (Not a valid pool type)" -ForegroundColor Red
        }
        Write-Host ''
    }
}
Export-ModuleMember Remove-PoolDatastore

Function Get-PoolMaster {
    <#
    .SYNOPSIS
    Returns the name (or path) of the parent VM for a given pool.
    .DESCRIPTION
    Given either the name of a pool or the actual pool object, this function returns the parent VM, 
    either by name or by path.
    .EXAMPLE
    Get-PoolMaster "PoolID"
    MASTER-VM-00
    .EXAMPLE
    Get-PoolMaster "PoolID" -Path
    /path/to/MASTER-VM-00
    .PARAMETER pool
    Either a Pool ID as a string or a pool object
    .PARAMETER Path
    Switch tells the function to return the path to the parent VM instead of the name
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        [alias('pool_id')]
        $pool,
        [switch]$Path
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if ($pool -isnot [PSCustomObject]){
        $pool = Get-VDIPool -pool_id $pool
    }
    
    if ($pool.parentVMPath){
        if ($Path){
            return $pool.parentVMPath
        }else{
            return Split-Path $pool.parentVMPath -Leaf 
        }
    }else{
        Write-Host ("Error: {0} is not a linked-clone pool, and therefore does not utilize a master VM." -f $pool.pool_id) -ForegroundColor Red
        return ""
    }
}
Export-ModuleMember Get-PoolMaster

Function Get-PoolSnapshot {
    <#
    .SYNOPSIS
    Returns the name (or path) of the current snapshot set for a given pool.
    .DESCRIPTION
    Given either the name of a pool or the actual pool object, this function returns the parent VM
    snapshot set for it, either by name or by path.
    .EXAMPLE
    Get-Pool-Snapshot "PoolID"
    Snapshot 2
    .EXAMPLE
    Get-Pool-Snapshot "PoolID" -Path
    /Snapshot 1/Snapshot 2
    .PARAMETER pool
    Either a Pool ID as a string or a pool object
    .PARAMETER Path
    Switch tells the function to return the path to the snapshot instead of the name
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        [alias('pool_id')]
        $pool,
        [switch]$Path
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if ($pool -isnot [PSCustomObject]){
        $pool = Get-VDIPool -pool_id $pool
    }
    if ($pool.parentVMSnapshotPath){
        if ($Path){
            return $pool.parentVMSnapshotPath
        }else{
            return Split-Path $pool.parentVMSnapshotPath -Leaf
        }
    }else{
        Write-Host ("Error: {0} is not a linked-clone pool, and therefore does not utilize a master VM snapshot." -f $pool.pool_id) -ForegroundColor Red
        return ""
    }
}
Export-ModuleMember Get-PoolSnapshot

Function Get-LatestSnapshot {
    <#
    .SYNOPSIS
    Returns the name (or path) of the latest snapshot for a given virtual machine.
    .DESCRIPTION
    Given the name of a virtual machine, this function returns either the name or the full path to the latest snapshot.
    .EXAMPLE
    Get-LatestSnapshot "MASTER-VM-00"
    /Snapshot 1/Snapshot 2
    .EXAMPLE
    Get-LatestSnapshot "MASTER-VM-00" -Path
    Snapshot 2
    .PARAMETER vm
    The name of the virtual machine
    .PARAMETER Path
    Switch tells the function to return the path to the snapshot instead of the name
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $vm,
        [switch]$Path
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $snapshots = Get-Snapshot $vm | select -ExpandProperty Name
    if ($snapshots){
        if ($Path){
            return "/" + [string]::join("/", $snapshots)
        }else{
            if ($snapshots -is [system.string]){
                return $snapshots
            }else{
                return $snapshots[-1]
            }
        }
    }else {
        Write-Host "Could not find any snapshots for the VM named $vm"
        return $false
    }
}
Export-ModuleMember Get-LatestSnapshot

Function Confirm-PoolSnapshotOutdated {
    <#
    .SYNOPSIS
    Checks if the pool's snapshot is outdated.
    .DESCRIPTION
    Given either a Pool ID or a pool object, this function checks if the pool's master VM has a newer snapshot than
    the one set for the pool.
    .PARAMETER pool
    Either a Pool ID as a string or a pool object 
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        [alias('pool_id')]
        $pool
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if ($pool -isnot [PSCustomObject]){
        $pool = Get-VDIPool -pool_id $pool
    }
    if ($pool.parentVMPath){
        $vm = Split-Path $pool.parentVMPath -Leaf
        $latest = Get-LatestSnapshot $vm -Path
        return ($latest -ne $pool.parentVMSnapshotPath)
    }else{
        return $false
    }
}
Export-ModuleMember Confirm-PoolSnapshotOutdated

Function Get-PoolsWithOutdatedSnapshots {
    <#
    .SYNOPSIS
    Returns the pools on the broker that have outdated snapshots.
    .DESCRIPTION
    Returns the pools on the broker that have outdated snapshots.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    return Get-VDIPool | Where-Object { Confirm-PoolSnapshotOutdated $_ } | Sort-Object Name
}
Export-ModuleMember Get-PoolsWithOutdatedSnapshots

Function Show-PoolsWithOutdatedSnapshots {
    <#
    .SYNOPSIS
    Displays the pools on the broker that have outdated snapshots.
    .DESCRIPTION
    Displays the pools on the broker that have outdated snapshots.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $pools = Get-PoolsWithOutdatedSnapshots 
    if ($pools){
        $pools | 
        select @{Name="Pool"; Expression={$_.pool_id}},
            @{Name="Master"; Expression={Split-Path $_.parentVMPath -Leaf}},
            @{Name="Current Snapshot"; Expression={$_.parentVMSnapshotPath}},
            @{Name="Latest Snapshot"; Expression={Get-LatestSnapshot (Split-Path $_.parentVMPath -Leaf) -Path}} | 
        Format-Table
    }else{
        Write-Host "All pools on $script:broker are current."
    }
}
Export-ModuleMember Show-PoolsWithOutdatedSnapshots

Function Confirm-SnapshotExists {
    <#
    .SYNOPSIS
    Checks if a VM snapshot exists.
    .DESCRIPTION
    Given a VM name and a snapshot name, this function checks if the snapshot exists.
    .PARAMETER vm
    The name of the virtual machine to check.
    .PARAMETER snapshot 
    The name of the snapshot to check for.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $vm,
        [Parameter(Mandatory=$true)]
        $snapshot
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $global:error.Clear()
    Get-Snapshot $vm -Name $snapshot -EA SilentlyContinue | Out-Null
    if ($global:error -ne $null){
        return $false
    }else{
        return $true
    }
}
Export-ModuleMember Confirm-SnapshotExists

Function Confirm-SnapshotPathExists {
    <#
    .SYNOPSIS
    Checks if a VM snapshot path exists.
    .DESCRIPTION
    Given a VM name and a snapshot path, this function checks if the snapshot path exists.
    .PARAMETER vm
    The name of the virtual machine to check.
    .PARAMETER snapshot 
    The path of the snapshot to check for.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $vm,
        [Parameter(Mandatory=$true)]
        $snapshot
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $full_path = Get-LatestSnapshot $vm -Path
    return ($full_path -and $full_path.StartsWith($snapshot))
}
Export-ModuleMember Confirm-SnapshotPathExists

Function Set-PoolSnapshot {
    <#
    .SYNOPSIS
    Changes the snapshot for the given pool(s).
    .DESCRIPTION
    Given a snapshot and optionally a list of pools, sets the snapshot for each pool.
    .PARAMETER snapshot
    The path of the snapshot to set.
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be updated.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $snapshot,
        [Parameter(Mandatory=$false)]
        [alias('pool','pool_id')]
        $pools = "all"
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool
    }else {
        $pools = Get-VDIPool -pool_id $pools
    }
    foreach ($pool in $pools) { 
        if ($pool.parentVMSnapshotPath){
            $parent = Get-PoolMaster $pool
            if (Confirm-SnapshotPathExists -vm $parent -snapshot $snapshot){
                Write-Host "Changing " -NoNewline
                Write-Host $pool.pool_id -ForegroundColor Cyan -NoNewline
                Write-Host " snapshot from " -NoNewline
                Write-Host (Split-Path $pool.parentVMSnapshotPath -Leaf) -ForegroundColor Gray -NoNewLine
                Write-Host " to " -NoNewline
                Write-Host (Split-Path $snapshot -Leaf) -ForegroundColor Gray -NoNewLine
                Write-Host "..." -NoNewline
                Update-VDIAutomaticLinkedClonePool -pool_id $pool.pool_id -parentSnapshotPath $snapshot -EA SilentlyContinue
                if ((Get-PoolSnapshot $pool.pool_id -Path) -eq $snapshot){
                    Write-Host "Success" -ForegroundColor Green
                }else{
                    Write-Host "Failed" -ForegroundColor Red
                }
            }else {
                Write-Host ("Could not change snapshot on the {0} pool because the snapshot path {1} doesn't exist." -f $pool.pool_id,$snapshot) -ForegroundColor Red
            }
        }
    }
}
Export-ModuleMember Set-PoolSnapshot

Function Send-PoolRecompose {
    <#
    .SYNOPSIS
    Schedules the recomposition of all the clones in the given pool(s).
    .DESCRIPTION
    Schedules the recomposition of all the clones in the given pool(s).
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be updated.
    .PARAMETER except
    Optional.  An array of Pool IDs as strings that will be excluded from recomposition.
    .PARAMETER forceLogoff
    Optional.  Whether user sessions should be logged off before performing this operation.
    Defaults to false.
    .PARAMETER stopOnError
    Optional.  Whether this operation should stop when an error occurs. 
    Defaults to false.  
    .PARAMETER Simulate
    Switch.  If set, the calculated recompose schedule will be displayed, but nothing
    will actually be scheduled.  
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [Alias('pool', 'pool_id')]
        $pools = "all",
        [string[]]$except = @(""),
        [boolean]$forceLogoff = $false,
        [boolean]$stopOnError = $false,
        [switch]$Simulate
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    # Retrieve all of the linked clones and group them by pool
    $clonesBySite = Get-VDIDesktopVM -isInPool $true -isLinkedClone $true -EA SilentlyContinue | 
                        Sort-Object name | 
                        Group-Object -Property pool_id -AsHashTable
    
    if (-not $clonesBySite){ Write-Host "`nCould not find any linked-clones to recompose.`n"; return }
    
    # Retrieve the pool object(s)
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool -EA SilentlyContinue
    }else {
        $pools = Get-VDIPool -pool_id $pools -EA SilentlyContinue
    }
    
    # Filter out pools that have no clones, aren't linked-clone pools, or were included in the $except argument.  Sorts remaining pools by pool ID.
    $pools = $pools | ? { (($except -notcontains $_.pool_id) -and ($_.parentVMSnapshotPath) -and ($clonesBySite[$_.pool_id])) } | Sort-Object pool_id
    
    if ($pools -eq $null){
        Write-Host "`nNo linked-clone pools were found, or those that were found contained no clones to recompose.`n"
        return
    }elseif ($pools -is [system.array]){
        $poolCount = $pools.count
    }else{
        $poolCount = 1
    }
    
    if ($Simulate){ Write-Host "`nNote: This is a simulation.  No action will be taken." -ForegroundColor Yellow }
    Write-Host "`nScheduling pools for recomposition:"
    
    $poolData = @{}
    $waves = @(0)
    $replicasChecked = @{}
    
    foreach ($pool in $pools){
        if ($pool.displayName){ Write-Host "  " $pool.displayName -NoNewline }
        else { Write-Host "  " $pool.pool_id -NoNewline }
        
        # Determine the pool's parent VM path and snapshot path and save it to the $poolData array, to be used in the recompose command
        $parentVMPath = Get-PoolMaster $pool -Path
        $snapshot = Get-PoolSnapshot $pool -Path
        $poolData[$pool.pool_id] = @{"parentVMPath" = $parentVMPath; "snapshot" = $snapshot}
        
        # Checks if a replica has already been created for this VM/snapshot.
        # The use of the $replicasChecked hash is a makeshift memoization function, preventing us from checking for the same
        #  snapshot's replica repeatedly if multiple pools use the same snapshot.  
        if ($replicasChecked["$parentVMPath-$snapshot"] -eq $null){
            $replicasChecked["$parentVMPath-$snapshot"] = (Confirm-ReplicaProvisioned -vm $parentVMPath -snapshot $snapshot)
        }
        
        # Retrieve the pool's clones
        $clones = $clonesBySite[$pool.pool_id]
        if ($clones){
            # Determine the number of clones in the pool
            if ($clones.count){
                $size = $clones.count
            }else{
                $size = 1 
            }
            Write-Host " ($size)" -ForegroundColor Gray
            
            # Calculate the number of groups in which the pool will be recomposed in
            $groupCount = [Math]::Truncate($size / 30) + 2 
            $replicaDelay = 0
            
            # If the pool's snapshot has no replica provisioned, add an N wave delay after the first wave to allow for replica provisioning
            # The number of waves to delay is inversely related to the number of pools being recomposed.  
            if (-not $replicasChecked["$parentVMPath-$snapshot"]){ 
                $replicaDelay = [Math]::Truncate(15 / $poolCount) + 3
                Write-Host "`tAdding additional delay to allow for provisioning of replica." -ForegroundColor Gray
            }
            while ($waves.length -lt ($groupCount + $replicaDelay)){ $waves += 0 } # increase the size of the $waves array, if necessary
            
            # Loop through the pool's clones, separating them into provisioning groups (waves)
            $clones | % {$i=0} {
                # Calculate which group this clone will be assigned to
                $group = [Math]::Floor($i / ($size / $groupCount))
                
                # Add the N wave replica delay, if necessary, to the clone if it isn't assigned to the first group
                if ($group -ne 0){ $group += $replicaDelay }
                
                # Add the clone to the calculated wave
                if ($waves[$group] -eq 0){
                    $waves[$group] = @($_)
                }else{
                    $waves[$group] += $_
                }

                $i++
            }
        }
    }
    
    # Build the schedule
    # - First wave begins in 5 minutes
    # - For each wave, clones are recomposed in groups of 20, with each group starting 10 minutes after the last
    # - A delay of 15 minutes separates each wave
    $schedule = @{}
    $waves | % {$i=1;$delay=5} {
        for ($j=0; $j -lt $_.length; $j+=20){
            $schedule[$delay] = $_[$j..($j + 19)]
            $delay += 10
        }
        $i++; $delay += 5
    }
    
    $schedule = $schedule.GetEnumerator() | Sort-Object Name
    foreach ($t in $schedule){
        $time = (Get-Date).AddMinutes($t.Name)
        Write-Host "`nIn" $t.Name "minutes (" -NoNewline -ForegroundColor Cyan
        Write-Host $time.ToShortTimeString() -NoNewline -ForegroundColor Cyan
        Write-Host ")`n**********************************" -ForegroundColor Cyan
        $t.Value | Format-Columns -Property Name -Autosize -MaxColumn 8  | Out-Host
        if (-not $Simulate){
            $attempted,$successful,$unchanged = 0,0,0
            $t.Value | Group-Object -Property pool_id | % {
                $poolID = $_.Name 
                $options = @{
                    parentVMPath = $poolData[$poolID].parentVMPath
                    parentSnapshotPath = $poolData[$poolID].snapshot
                    schedule = $time
                    forceLogoff = $forceLogoff
                    stopOnError = $stopOnError
                }
                $result = $_.Group | Send-VDILinkedCloneRecompose @options
                $attempted += $_.Count
                $successful += $result.vmsToRecompose
                $unchanged += $result.vmsUnchanged
            }
            Write-Host ("`n  {0,-13} {1}" -f "Attempted:",$attempted) -ForegroundColor Yellow
            Write-Host ("  {0,-13} {1}" -f "Successful:",$successful) -ForegroundColor Green
            Write-Host ("  {0,-13} {1}" -f "Unchanged:",$unchanged) -ForegroundColor Magenta
        }
    }
    Write-Host ""
}
New-Alias recompose Send-PoolRecompose
Export-ModuleMember Send-PoolRecompose
 
Function Confirm-ReplicaProvisioned {
    <#
    .SYNOPSIS
    Checks if a replica has been provisioned for a given VM and snapshot.
    .DESCRIPTION
    Given a VM and a snapshot, checks if a replica has been provisioned for it.
    .PARAMETER vm 
    Either the name or the full path of the VM to check.
    .PARAMETER snapshot
    Either the name or the full path of the snapshot to check. 
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $vm,
        [Parameter(Mandatory=$true)]
        $snapshot
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $objSnapshot = Get-Snapshot -VM (Split-Path $vm -Leaf) -Name (Split-Path $snapshot -Leaf) -EA SilentlyContinue
    if ($objSnapshot){
        $snapshotID = $objSnapshot.Id.Replace("VirtualMachineSnapshot-", "")
        $filter = "(&(objectClass=pae-VM)(pae-SVIVmSnapshotMOID=$snapshotID))"
        
        $clones = Invoke-Command -Session $script:brokerSession -ArgumentList $filter -ScriptBlock {
            $path = "OU=Servers,dc=vdi,dc=vmware,dc=int"
            $domain = "LDAP://localhost/$path"
            $root = New-Object System.DirectoryServices.DirectoryEntry $domain
            $query = New-Object System.DirectoryServices.DirectorySearcher($root)
            $query.Filter = $args[0]
             $query.FindAll()
         }
         return (($clones -ne $null) -as [system.boolean])
    }else{
        return $false
    }
}
Export-ModuleMember Confirm-ReplicaProvisioned

Function Get-OutdatedVMs {
    <#
    .SYNOPSIS
    Returns the clones that were built off a different snapshot than the one currently set for their pool.
    .DESCRIPTION
    Returns the clones that were built off a different snapshot than the one currently set for their pool.
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be searched.
    .PARAMETER except
    Optional.  An array of Pool IDs as strings that will be excluded from search.
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [alias('pool','pool_id')]
        $pools = "all",
        [string[]]$except = @("")
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    # Retrieve the pool object(s)
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool | ? { (($except -notcontains $_.pool_id) -and ($_.parentVMSnapshotPath)) } | Sort-Object pool_id
    }else {
        $pools = Get-VDIPool -pool_id $pools | ? { (($except -notcontains $_.pool_id) -and ($_.parentVMSnapshotPath)) } | Sort-Object pool_id
    } 
    
    $outdated = @()
    if ($pools){
        $pools | % {
            # Gather the CNs of each clone in the pool into a comma-separated list of paths in the broker's ADAM database
            $cns = "({0})" -f $_.machineDNs.Replace(",OU=Servers,DC=vdi,DC=vmware,DC=int","").Replace(";",")(")
            
            # If there are multiple CNs, wrap the query in an "OR" operator (|($cns))
            if ($_.machineDNs.Contains(";")){ $cns = "(|{0})" -f $cns }
            
            # Subquery for matching on clones with different snapshots than the pool
            $snapshot = "(!pae-SVIVmSnapshotMOID={0})" -f $_.parentVMSnapshotMOID
            
            # The full query string will find all the clones in the pool that have a different base snapshot than the one set for the pool
            $filter = "(&(objectClass=pae-VM){0}{1})" -f $snapshot,$cns
            
            # Search the ADAM database on the broker
            $clones = Invoke-Command -Session $script:brokerSession -ArgumentList $filter -ScriptBlock {
                $path = "OU=Servers,dc=vdi,dc=vmware,dc=int"
                $domain = "LDAP://localhost/$path"
                $root = New-Object System.DirectoryServices.DirectoryEntry $domain
                $query = New-Object System.DirectoryServices.DirectorySearcher($root)
                $query.Filter = $args[0]
                 $query.FindAll()
             }
             
             # If any clones are outdated, convert each into a custom object with Name,CurrentSnapshot, and PoolSnapshot properties
             # and add them to the $outdated array
             if ($clones -ne $null){
                 $snapshotPath = $_.parentVMSnapshotPath
                 foreach ($clone in $clones) {
                     $objClone = New-Object System.Object
                     $objClone | Add-Member -type NoteProperty -Name Name -Value $clone.Properties["pae-displayname"][0]
                     $objClone | Add-Member -type NoteProperty -Name CurrentSnapshot -Value $clone.Properties."pae-svivmsnapshot"[0]
                     $objClone | Add-Member -type NoteProperty -Name PoolSnapshot -Value $snapshotPath
                     $outdated += $objClone
                 }
             }
        }
    }
    # Return the results
    if ($outdated){
        $outdated | Sort-Object Name
    }else {
        Write-Host "`nCould not find any outdated VMs.`n"
        $outdated
    }
}
Export-ModuleMember Get-OutdatedVMs

Function Send-PoolRefresh {
    <#
    .SYNOPSIS
    Schedules the refresh of all the clones in the given pool(s).
    .DESCRIPTION
    Schedules the refresh of all the clones in the given pool(s).
    .PARAMETER pools 
    Optional.  Can be a Pool ID as a string, a pool object, or an array of either.  
    If not specified, every pool on the broker will be refreshed.
    .PARAMETER except
    Optional.  An array of Pool IDs as strings that will be excluded from refresh.
    .PARAMETER forceLogoff
    Optional.  Whether user sessions should be logged off before performing this operation.
    Defaults to false.
    .PARAMETER stopOnError
    Optional.  Whether this operation should stop when an error occurs. 
    Defaults to false.  
    .PARAMETER Simulate
    Switch.  If set, the calculated refresh schedule will be displayed, but nothing
    will actually be scheduled.  
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [alias('pool','pool_id')]
        $pools = "all",
        [string[]]$except = @(""),
        [boolean]$forceLogoff = $false,
        [boolean]$stopOnError = $false,
        [switch]$Simulate
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    # Retrieve all of the linked clones and group them by pool
    $clonesBySite = Get-VDIDesktopVM -isInPool $true -isLinkedClone $true -EA SilentlyContinue | 
                        Sort-Object name | 
                        Group-Object -Property pool_id -AsHashTable
    
    if (-not $clonesBySite){ Write-Host "`nCould not find any linked-clones to refresh.`n"; return }
    
    # Retrieve the pool object(s)
    if (($pools -is [system.string]) -and ($pools.ToLower() -eq "all")){
        $pools = Get-VDIPool -EA SilentlyContinue
    }else {
        $pools = Get-VDIPool -pool_id $pools -EA SilentlyContinue
    }
    
    # Filter out pools that have no clones, aren't linked-clone pools, or were included in the $except argument.  Sorts remaining pools by pool ID.
    $pools = $pools | ? { (($except -notcontains $_.pool_id) -and ($_.parentVMSnapshotPath) -and ($clonesBySite[$_.pool_id])) } | Sort-Object pool_id
    
    if ($pools -eq $null){
        Write-Host "`nNo linked-clone pools were found, or those that were found contained no clones to refresh.`n"
        return
    }
    
    if ($Simulate){ Write-Host "`nNote: This is a simulation.  No action will be taken." -ForegroundColor Yellow }
    Write-Host "`nScheduling pools for refresh:"
    
    $waves = @(0)
    
    foreach ($pool in $pools){
        if ($pool.displayName){ Write-Host "  " $pool.displayName -NoNewline }
        else { Write-Host "  " $pool.pool_id -NoNewline }
        
        # Retrieve the pool's clones
        $clones = $clonesBySite[$pool.pool_id]
        if ($clones){
            # Determine the number of clones in the pool
            if ($clones.count){
                $size = $clones.count
            }else{
                $size = 1 
            }
            Write-Host " ($size)" -ForegroundColor Gray
            
            # Calculate the number of groups in which the pool will be refreshed in
            $groupCount = [Math]::Truncate($size / 30) + 2 
            while ($waves.length -lt $groupCount){ $waves += 0 } # increase the size of the $waves array, if necessary
            
            # Loop through the pool's clones, separating them into groups (waves)
            $clones | % {$i=0} {
                # Calculate which group this clone will be assigned to
                $group = [Math]::Floor($i / ($size / $groupCount))
                
                # Add the clone to the calculated wave
                if ($waves[$group] -eq 0){
                    $waves[$group] = @($_)
                }else{
                    $waves[$group] += $_
                }

                $i++
            }
        }
    }
    
    # Build the schedule
    # - First wave begins in 5 minutes
    # - For each wave, clones are refreshed in groups of 20, with each group starting 5 minutes after the last
    # - A delay of 10 minutes separates each wave
    $schedule = @{}
    $waves | % {$i=1;$delay=5} {
        for ($j=0; $j -lt $_.length; $j+=20){
            $schedule[$delay] = $_[$j..($j + 19)]
            $delay += 5
        }
        $i++; $delay += 5
    }
    
    $schedule = $schedule.GetEnumerator() | Sort-Object Name
    foreach ($t in $schedule){
        $time = (Get-Date).AddMinutes($t.Name)
        Write-Host "`nIn" $t.Name "minutes (" -NoNewline -ForegroundColor Cyan
        Write-Host $time.ToShortTimeString() -NoNewline -ForegroundColor Cyan
        Write-Host ")`n**********************************" -ForegroundColor Cyan
        $t.Value | Format-Columns -Property Name -Autosize -MaxColumn 8  | Out-Host
        if (-not $Simulate){
            $t.Value | Group-Object -Property pool_id | % {
                $_.Group | Send-VDILinkedCloneRefresh -schedule $time -forceLogoff $forceLogoff -stopOnError $stopOnError
            }
        }
    }
}
New-Alias refresh Send-PoolRefresh
Export-ModuleMember Send-PoolRefresh

Function Send-ConsoleSessionRefresh {
    <#
    .SYNOPSIS
    Refreshes all VMs with console sessions
    .DESCRIPTION
    Refreshes all VMs on the broker with connected sessions that are using the CONSOLE protocol. 
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param()
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    $consoleSessions = Get-VDIRemoteSession -Protocol CONSOLE -EA SilentlyContinue 
    if ($consoleSessions) {
        $pool_ids = $consoleSessions | Group-Object -Property pool_id -NoElement | % { $_.Name }
        $pools = Get-VDIPool -pool_id $pool_ids 
        $vms = Get-VDIDesktopVM -isLinkedClone $true -isInPool $true -pool_id $pool_ids -composerTask "" -EA SilentlyContinue 
        $toRefresh = @() 
        foreach ($session in $consoleSessions) { 
            $machineID = $session.session_id -replace '[\S\s]+@cn=([\w-]+),[\S\s]+','$1'
            $vm = $vms | Where-Object { $_.machine_id -eq $machineID }
            if ($vm) {
                $pool = $pools | Where-Object {$_.pool_id -eq $session.pool_id}
                if ($pool.poolType -eq "SviNonPersistent") {
                    $toRefresh += $vm
                }
                #else {
                    #trigger reboot or reset instead of refresh (to be determined)
                #}
            }
        }
        if ($toRefresh){
            $toRefresh | Send-VDILinkedCloneRefresh -schedule (Get-Date) -forceLogoff $true
        }
    }
}
Export-ModuleMember Send-ConsoleSessionRefresh

Function New-PoolFromCopy {
    <#
    .SYNOPSIS
    Creates a new pool with settings identical to an existing pool.
    .DESCRIPTION
    Given an existing pool to use as a template, a new pool will be created, enabled, and entitled.
    .PARAMETER source 
    Can be a Pool ID as a string or a pool object 
    .PARAMETER pool_id
    A string representing the ID of the pool you want to create.
    .PARAMETER description
    Optional.  Sets the description for the new pool.
    .PARAMETER displayName
    Optional.  Sets the display name for the new pool.
    .PARAMETER namePrefix
    A string representing the naming scheme for the new pool. Required for automatic pools.
    Ex. SITE-VM-{n:fixed=2}  
    .PARAMETER settings
    Optional.  A hash of options to pass to the Add-*Pool cmdlet.  Any options set here will 
    override the ones retrieved from the source pool.  
    .NOTES
    Custom function written by Nick Reed (reednj77@gmail.com)
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $source,
        [Parameter(Mandatory=$true)]
        [string]$pool_id,
        [Parameter(Mandatory=$false)]
        [string]$description="",
        [Parameter(Mandatory=$false)]
        [string]$displayName="",
        [Parameter(Mandatory=$false)]
        [string]$namePrefix,
        [Parameter(Mandatory=$false)]
        [hashtable]$settings
    )
    
    if (-not (Confirm-VDIConnected)){ Write-Host $script:notConnectedMsg -ForegroundColor Red -BackgroundColor Black; return }
    
    if ($source -isnot [PSCustomObject]){
        $source = Get-VDIPool -pool_id $source
    }
    
    if ($source){
        $entitlements = Get-VDIPoolEntitlement -pool_id $source.pool_id -EA SilentlyContinue
        $vms = Get-VDIDesktopVM -pool_id $source.pool_id | Sort-Object name | Group-Object -Property pool_id -AsHashTable
        $vms = $vms[$source.pool_id]
        
        $source.pool_id = $pool_id
        $source.description = $description 
        $source.displayName = $displayName 
        if ($source.namePrefix){
            if ($namePrefix){
                $source.namePrefix = $namePrefix
            }else{
                Write-Host "Error: You must specify a namePrefix in order to copy this type of pool." -ForegroundColor Red -BackgroundColor Black
                return
            }
        }
        
        # Take the OU path of the source and change the leaf to the new pool ID.
        if ($source.organizationalUnit){
            if (($settings) -and ($settings.organizationalUnit)){
                $source.organizationalUnit = $settings.organizationalUnit
            }else{
                $arrOU = $source.organizationalUnit.split(',')
                $arrOU[0] = "OU=$pool_id"
                $source.organizationalUnit = [string]::Join(',',$arrOU)
            }
        }
        
        $source | Add-Member -MemberType NoteProperty -Name "Entitlements" -Value $entitlements 
        $source | Add-Member -MemberType NoteProperty -Name "Desktops" -Value $vms
        
        if ($settings){
            Add-Pool $source -settings $settings
        }else{
            Add-Pool $source
        }
    }else{
        Write-Host "Error: Could not find the source pool." -ForegroundColor Red -BackgroundColor Black
    }
}
New-Alias cppool New-PoolFromCopy
Export-ModuleMember New-PoolFromCopy

Function Add-Pool {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$pool,
        [Parameter(Mandatory=$false)]
        [hashtable]$settings
    )
    
    function Merge-Settings{
        if ($settings){
            $settings.GetEnumerator() | % {
                if ($options[$_.Name]){ $options[$_.Name] = $_.Value }
            }
        }
    }
    Function GetGeneralPoolType {
        Param($poolType)
        switch -wildcard ($poolType.ToLower()){
            "svi*" { "automaticlinkedclone"; break }
            "onrequest*" { "onrequest"; break }
            "manualunmanaged*" { "manualunmanaged"; break }
            "manual*" { "manual"; break }
            "persistent" { "automaticfull"; break }
            "nonpersistent" { "automaticfull"; break }
            default { "" }
        }
    }
    Function HandleOnRequestPool {
        Param($pool)
        Write-Host ("Unable to create the pool {0} because it has a manual naming pattern." -f $pool.pool_id) -ForegroundColor Red
    }
    function PromptForPoolCreationConfirmation {
        $title = "Pool Creation"
        $message = "Create the pool with the settings listed above?"
        $yes = "Create pool."
        $no = "Don't create pool."
        return YesNoPrompt $title $message $yes $no
    }
    function Copy-Entitlements {
        if ($pool.Entitlements){
            Write-Host "Copying entitlements..."
            $pool.Entitlements | % {
                Write-Host "`tEntitling " -NoNewline
                Write-Host ("{0}..." -f $_.cn) -ForegroundColor Cyan -NoNewline
                $res = Add-VDIPoolEntitlement -pool_id $options['pool_id'] -sid $_.sid -EA SilentlyContinue 
                if (($res.entitlementsAdded) -and ($res.entitlementsAdded -eq 1)){ Write-Host "Success" -ForegroundColor Green }
                else{ Write-Host "Failed" -ForegroundColor Red }
            }
        }
    }
    
    $type = GetGeneralPoolType $pool.poolType
    if ($type -eq "onrequest"){
        HandleOnRequestPool $pool
    }elseif ($type -ne ""){
        Write-Host ("`n{0}`n" -f $pool.pool_id) -ForegroundColor Cyan
    
        $options = Set-PoolOptions $pool -type $type
        
        if ($options){
            Merge-Settings
            
            # Display options to user
            $options.GetEnumerator() | Sort-Object Name
                
            if (PromptForPoolCreationConfirmation){
                Write-Host ("`nCreating new pool {0}..." -f $options['pool_id']) -NoNewline
                $global:error.Clear()
                
                switch ($type){
                    "automaticlinkedclone" { Add-VDIAutomaticLinkedClonePool @options -EA SilentlyContinue}
                    "automaticfull" { Add-VDIAutomaticPool @options -EA SilentlyContinue }
                    "manual" { Add-VDIManualPool @options -EA SilentlyContinue }
                    "manualunmanaged" { Add-VDIManualUnmanagedPool @options -EA SilentlyContinue }
                }
                
                # Check if successful
                if (($global:error.count -eq 0) -and (Get-VDIPool -pool_id $options['pool_id'] -EA SilentlyContinue)){
                    Write-Host "Success" -ForegroundColor Green
                    Copy-Entitlements
                }else{
                    Write-Host "Failed" -ForegroundColor Red
                    if ($global:error.count -gt 0){
                        $msg = "`nError Message:`n`n{0}`n" -f $global:error[0].ToString()
                    }else{
                        $msg = "`nPool creation failed for an unknown reason.  Try running the command again.`n"
                    }
                    Write-Host $msg -ForegroundColor Red -BackgroundColor Black
                }
            }
        }
    }
}

Function Set-PoolOptions {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$pool,
        [string]$type 
    )
    
    $domaincontrollerpath = ""
    
    function Copy-Property([Array]$prop){
        $prop | % { if ($pool.$_){ $options[$_] = $pool.$_ } }
    }
    function DC-Exists {
        $ErrorActionPreference = 'SilentlyContinue'
        $chk = ([ADSI]::Exists("LDAP://{0}" -f $domaincontrollerpath))
        $ErrorActionPreference = 'Continue'
        return $chk
    }
    function OU-Exists { return ([ADSI]::Exists("LDAP://{0},{1}" -f ($options['organizationalUnit'],$domaincontrollerpath))) }
    function PromptForOUCreationConfirmation {
        if (Get-Command dsadd -EA SilentlyContinue){
            $title = "OU Creation"
            $message = "The OU ({0},{1}) doesn't exist.  Do you want to create it?" -f ($options['organizationalUnit'],$domaincontrollerpath)
            $yes = "Create OU."
            $no = "Don't create OU."
            return YesNoPrompt $title $message $yes $no
        }else{
            Write-Host ("`nError: The OU ({0},{1}) doesn't exist. " -f ($options['organizationalUnit'],$domaincontrollerpath)) -NoNewline -ForegroundColor Red
            Write-Host "This script can't create it for you since Active Directory Domain Services (AD DS) is not installed.`n" -ForegroundColor Red
            return $false
        }
    }
    function PromptForPoolCreationConfirmation {
        $title = "Pool Creation"
        $message = "Create the pool with the settings listed above?"
        $yes = "Create pool."
        $no = "Don't create pool."
        return YesNoPrompt $title $message $yes $no
    }
    function Create-OU {
        Write-Host "`nCreating OU..." -NoNewline 
        if ($script:auth -eq "implicit"){
            dsadd ou ("{0},{1}" -f ($options['organizationalUnit'],$domaincontrollerpath)) -q
        }else{
            dsadd ou ("{0},{1}" -f ($options['organizationalUnit'],$domaincontrollerpath)) `
                -u $script:credentials.UserName `
                -p ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:credentials.Password))) `
                -q
        }
        if (OU-Exists){ Write-Host "Success" -ForegroundColor Green; return $true }
        else{ Write-Host "Failed" -ForegroundColor Red; return $false }
    }
    function Set-ManualUnmanagedProperties {
        if ($pool.machineDNs){
            $machines = $pool.machineDNs.Split(';')
            $pm_ids = @()
            $pool.machineDNs.Split(';') | % { $pm_ids += ($_ -replace 'CN=([\w\-]+),[\S\s]+','$1') }
            if ($pm_ids.count -gt 1){
                $options['pm_id_list'] = [string]::Join(';', $pm_ids)
            }elseif ($pm_ids.count -eq 1){
                $options['pm_id'] = $pm_ids[0]
            }
        }
    }
    function Set-ManualProperties {
        if ($pool.Desktops){
            if ($pool.Desktops.count -gt 1){
                $vm_ids = $pool.Desktops | Select-Object -expandProperty id
                $options['vm_id_list'] = [string]::Join(';', $vm_ids)
            }elseif ($pool.Desktops.count -eq 1){
                $options['id'] = $pool.Desktops[0].id
            }
        }
    }
    function Set-AutoProperties {
        $options['isProvisioningEnabled'] = [System.Convert]::ToBoolean($pool.provisionEnabled)
        $options['suspendProvisioningOnError'] = [System.Convert]::ToBoolean($pool.provisionSuspendOnError)
        $options['vmFolderPath'] = [string]::Join('/', (Split-Path $pool.vmFolderPath).Split('\'))
        if ($pool.customizationSpec){ $options['customizationSpecName'] = $pool.customizationSpec }
        Copy-Property 'resourcePoolPath','minimumCount','maximumCount','headroomCount','namePrefix'
        if ($pool.persistence.ToLower() -eq "nonpersistent"){ Copy-Property 'deletePolicy' }
    }
    function Set-AutoFullProperties {
        $options['dataStorePaths'] = $pool.datastorePaths
        $options['startClone'] = [System.Convert]::ToBoolean($pool.startClone)
        Copy-Property 'templatePath'
    }
    function Set-AutoLinkedCloneProperties {
        $options['parentSnapshotPath'] = $pool.parentVMSnapshotPath
        Copy-Property 'parentVMPath','datastoreSpecs','composer_ad_id','logoffScript','postSyncScript','organizationalUnit'
        if ($script:domaincontrollerpath){
            $domaincontrollerpath = $script:domaincontrollerpath
        }else{
            $domaincontrollerpath = "dc={0}" -f [string]::Join(',dc=', $pool.composerDomain.split('.'))
        }
        if (DC-Exists){
            if (-not (OU-Exists)){
                # Ask the user if they want the script to create the OU for them.  If no, the function exits.
                if (PromptForOUCreationConfirmation){
                    if (-not (Create-OU)){ return $false}
                }else{ 
                    Write-Host "Pool creation aborted.  To specify the OU you want, pass it into the function with the -settings parameter." -ForegroundColor Yellow
                    return $false
                }
            }
        }else{
            Write-Host ("WARNING: Can't verify that the OU {0} exists because the domain controller ({1}) is invalid.  Pool creation will fail if the OU doesn't exist." `
                            -f ($options['organizationalUnit'],$domaincontrollerpath)) -ForegroundColor Yellow
        }
        # Parse the user and temp disks
        if ($pool.persistentDiskSpecs){
            $specs = $pool.persistentDiskSpecs -split '\];\['
            $specs | % {
                $diskSize = $_ -replace '[\S\s]*DiskSize=(\d+);[\S\s]*','$1'
                $diskUsage = $_ -replace '[\S\s]*DiskUsage=(\w+);[\S\s]*','$1'
                $mountpoint = $_ -replace '[\S\s]*MountPoint=(.);[\S\s]*','$1'
    
                switch ($diskUsage){
                    "SystemDisposable" {
                        $options['useTempDisk'] = $true
                        $options['tempDiskSize'] = $diskSize
                    }
                    "UserProfile" {
                        $options['useUserDataDisk'] = $true
                        $options['dataDiskLetter'] = $mountpoint
                        $options['dataDiskSize'] = $diskSize
                    }
                }
            }
        }

        # Parse the refresh policy into the correct options
        $pool.refreshPolicy.split(';') | % {
            if ($_.StartsWith("type=")){ $options['refreshPolicyType'] = $_.Substring(5) }
            elseif ($_.StartsWith("days=")){ $options['refreshPolicyDays'] = $_.Substring(5) }
            elseif ($_.StartsWith("usage=")){ $options['refreshPolicyUsage'] = $_.Substring(6) }
        }
    }

    $options = @{
        isUserResetAllowed = [System.Convert]::ToBoolean($pool.userResetAllowed)
        defaultProtocol = $pool.protocol
        allowProtocolOverride = [System.Convert]::ToBoolean($pool.allowProtocolOverride)
        flashQuality = $pool.flashQualityLevel
        flashThrottling = $pool.flashThrottlingLevel
    }
    
    Copy-Property 'pool_id','description','displayName','persistence','autoLogoffTime','folderId'
    
    if (-not [System.Convert]::ToBoolean($pool.enabled)){ $options['disabled'] = $true }
    
    if ($pool.persistence.ToLower() -eq "nonpersistent"){ 
        $options['allowMultipleSessions'] = [System.Convert]::ToBoolean($pool.multiSessionAllowed)
    }
    
    if ($type -eq "manualunmanaged"){
        Set-ManualUnmanagedProperties
    }else{
        Copy-Property 'vc_id','powerPolicy'
        if ($type -eq "manual"){
            Set-ManualProperties
        }else{
            Set-AutoProperties
            if ($type -eq "automaticfull"){
                Set-AutoFullProperties
            }else{
                if ((Set-AutoLinkedCloneProperties) -eq $false){ return $false }
            }
        }
    }
    return $options
}

Function YesNoPrompt {
    Param(
        [string]$title,
        [string]$message,
        [string]$yesText,
        [string]$noText
    )
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", $yesText
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", $noText
    $opts = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    !$Host.ui.PromptForChoice($title,$message,$opts,0)
}

Function Format-Columns {
    ################################################################
    #.Synopsis
    #  Formats incoming data to columns.
    #.Description
    #  It works similarly as Format-Wide but it works vertically. Format-Wide outputs
    #  the data row by row, but Format-Columns outputs them column by column.
    #.Parameter Property
    #  Name of property to get from the object.
    #  It may be 
    #   -- string - name of property.
    #   -- scriptblock
    #   -- hashtable with keys 'Expression' (value is string=property name or scriptblock)
    #      and 'FormatString' (used in -f operator)
    #.Parameter Column
    #  Count of columns
    #.Parameter Autosize
    #  Determines if count of columns is computed automatically.
    #.Parameter MaxColumn
    #  Maximal count of columns if Autosize is specified
    #.Parameter InputObject
    #  Data to display
    #.Example
    #  PS> 1..150 | Format-Columns -Autosize
    #.Example 
    #  PS> Format-Columns -Col 3 -Input 1..130
    #.Example
    #  PS> Get-Process | Format-Columns -prop @{Expression='Handles'; FormatString='{0:00000}'} -auto
    #.Example
    #  PS> Get-Process | Format-Columns -prop {$_.Handles} -auto
    #.Notes
    # Name: Get-Columns
    # Author: stej, http://twitter.com/stejcz
    # Lastedit: 2010-01-14
    # Version 0.2 - 2010-01-14
    #  - added MaxColumn
    #  - fixed bug - displaying collection of 1 item was incorrect
    # Version 0.1 - 2010-01-06
    ################################################################
    param(
        [Parameter(Mandatory=$false,Position=0)][Object]$Property,
        [Parameter()][switch]$Autosize,
        [Parameter(Mandatory=$false)][int]$Column,
        [Parameter(Mandatory=$false)][int]$MaxColumn,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][PsObject[]]$InputObject
    )
    begin   { $values = @() }
    process { $values += $InputObject }
    end {
        function ProcessValues {
            $ret = $values
            $p = $Property
            if ($p -is [Hashtable]) {
                $exp = $p.Expression
                if ($exp) {
                    if ($exp -is [string])          { $ret = $ret | % { $_.($exp) } }
                    elseif ($exp -is [scriptblock]) { $ret = $ret | % { & $exp $_} }
                    else                            { throw 'Invalid Expression value' }
                }
                if ($p.FormatString) {
                    if ($p.FormatString -is [string]) {    $ret = $ret | % { $p.FormatString -f $_ } }
                    else {                              throw 'Invalid format string' }
                }
            }
            elseif ($p -is [scriptblock]) { $ret = $ret | % { & $p $_} }
            elseif ($p -is [string]) {      $ret = $ret | % { $_.$p } }
            elseif ($p -ne $null) {         throw 'Invalid -property type' }
            # in case there were some numbers, objects, etc., convert them to string
            $ret | % { $_.ToString() }
        }
        function Base($i) { [Math]::Floor($i) }
        function Max($i1, $i2) {  [Math]::Max($i1, $i2) }
        if (!$Column) { $Autosize = $true }
        $values = ProcessValues
        
        $valuesCount = @($values).Count
        if ($valuesCount -eq 1) {
            $values | Out-Host
            return
        }
        
        # from some reason the console host doesn't use the last column and writes to new line
        $consoleWidth          = $host.ui.RawUI.maxWindowSize.Width -1; 
        $spaceWidthBetweenCols = 2
            
        # get length of the longest string
        $values | % -Begin { [int]$maxLength = -1 } -Process { $maxLength = Max $maxLength $_.Length }
        
        # get count of columns if not provided
        if ($Autosize) {
            $Column         = Max (Base ($consoleWidth/($maxLength+$spaceWidthBetweenCols))) 1
            $remainingSpace = $consoleWidth - $Column*($maxLength+$spaceWidthBetweenCols);
            if ($remainingSpace -ge $maxLength) { 
                $Column++ 
            }
            if ($MaxColumn -and $MaxColumn -lt $Column) {
                Write-Debug "Columns corrected to $MaxColumn (original: $Column)"
                $Column = $MaxColumn
            }
        }
        $countOfRows       = [Math]::Ceiling($valuesCount / $Column)
        $maxPossibleLength = Base ($consoleWidth / $Column)
        
        # cut too long values, considers count of columns and space between them
        $values = $values | % { 
            if ($_.length -gt $maxPossibleLength) { $_.Remove($maxPossibleLength-2) + '..' }
            else { $_ }
        }
        
        #add empty values so that the values fill rectangle (2 dim array) without space
        if ($Column -gt 1) {
            $values += (@('') * ($countOfRows*$Column - $valuesCount))
        }
        # in case there is only one item, make it array
        $values = @($values)
        <#
        now we have values like this: 1, 2, 3, 4, 5, 6, 7, ''
        and we want to display them like this:
        1 3 5 7
        2 4 6 ''
        #>
        
        $formatString = (1..$Column | %{"{$($_-1),-$maxPossibleLength}"}) -join ''
        1..$countOfRows | % { 
            $r    = $_-1
            $line = @(1..$Column | % { $values[$r + ($_-1)*$countOfRows]} )
            $formatString -f $line | Out-Host
        }
    }
}

Function Parse-IniFile {
    Param($file)
    if (Test-Path $file){
        switch -regex -file $file {
            "^\s*([^#].+?)\s*=\s*(.*)" {
                $name,$val = $matches[1..2]
                Set-Variable -Name $name -Value $val -Scope "Script"
            }
        }
    }
}

$settingsFile = ($MyInvocation.MyCommand.Path | Split-Path) + "\settings.ini"
Parse-IniFile $settingsFile

if ($args.length -gt 0){
    Connect-VDI $args[0]
}

Export-ModuleMember -Alias *
