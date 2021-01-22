#ps1

# username
$Username = "buildadmin"
# replace this with strong password and a github PAT
$Password = "xxxx" 
$GITHUB_PAT="xxxx"

# Url of github api
$GITHUB_URL="https://api.github.com"
# or for GHE on-prem
# GITHUB_URL="https://github.mycompany.local/api/v3"

$group = "Administrators"

Set-ExecutionPolicy Unrestricted # Beginning in PowerShell 6.0 for non-Windows computers, the default execution policy is Unrestricted and can't be changed. 

$adsi = [ADSI]"WinNT://$env:COMPUTERNAME"
$existing = $adsi.Children | Where-Object {$_.SchemaClassName -eq 'user' -and $_.Name -eq $Username }

if ($null -eq $existing) {

    Write-Host "Creating new local user $Username."
    & NET USER $Username $Password /add /y /expires:never
    
    Write-Host "Adding local user $Username to $group."
    & NET LOCALGROUP $group $Username /add

}
else {
    Write-Host "Setting password for existing local user $Username."
    $existing.SetPassword($Password)
}

Write-Host "Ensuring password for $Username never expires."
& WMIC USERACCOUNT WHERE "Name='$Username'" SET PasswordExpires=FALSE
function Refresh-System(){
    $signature = @'
[DllImport("wininet.dll", SetLastError = true, CharSet=CharSet.Auto)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
    
        $INTERNET_OPTION_SETTINGS_CHANGED   = 39
        $INTERNET_OPTION_REFRESH            = 37
        $type = Add-Type -MemberDefinition $signature -Name wininet -Namespace pinvoke -PassThru
        $type::InternetSetOption(0, $INTERNET_OPTION_SETTINGS_CHANGED, 0, 0)
        $type::InternetSetOption(0, $INTERNET_OPTION_REFRESH, 0, 0)
    
}

try{
    Write-Host "Set IE proxy"
    $proxy = "http://my-proxy.loca:8080"
    $noproxy = ""

    $proxyBytes = [system.Text.Encoding]::ASCII.GetBytes($proxy)
    $noproxyBytes = [system.Text.Encoding]::ASCII.GetBytes($noproxy)
    $defaultConnectionSettings = [byte[]]@(@(70,0,0,0,4,0,0,0,3,0,0,0,$proxyBytes.Length,0,0,0)+$proxyBytes+@($noproxyBytes.Length,0,0,0)+$noproxyBytes+ @(1..36 | ForEach-Object {0}))
    #$defaultConnectionSettings = [byte[]]@(@(70,0,0,0,0,0,0,0,11,0,0,0,$proxyBytes.Length,0,0,0)+$proxyBytes+@($bypassBytes.Length,0,0,0)+$bypassBytes+ @(1..36 | % {0}))

    $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path "$regKey" -Name "ProxyServer" -value $proxy
    Set-ItemProperty -Path "$regKey" -Name "ProxyEnable" -value 1
    if(!(Test-Path "$regKey\Connections"))
    {
        New-Item "$regKey\Connections"
    }
    Set-ItemProperty -Path "$regKey\Connections" -Name DefaultConnectionSettings -Value $defaultConnectionSettings
    Set-ItemProperty -Path "$regKey" -Name "ProxyOverride" -value $noproxy
    Set-ItemProperty -Path "$regKey" -Name "DisableFirstRunCustomize" -value 1
    
    Write-Host "Set environment proxy"
    [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', "$proxy", [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', "$proxy", [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('NO_PROXY', "$noproxy", [System.EnvironmentVariableTarget]::Machine)
    
    Write-Host "Refresh system to persist proxy"
    Refresh-System

    Write-Host "Set WinHTTP proxy"
    netsh winhttp import proxy source=ie
    Start-Process control "inetcpl.cpl,,4"
}
catch{
    Write-Error "The following exception occured `n $_.ToString()" 

}
Write-Output "Starting installation of Github Runner"


Set-Location C:\
mkdir a
Set-Location a
$RUNNER_VER="2.274.2"
Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v$RUNNER_VER/actions-runner-win-x64-$RUNNER_VER.zip" -Proxy "http://my-proxy.loca:8080" -OutFile "actions-runner-win-x64-$RUNNER_VER.zip" -UseBasicParsing
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/actions-runner-win-x64-$RUNNER_VER.zip", "$PWD")
$githubheaders = @{"Authorization"="token $GITHUB_PAT"}
Write-Host "Get token from github"
Write-Host "calling https://api.github.com/enterprises/agoda/actions/runners/registration-token"
Write-Host " -with- "
Write-Host $GITHUB_PAT
Write-Host "======================="
$TOKEN_RESP = (Invoke-RestMethod -Method Post -Uri "$GITHUB_URL/enterprises/agoda/actions/runners/registration-token" -Headers $githubheaders -Proxy "http://my-proxy.loca:8080" -UseBasicParsing).token
Write-Host $TOKEN_RESP


$name = New-Guid
./config.cmd --url https://github.com/enterprises/agoda --token $TOKEN_RESP --name $name --work "w" --unattended --runasservice


Write-Output "==== github done ===="
