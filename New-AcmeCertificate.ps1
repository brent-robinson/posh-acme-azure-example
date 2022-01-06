param (
    [string] $AcmeDirectory,
    [string] $AcmeContact,
    [string] $CertificateNames,
    [string] $StorageContainerSASToken,
    [string] $CloudFlareAPIToken
)

# Supress progress messages. Azure DevOps doesn't format them correctly (used by New-PACertificate)
$global:ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop"

# Split certificate names by comma or semi-colin
$CertificateNamesArr = $CertificateNames.Replace(',',';') -split ';' | ForEach-Object -Process { $_.Trim() }

# Create working directory
$workingDirectory = Join-Path -Path "." -ChildPath "pa"
Remove-Item $workingDirectory -Recurse -ErrorAction Ignore
New-Item -Path $workingDirectory -ItemType Directory | Out-Null

# Sync contents of storage container to working directory
# MSFT Hosted Ubuntu defaults to azcopy v 7 if alias azcopy10 is not specified
azcopy10 sync "$StorageContainerSASToken" "$workingDirectory"

# Set Posh-ACME working directory
$env:POSHACME_HOME = $workingDirectory
Import-Module Posh-ACME -Force

# Configure Posh-ACME server
Set-PAServer -DirectoryUrl $AcmeDirectory

# Configure Posh-ACME account
$accounts = Get-PAAccount -List
if (-not $accounts -or $accounts.Length -eq 0) {
    # New account
    $account = New-PAAccount -Contact $AcmeContact -AcceptTOS -Force
} else {
    $account = $accounts[0]
}

echo "Account"
$account
$account | Set-PAAccount
echo ""

echo "Orders"
Get-PAOrder -List
echo ""

# If only one host name is passed, $CertificateNamesArr will be a string instead of an array
if ($CertificateNamesArr -is [array]) {
    $order = Get-PAOrder $CertificateNamesArr[0]
} else {
    $order = Get-PAOrder $CertificateNamesArr
}

echo "Selected Order"
$order | Format-Table
echo ""

if (-not $order) {
    $pArgs = @{ CFTokenInsecure = $CloudFlareAPIToken }
    New-PACertificate -Domain $CertificateNamesArr -DnsPlugin Cloudflare -PluginArgs $pArgs
} else {
    # Posh-ACME doesn't support setting a renewal window. Its renewal window defaults to 2/3
    # of the lifetime of the certificate
    # https://github.com/rmbolger/Posh-ACME/blob/f11192ba8796e41cb0ec2e84c3d4034239044be2/Posh-ACME/Public/Complete-PAOrder.ps1#L59-L65
    # Since we use lets encrypt (90 day certs) that will mean renew after 30 days remaining.
    # Since Okta sends us cert warnings at 30 days, we want to renew a little bit sooner, so we
    # will force renewal at 45 days
    # KMS 2022 JAN 5
    if ($order.CertExpires -eq $null -or $(New-Timespan -Start $(Get-Date) -End $order.CertExpires).Days -lt 45) {
        echo "Renewing with force"
        Submit-Renewal -Force
    } else {
        echo "Renewing"
        Submit-Renewal
    }
}

# Sync working directory back to storage container
azcopy10 sync "$workingDirectory" "$StorageContainerSASToken"