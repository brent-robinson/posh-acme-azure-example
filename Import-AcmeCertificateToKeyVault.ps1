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
$currentServerName = ((Get-PAServer).location) -split "/" | Where-Object -FilterScript { $_ } | Select-Object -Skip 1 -First 1
$currentAccountName = (Get-PAAccount).id

# Determine paths to resources
$orderDirectoryPath = Join-Path -Path $workingDirectory -ChildPath $currentServerName | Join-Path -ChildPath $currentAccountName | Join-Path -ChildPath $certificateName
$orderDataPath = Join-Path -Path $orderDirectoryPath -ChildPath "order.json"
$pfxFilePath = Join-Path -Path $orderDirectoryPath -ChildPath "fullchain.pfx"

# If we have a order and certificate available
if ((Test-Path -Path $orderDirectoryPath) -and (Test-Path -Path $orderDataPath) -and (Test-Path -Path $pfxFilePath)) {

    $pfxPass = (Get-PAOrder $certificateName).PfxPass

    # Load PFX
    $certificate = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $pfxFilePath, $pfxPass, 'EphemeralKeySet'

    # Get the current certificate from key vault (if any)
    $azureKeyVaultCertificateName = $certificateName.Replace(".", "-").Replace("!", "wildcard")
    $keyVaultResource = Get-AzResource -ResourceId $KeyVaultResourceId
    $azureKeyVaultCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -ErrorAction SilentlyContinue

    # If we have a different certificate, import it
    If (-not $azureKeyVaultCertificate -or $azureKeyVaultCertificate.Thumbprint -ne $certificate.Thumbprint) {
        Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -FilePath $pfxFilePath -Password (ConvertTo-SecureString -String $pfxPass -AsPlainText -Force) | Out-Null
    }
}
