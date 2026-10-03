[CmdletBinding(DefaultParameterSetName = 'Copy')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Copy')][string]$Path,
    [Parameter(Mandatory = $true, ParameterSetName = 'Clear')][switch]$Clear
)

$ErrorActionPreference = 'Stop'
if ($Clear) {
    Set-Clipboard -Value ''
    Write-Host 'Clipboard cleared.'
    return
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'The signing file was not found.' }
$resolvedSigningPath = (Resolve-Path -LiteralPath $Path).ProviderPath
$extension = [IO.Path]::GetExtension($resolvedSigningPath).ToLowerInvariant()
if ($extension -notin @('.p12', '.p8', '.mobileprovision')) { throw 'Choose a P12 certificate, P8 API private key or provisioning profile.' }
$file = Get-Item -LiteralPath $resolvedSigningPath
if ($file.Length -gt 2MB) { throw 'The file is larger than expected for signing material. Verify the selected file.' }
$signingBytes = [IO.File]::ReadAllBytes($resolvedSigningPath)
try {
    Set-Clipboard -Value ([Convert]::ToBase64String($signingBytes))
    Write-Host 'Base64 copied to clipboard without printing it. Paste directly into the corresponding GitHub Secret, then clear the clipboard.'
} finally {
    [Array]::Clear($signingBytes, 0, $signingBytes.Length)
}
