param (
    [string] $CertificateNames,
    [string] $KeyVaultResourceId
)

# Split certificate names by comma or semi-colon
$certificateName = $CertificateNames.Replace(',', ';') -split ';' | ForEach-Object -Process { $_.Trim() } | Select-Object -First 1

# For wildcard certificates, Posh-ACME replaces * with ! in the directory name
$certificateName = $certificateName.Replace('*', '!')

# Set working directory
$workingDirectory = Join-Path -Path "." -ChildPath "pa"

# Set Posh-ACME working directory
$env:POSHACME_HOME = $workingDirectory
Import-Module -Name Posh-ACME -Force

# Resolve the details of the certificate
$currentServerName = ((Get-PAServer).Name)
$currentAccountName = (Get-PAAccount).id

# Determine paths to resources
$orderDirectoryPath = Join-Path -Path $workingDirectory -ChildPath $currentServerName | Join-Path -ChildPath $currentAccountName | Join-Path -ChildPath $certificateName
$orderDataPath = Join-Path -Path $orderDirectoryPath -ChildPath "order.json"
$pfxFilePath = Join-Path -Path $orderDirectoryPath -ChildPath "fullchain.pfx"

# If we have a order and certificate available
if ((Test-Path -Path $orderDirectoryPath) -and (Test-Path -Path $orderDataPath) -and (Test-Path -Path $pfxFilePath)) {

    # Load order data
    $pfxPass = (Get-PAOrder -Name $certificateName).PfxPass
    $securePfxPass = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    
    # Load PFX
    $certificate = Get-PfxCertificate $pfxFilePath -Password $securePfxPass

    # Get the current certificate from key vault (if any)
    $azureKeyVaultCertificateName = $certificateName.Replace(".", "-").Replace("!", "wildcard")
    $keyVaultResource = Get-AzResource -ResourceId $KeyVaultResourceId
    $azureKeyVaultCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -ErrorAction SilentlyContinue

    # If we have a different certificate, import it
    If (-not $azureKeyVaultCertificate -or $azureKeyVaultCertificate.Thumbprint -ne $certificate.Thumbprint) {
        Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -FilePath $pfxFilePath -Password $securePfxPass | Out-Null
    }
} else {
    Write-Output "Resource Path(s) not valid."
    exit 1
}
