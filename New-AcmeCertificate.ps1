param (
    [string] $AcmeDirectory,
    [string] $AcmeContact,
    [string] $CertificateNames,
    [string] $StorageContainerSASToken,
    [string] $CloudFlareAPIToken
)

# Supress progress messages. Azure DevOps doesn't format them correctly (used by New-PACertificate)
$global:ProgressPreference = 'SilentlyContinue'

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
$account = Get-PAAccount
if (-not $account) {
    # New account
    $account = New-PAAccount -Contact $AcmeContact -AcceptTOS -Force
}
elseif ($account.contact -ne "mailto:$AcmeContact") {
    # Update account contact
    Set-PAAccount -ID $account.id -Contact $AcmeContact
}

$pArgs = @{ CFTokenInsecure = $CloudFlareAPIToken }
New-PACertificate -Domain $CertificateNamesArr -DnsPlugin Cloudflare -PluginArgs $pArgs

# Sync working directory back to storage container
azcopy10 sync "$workingDirectory" "$StorageContainerSASToken"