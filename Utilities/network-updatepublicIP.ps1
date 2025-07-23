<#
.SYNOPSIS
    A boilerplate PowerShell script for updating public IP in Cloudflare's DNS records

.NOTES
    Author: Collyn Camara
    Date: $(Get-Date -Format "yyyy-MM-dd")


    Use the following block to load env variables from a .env file. The current method is set up for loading env variables from Semaphore UI's key store.
    #######################################
    $envFile = Get-Content -Path "./.env"

    # ENV Secrets
    $CLOUDFLARE_DNS_API_KEY = $envFile | Where-Object { $_ -match "^CLOUDFLARE_DNS_API_KEY=" } | ForEach-Object { $_.Split('=')[1] }
    $CLOUDFLARE_DNS_ZONE_ID = $envFile | Where-Object { $_ -match "^CLOUDFLARE_DNS_ZONE_ID=" } | ForEach-Object { $_.Split('=')[1] }
    $CLOUDFLARE_DNS_RECORD_NAME = $envFile | Where-Object { $_ -match "^CLOUDFLARE_DNS_RECORD_NAME=" } | ForEach-Object { $_.Split('=')[1] }
    #######################################
#>

############# INITIZALIZE LOGGING #############
$VerbosePreference = "Continue"
Write-Verbose "Initializing logging..."
############# END INITIZALIZE LOGGING #############

############# LOAD VARIABLES #############
Write-Verbose "Loading environment variables from .env file..."

$CLOUDFLARE_DNS_API_KEY = $env:CLOUDFLARE_DNS_API_KEY
$CLOUDFLARE_DNS_ZONE_ID = $env:CLOUDFLARE_DNS_ZONE_ID
$CLOUDFLARE_DNS_RECORD_NAME = $env:CLOUDFLARE_DNS_RECORD_NAME
if (-not $CLOUDFLARE_DNS_API_KEY -or -not $CLOUDFLARE_DNS_ZONE_ID -or -not $CLOUDFLARE_DNS_RECORD_NAME) {
    Write-Error "Required environment variables are not set. Please check your .env file."
    exit 1
}

Write-Verbose "Environment variables loaded successfully."
Write-Verbose "Creating global variables for runtime..."

# Gloabal Predefined Variables
$CLOUDFLARE_DNS_RECORD_ID = $null
$CLOUDFLARE_DNS_RECORDS_URL = "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_DNS_ZONE_ID/dns_records"

Write-Verbose "Global variables created successfully."
############# END LOAD VARIABLES #############

############# FUNCTIONS #############

function Get-DNSRecord {
    param (
        [string]$RecordName,
        [string]$APIKey
    )

    $Method = "GET"
    $Headers = @{
        "Authorization" = "Bearer $APIKey"
    }

    try{
        $DNS_Records = Invoke-RestMethod -URI $CLOUDFLARE_DNS_RECORDS_URL -Method $Method -Headers $Headers
    }
    catch {
        Write-Error "Failed to get DNS records: $_"
        return $null
    }

    return $DNS_Records.result | Where-Object { $_.name -eq $RecordName }
}

function Update-DNSRecord {
    param (
        [string]$RecordID,
        [string]$PublicIP,
        [string]$APIKey
    )

    $Method = "PATCH"
    $Headers = @{
        "Authorization" = "Bearer $APIKey"
    }
    $Body = @{
        type = "A"
        name = $CLOUDFLARE_DNS_RECORD_NAME
        content = $PublicIP
        ttl = 1
        proxied = $false
    } | ConvertTo-Json

    try {
        $Response = Invoke-RestMethod -URI "$CLOUDFLARE_DNS_RECORDS_URL/$RecordID" -Method $Method -Headers $Headers -Body $Body -ContentType "application/json"
        if ($Response.success) {
            Write-Verbose "DNS record updated successfully."
            return $Response.result
        } else {
            Write-Error "Failed to update DNS record: $($Response.errors | Out-String)"
            return $null
        }
    } catch {
        Write-Error "An error occurred while updating the DNS record: $_"
        return $null
    }

}

############# END FUNCTIONS #############
############# MAIN CODE #############
Write-Verbose "Starting main code execution..."
Write-Verbose "Checking if required environment variables are set..."
if (-not $CLOUDFLARE_DNS_API_KEY -or -not $CLOUDFLARE_DNS_ZONE_ID -or -not $CLOUDFLARE_DNS_RECORD_NAME) {
    Write-Error "Required environment variables are not set. Please check your .env file."
    exit 1
}

# Get the DNS record ID for the specified record name
Write-Verbose "Retrieving DNS record ID for '$CLOUDFLARE_DNS_RECORD_NAME'..."
$CLOUDFLARE_DNS_RECORD_ID = (Get-DNSRecord -RecordName $CLOUDFLARE_DNS_RECORD_NAME -APIKey $CLOUDFLARE_DNS_API_KEY).id
if (-not $CLOUDFLARE_DNS_RECORD_ID) {
    Write-Error "Something went wrong while getting the DNS record for: '$CLOUDFLARE_DNS_RECORD_NAME'."
    exit 1
}

# Get the current public IP address
$PublicIP = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
Write-Verbose "Current public IP is: $PublicIP"

# Update the DNS record with the current public IP address
$UpdatedRecordResponse = Update-DNSRecord -RecordID $CLOUDFLARE_DNS_RECORD_ID -PublicIP $PublicIP -APIKey $CLOUDFLARE_DNS_API_KEY
if (-not $UpdatedRecordResponse) {
    Write-Error "Failed to update the DNS record with the current public IP."
    exit 1
}

return $UpdatedRecordResponse