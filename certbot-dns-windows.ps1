#!/usr/bin/env pwsh

<#
    certbot-Hook for DNS validation in a Windows AD environment

    Uses PowerShell remoting to connect to the server and issues the dnscmd commands
    to set the TXT record for the given domain. This script assumes that you're using
    SSH to connect to the server and that an SSH key is used instead of password
    authentication!
#>

param(
    # The domain to validate
    [string] $domain,

    # The validation code
    [string] $validation,
    
    # Removes the TXT record if set
    [switch] $remove,

    # Enables debug output
    [switch] $debug
)

if ($debug) {
    $DebugPreference = 'Continue'
}

if ([string]::IsNullOrEmpty($domain)) {
    $domain = $env:CERTBOT_DOMAIN
}

if ([string]::IsNullOrEmpty($validation)) {
    $validation = $env:CERTBOT_VALIDATION
}

if ([string]::IsNullOrEmpty($domain)) {
    Write-Error 'The domain parameter or CERTBOT_DOMAIN environment variable are not set or empty'
    exit 1
}

if ([string]::IsNullOrEmpty($validation)) {
    Write-Error 'The validation parameter or CERTBOT_VALIDATION environment variable are not set or empty'
    exit 1
}

$zone = 'intern.domain.com'
$dnsServerHostName = 'your-win-dns-server.intern.domain.com'
$userName = 'domain\Administrator'

# This script assumes 
Write-Debug "Connecting to $dnsServerHostName as $userName"
$session = New-PSSession -HostName $dnsServerHostName -UserName $userName

# We have to remove the zone from the domain
$domain = "_acme-challenge.$($domain -replace ".$zone")"

try {
    if ($remove) {
        Write-Debug "Removing DNS record: $domain TXT $validation"
        $result = Invoke-Command -Session $session -ArgumentList $zone,$domain,$validation {
            param($zone,$domain,$validation)
            $output = & dnscmd /recorddelete "$zone" "$domain" TXT $validation /f 2>&1
            return @{ExitCode = $LASTEXITCODE; Output = $output} | ConvertTo-Json -Compress
        } | ConvertFrom-Json
    }
    else {
        Write-Debug "Adding DNS record: $domain TXT $validation"
        $result = Invoke-Command -Session $session -ArgumentList $zone,$domain,$validation {
            param($zone,$domain,$validation)
            $output = & dnscmd /recordadd "$zone" "$domain" /Aging 60 TXT $validation 2>&1
            return @{ExitCode = $LASTEXITCODE; Output = $output} | ConvertTo-Json -Compress
        } | ConvertFrom-Json
    }

    if ($result.ExitCode -ne 0) {
        $appOutput = [string]::Join([System.Environment]::NewLine, $result.Output)
        Write-Error $appOutput
        exit 3
    }
}
catch {
    Write-Error $_
    exit 2
}
finally {
    Write-Debug "Closing session"
    Remove-PSSession $session
}

exit 0
