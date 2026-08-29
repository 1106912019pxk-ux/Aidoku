[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$gitPath = Join-Path $resolvedRoot ".git"

if (-not (Test-Path -LiteralPath $gitPath -PathType Container)) {
    Write-Error "Expected a .git directory at '$gitPath'. This check does not initialize or repair repositories."
    exit 2
}

$repositoryOwner = (Get-Acl -LiteralPath $resolvedRoot).Owner
$gitOwner = (Get-Acl -LiteralPath $gitPath).Owner
$sandboxOwnerPattern = "\\CodexSandbox(?:Online|Offline)$"

if ($gitOwner -ne $repositoryOwner -or $gitOwner -match $sandboxOwnerPattern) {
    Write-Error @"
Git ownership check failed.
Repository: $resolvedRoot
Repository owner: $repositoryOwner
.git owner: $gitOwner

Do not bypass this with safe.directory for the writable project. Repair the .git root owner before continuing.
"@
    exit 1
}

Write-Output "Git ownership check passed."
Write-Output "Repository: $resolvedRoot"
Write-Output "Owner: $gitOwner"
