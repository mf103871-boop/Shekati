[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [ValidateSet('DER', 'PEM')][string]$CertificateFormat = 'DER',
    [string]$OpenSSLPath = 'C:\Program Files\Git\usr\bin\openssl.exe'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\', '/')
foreach ($privatePath in @($PrivateKeyPath, $OutputPath)) {
    if (-not [IO.Path]::IsPathRooted($privatePath)) { throw 'Use absolute private file paths outside the app repository.' }
    $resolvedPrivatePath = [IO.Path]::GetFullPath($privatePath)
    if ($resolvedPrivatePath.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPrivatePath.StartsWith($repositoryRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The private key and exported certificate must be outside the app repository.'
    }
}
foreach ($inputPath in @($OpenSSLPath, $PrivateKeyPath, $CertificatePath)) {
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) { throw 'A required OpenSSL, private-key or certificate file was not found.' }
}
$keyDirectory = [IO.Path]::GetFullPath((Split-Path -Path $PrivateKeyPath -Parent)).TrimEnd('\', '/')
$outputDirectory = [IO.Path]::GetFullPath((Split-Path -Path $OutputPath -Parent)).TrimEnd('\', '/')
if (-not $keyDirectory.Equals($outputDirectory, [StringComparison]::OrdinalIgnoreCase)) { throw 'Export into the same protected directory as the encrypted private key.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'The output file already exists; this helper never overwrites certificates.' }
$certificatePEM = Join-Path $outputDirectory 'distribution.apple.pem'
if (Test-Path -LiteralPath $certificatePEM) { throw 'distribution.apple.pem already exists. Choose a fresh protected directory or inspect that certificate first.' }
& $OpenSSLPath x509 -inform $CertificateFormat -in $CertificatePath -out $certificatePEM
if ($LASTEXITCODE -ne 0) { throw 'Apple certificate conversion failed. Check -CertificateFormat.' }
Write-Host 'Enter the private-key passphrase, then choose a nonempty export password for the P12 at OpenSSL prompts.'
& $OpenSSLPath pkcs12 -export -inkey $PrivateKeyPath -in $certificatePEM -out $OutputPath -name 'Shekati Apple Distribution'
if ($LASTEXITCODE -ne 0) { throw 'P12 export failed. The certificate may not match this private key.' }
Write-Host 'Password-protected P12 exported locally. Put its base64 contents and export password directly into GitHub Secrets.'
