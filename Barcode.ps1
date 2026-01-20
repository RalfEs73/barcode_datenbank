
<# 
.SYNOPSIS
  Sucht in PocketBase nach einem Datensatz anhand eines Barcodes (Exact/Contains/ContainsCI).

.EXAMPLE
  .\Barcode.ps1 42270386

.EXAMPLE
  .\Barcode.ps1 2703 -Mode Contains -PerPage 10
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Barcode,

    [ValidateSet('Exact','Contains')]
    [string]$Mode = 'Exact',

    [string]$PbBaseUrl = "https://pocketbase.ralfes.cloud/",
    [string]$Collection = "Barcode_Datenbank",
    [int]$PerPage = 5
)

# Filter zusammenbauen
switch ($Mode) {
    'Exact'      { $filterRaw = "Barcode='$Barcode'" }
    'Contains'   { $filterRaw = "Barcode?~'$Barcode'" }   # enthält (case-insensitive)
}
$filter = [System.Uri]::EscapeDataString($filterRaw)
$uri = "$PbBaseUrl/api/collections/$Collection/records?filter=$filter&perPage=$PerPage"

try {
    $resp = Invoke-RestMethod -Uri $uri -Method GET -ErrorAction Stop

    if ($null -ne $resp.items -and $resp.items.Count -gt 0) {
        $resp.items |
            Select-Object id, Barcode, Hersteller, Produkt,created, updated
    }
    else {
        Write-Host "Keine Treffer für '$Barcode' (Mode=$Mode)." -ForegroundColor Yellow
        exit 2
    }
}
catch {
    Write-Error "Fehler beim Abruf: $($_.Exception.Message)"
    exit 1
}
