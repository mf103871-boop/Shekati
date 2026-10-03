[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9 ._-]{1,80}$')][string]$CommonName,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')][string]$Email,
    [string]$OpenSSLPath = 'C:\Program Files\Git\usr\bin\openssl.exe'
)

$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathRooted($PrivateDirectory)) { throw 'Choose an absolute private directory path outside the app repository.' }
$privateRoot = [IO.Path]::GetFullPath($PrivateDirectory).TrimEnd('\', '/')
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\', '/')
if ($privateRoot.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $privateRoot.StartsWith($repositoryRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing material must be outside the app repository.'
}
if (Test-Path -LiteralPath $privateRoot) { throw 'Choose a new private directory; existing directories are not modified.' }
if (-not (Test-Path -LiteralPath $OpenSSLPath -PathType Leaf)) { throw 'OpenSSL was not found. Supply -OpenSSLPath for your trusted local OpenSSL installation.' }

New-Item -ItemType Directory -Path $privateRoot | Out-Null
$accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$directoryACL = New-Object Security.AccessControl.DirectorySecurity
$directoryACL.SetOwner($accountSid)
$directoryACL.SetAccessRuleProtection($true, $false)
$accessRule = New-Object Security.AccessControl.FileSystemAccessRule(
    $accountSid,
    [Security.AccessControl.FileSystemRights]::FullControl,
    [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [Security.AccessControl.PropagationFlags]::None,
    [Security.AccessControl.AccessControlType]::Allow
)
$directoryACL.AddAccessRule($accessRule)
Set-Acl -LiteralPath $privateRoot -AclObject $directoryACL

$keyPath = Join-Path $privateRoot 'distribution.key.pem'
$requestPath = Join-Path $privateRoot 'distribution.certSigningRequest'
Write-Host 'OpenSSL will ask for a private-key passphrase. Enter it directly at the prompt; do not put it in this command.'
& $OpenSSLPath genpkey -algorithm RSA -aes-256-cbc -pkeyopt rsa_keygen_bits:2048 -out $keyPath
if ($LASTEXITCODE -ne 0) { throw 'Encrypted private-key generation failed. No certificate was requested.' }
& $OpenSSLPath req -new -sha256 -key $keyPath -out $requestPath -subj "/CN=$CommonName/emailAddress=$Email"
if ($LASTEXITCODE -ne 0) { throw 'CSR generation failed. Preserve the private key and investigate the OpenSSL error.' }
Write-Host 'CSR prepared. Upload only distribution.certSigningRequest to the Apple certificate form.'
Write-Host 'Keep distribution.key.pem and its passphrase private; neither file contents nor passwords were printed.'
