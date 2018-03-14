# iis-counter-check



#monitor for requests executing
#if that goes to 100 and stays at 100 then we would need to recycle the app pools

#W3SVC_W3WP

#list all counters (EXAMPLE)
#$meh = Get-Counter -ListSet * | Select-Object CounterSetName, CounterSetType, Description, Paths 

#list all active request counters (EXAMPLE)
#get-counter -counter "\\$env:computername\\ASP.NET Apps v4.0.30319(__Total__)\Requests Executing"

#get for specific site (EXAMPLE)
#Get-Counter -Counter '\W3SVC_W3WP(13736_Skins.mppglobal.com)\Active Requests'


ensure you have iis scripting tools feature installed 