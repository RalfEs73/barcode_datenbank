
<#
.SYNOPSIS
  Fügt einen neuen Datensatz in PocketBase (Collection "Barcode_Datenbank") hinzu – nur für eingeloggte User.
  Nutzt PB_IDENTITY / PB_PASSWORD aus Umgebungsvariablen, mit Fallback auf Eingabe.


# Systemweit (Machine) – benötigt Admin
    # [Environment]::SetEnvironmentVariable("PB_IDENTITY","benutzer@email.de","Machine")
    # [Environment]::SetEnvironmentVariable("PB_PASSWORD","KENNWORT","Machine")
    # Get-ChildItem Env:PB_IDENTITY, Env:PB_PASSWORD

.PARAMS
  -UseCreatedBy  Setzt createdBy = eigene User-ID (wenn Create-Rule das verlangt).
  -SkipDuplicateCheck  Überspringt die Duplikatprüfung.

.NOTES
  Create-Rule in PB:
    - alle eingeloggten User:            @request.auth.id != ""
    - bestimmter User (ID):              @request.auth.id = "USER_ID"
    - via Relation createdBy (empfohlen):@request.data.createdBy = @request.auth.id
#>

[CmdletBinding()]
param(
    [string]$PbBaseUrl  = "https://pocketbase.ralfes.cloud",
    [string]$Collection = "Barcode_Datenbank",
    [string]$AuthColl   = "users",
    [switch]$SkipDuplicateCheck
)

function Read-NonEmpty([string]$prompt) {
    while ($true) {
        $val = Read-Host $prompt
        if (![string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
        Write-Host "Eingabe darf nicht leer sein." -ForegroundColor Yellow
    }
}

try {
    # --- 0) Identity & Passwort aus ENV lesen, sonst Fallback auf Eingabe ---
    $identity = $env:PB_IDENTITY
    $password = $env:PB_PASSWORD

    if ([string]::IsNullOrWhiteSpace($identity)) {
        $identity = Read-NonEmpty "Login (E-Mail oder Username)"
    }
    if ([string]::IsNullOrWhiteSpace($password)) {
        $securePw = Read-Host "Passwort" -AsSecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePw)
        )
    }

    # --- Login gegen Auth-Collection ---
    $authUri  = "$PbBaseUrl/api/collections/$AuthColl/auth-with-password"
    $authBody = @{ identity = $identity; password = $password } | ConvertTo-Json
    $authResp = Invoke-RestMethod -Uri $authUri -Method POST -ContentType "application/json" `
                                  -Body $authBody -ErrorAction Stop

    $token  = $authResp.token
    $userId = $authResp.record.id
    if (-not $token) { throw "Kein Token erhalten. Prüfe Auth-Settings der '$AuthColl'." }

    $headers = @{ Authorization = "Bearer $token" }

    # --- 1) Interaktive Eingaben für den neuen Datensatz ---
    $barcode    = Read-NonEmpty "Barcode eingeben"
    $hersteller = Read-NonEmpty "Hersteller eingeben"
    $produkt    = Read-NonEmpty "Produktname eingeben"

    if ($barcode -notmatch '^\d+$') {
        Write-Error "Der Barcode sollte nur aus Ziffern bestehen."
        exit 2
    }

    # --- 2) Duplikat-Check ---
    if (-not $SkipDuplicateCheck) {
        $filter   = [System.Uri]::EscapeDataString("Barcode='$barcode'")
        $checkUri = "$PbBaseUrl/api/collections/$Collection/records?filter=$filter&perPage=1"

        $checkResp = Invoke-RestMethod -Uri $checkUri -Headers $headers -Method GET -ErrorAction Stop
        if ($null -ne $checkResp.items -and $checkResp.items.Count -gt 0) {
            $existing = $checkResp.items[0]
            Write-Host "Hinweis: Barcode '$barcode' existiert bereits (ID: $($existing.id))." -ForegroundColor Yellow
            # Write-Host "Abbruch, um Duplikate zu vermeiden. Starte mit -SkipDuplicateCheck, falls gewünscht."
            exit 3
        }
    }

    # --- 3) POST Create ---
    $payload = @{
        Barcode    = $barcode
        Hersteller = $hersteller
        Produkt    = $produkt
    }
    if ($UseCreatedBy) { $payload.createdBy = $userId }  # Relation-Feld (optional)

    $createUri = "$PbBaseUrl/api/collections/$Collection/records"
    $resp = Invoke-RestMethod -Uri $createUri -Method POST -Headers $headers `
                              -ContentType "application/json" -Body ($payload | ConvertTo-Json) `
                              -ErrorAction Stop

    # --- 4) Ergebnis ---
    if ($resp) {
        [pscustomobject]@{
            ID         = $resp.id
            Barcode    = $resp.Barcode
            Hersteller = $resp.Hersteller
            Produkt    = $resp.Produkt
            Created    = $resp.created
            Updated    = $resp.updated
        } | Format-List
        exit 0
    } else {
        Write-Error "Unerwartete leere Antwort von PocketBase."
        exit 1
    }
}
catch {
    Write-Error "Fehler: $($_.Exception.Message)"
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Error "Details: $($_.ErrorDetails.Message)"
    }
    exit 1
}
