#monitor for requests executing
#if that goes to 100 and stays at 100 then we would need to recycle the app pools

#W3SVC_W3WP

#list all counters (EXAMPLE)
#$meh = Get-Counter -ListSet * | Select-Object CounterSetName, CounterSetType, Description, Paths 

#list all active request counters (EXAMPLE)
#get-counter -counter "\\$env:computername\\ASP.NET Apps v4.0.30319(__Total__)\Requests Executing"

#get for specific site (EXAMPLE)
#Get-Counter -Counter '\W3SVC_W3WP(13736_Skins.mppglobal.com)\Active Requests'
##################### VARIABLES ###########################
$logFile = "C:\logs\IIS_Active_Requests"
$reqsLimit = "99"
$offenderSites = $null
$executingHash = $null
Import-Module WebAdministration

#####################CHECK START###########################
#run check against total requests

function Write-Tee($Message)
{
    #Zip Up any old Logs (older than a day)
    $oldLogs = Get-childItem $logFile -Filter *.log | where {$_.CreationTime -lt (Get-Date).AddDays(-1)}
    if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe")) {throw "$env:ProgramFiles\7-Zip\7z.exe needed"} 
    set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"  
    $source = $null
    $target = $Null
    foreach ($file in $oldLogs)
        {
        $Source = "$($logfile)\$file"
        $Target =  "$($logfile)\oldlogs.7z"
        sz a -mx=9 $Target $Source
        Remove-Item $Source -Force
        }
    
    #Write the file out
    Tee-Object -FilePath "$($logfile)\IIS_Active_Requests.log" -Append -InputObject "[$(Get-Date)]: $Message"
}

function Invoke-Recycle($Site)
{
    #$pool = (Get-Item "IIS:\Sites\$Site"| Select-Object applicationPool).applicationPool
    #Restart-WebAppPool $pool
    (Get-Item "IIS:\Sites\*" | Select-Object applicationPool).applicationPool | Restart-WebAppPool
    Write-Tee "App Pools Recycled"
}

#Must call this prior to "get-child item for some reason, no idea why
$sitelist = Get-Website 

#Get all the sites and their IDs
$sites = Get-ChildItem IIS:\Sites | Select-Object ID, NAME | Sort-Object ID

#Get all the web apps (not used yet)
$apps = Get-WebApplication

#initalise the hashtable

$executingHash = @{}

#For each site found, run a counter pull agist the site ID and the requests executing
foreach ($site in $sites)
{
    
    $reqsExecuting = get-counter -counter "\\$env:computername\\ASP.NET Apps v4.0.30319(_lm_w3svc_$($site.id)_root)\Requests Executing" -ErrorAction Ignore
    
    #Build Up a HashTable to store site IDs and their current executing count
    $executingHash.add($site.id, $reqsExecuting.CounterSamples.cookedValue)

    #if a result is found output the info for that sitename
    if ($reqsExecuting -ne $null)
    {
    Write-Tee "Site ID: $($site.id), Name: $($site.name) -  Current Executing Requests: $($reqsExecuting.CounterSamples.cookedValue)"
    }
    Else
    # site ID did not match with the counter
    {
    Write-Tee "Site ID: $($site.id), Name: $($site.name) - No Counter Found for Site ID"
    }
}

#Total executing output
$totalExecutingRequests = get-counter -counter "\\$env:computername\\ASP.NET Apps v4.0.30319(__Total__)\Requests Executing"
Write-Tee "Total number of all Executing Requests: $($totalExecutingRequests.CounterSamples.CookedValue)"
write-tee "Limit currently set to: $($reqsLimit)"


#Check to see if total limit has been breached
if ($totalExecutingRequests.CounterSamples.cookedvalue -gt $reqsLimit)
{
    #Outputs info for each site
    foreach ($siteReq in $executingHash.GetEnumerator())
    {
        #Exclude checks with no counters
        if ($siteReq.value -ne $null)
        {
            
            #Pulls in the site counter value and convert to int 
            $reqCount = $siteReq.value
            $reqCount = [convert]::ToInt32($reqCount)
        
            #pulls in the site info based on the site ID 
            $siteItem =  Get-ChildItem IIS:\Sites | Where-Object ID -eq $siteReq.name

            #gets the site name based from the site info
            $siteName = $siteItem.name
        
            #Write-Tee "$($siteName) is currently at $($reqCount)"
            if ($reqCount -gt $reqsLimit)
            {
            #Write-Tee "$siteName is over $($reqsLimit)!"
            [array]$offenderSites += $siteName
            }
        }
    }

    # Take Action
    Write-Tee "Recycling all app pools"
            
    #recycle the app pools
    Invoke-Recycle
    
    # Slack message
    $Message = "@here - ASP Total Requests executing is currently at $($totalExecutingRequests.CounterSamples.cookedvalue) active requests on $($env:computername).
                I have taken the liberty to recycle the App pools, as the site(s) $($offenderSites) has exceeded the set limit of $($reqsLimit).
                Sleep now sweet humans, I am now in control of everything.
                See$($logFile)\IIS_Active_Requests.log for detailed info on which site(s) were under load and ticker history."
    $Channel = '#infrastructure'
    $payload = @{
        "channel" = $Channel
        "icon_url" = 'http://orig12.deviantart.net/89ff/f/2011/266/f/3/mudkip_by_fawfuldude11-d4apyis.jpg'
        "text" = $Message
        "username" = 'IIS_Bot'
        "link_names" = 1 #added this to allow us to call users in messages
    }

    Invoke-WebRequest -UseBasicParsing `
        -Body (ConvertTo-Json -Compress -InputObject $payload) `
        -Method Post `
        -Uri "WEBHOOK GOES HERE" | Out-Null
}
 
