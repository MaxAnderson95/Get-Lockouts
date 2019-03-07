Function Get-Lockouts {

    <#
    
        .SYNOPSIS
        Returns user lockout logs in the domain

        .DESCRIPTION
        Returns user lockout logs in the domain.

        .PARAMETER AllDomainControllers
        Specifies to return log results from all domain controllers in the domain. If left unspecified, only domain controllers in the
        current site on the computer running the script are quieried.

        .PARAMETER QueryEntireLog
        Specifies to return all available log entries regardless of their date and time stamp. If left unspecified, only logs generated
        in the last 4 hours are returned.

        .EXAMPLE
        PS> Get-Lockouts
        Username    Lockout Origin Lockout Time         Domain Controller
        --------    -------------- ------------         -----------------
        Bob.Smith   COMPUTER01     3/6/2019 10:22:54 PM DC01
        John.Doe    COMPUTER02     3/6/2019 9:52:54 PM  DC02
        Sally.Smith COMPUTER03     3/6/2019 9:22:53 PM  DC01
        Jane.Doe    COMPUTER04     3/6/2019 8:52:53 PM  DC02

        .EXAMPLE
        PS> Get-Lockouts -AllDomainControllers
        ...

        .EXAMPLE
        PS> Get-Lockouts -QueryEntireLog
        ...

    #>

    [CmdletBinding()]
    Param(

        [Parameter(Position=0)]
        [Switch]$AllDomainControllers,

        [Parameter(Position=1)]
        [Switch]$QueryEntireLog

    )

    #Get a list of domain controllers
    If ($AllDomainControllers) {

        $DCFilter = '*'

    } Else {

        $CurrentSite = (Get-ADDomainController).Site

        $DCFilter = 'isReadOnly -eq $False -and Site -eq $CurrentSite'

    }

    $DomainControllers = Get-ADDomainController -Filter $DCFilter

    #Loop through each domain controller
    ForEach ($DomainController in $DomainControllers) {
        
        #Create a new job with the name of the domain controller
        Start-Job -Name $DomainController.Name -ScriptBlock {

            #Invoke a command on the domain controller
            Invoke-Command -ComputerName $args[0].Name -ScriptBlock {

                #Get's a list of lockouts
                $Lockouts = Get-WinEvent -FilterHashtable @{"LogName"="Security";"ID"=4740} -ErrorAction SilentlyContinue

                #Loops through each lockout
                ForEach ($Lockout in $Lockouts) {

                    #Creates a custom object with the relavant data
                    [PSCustomObject]@{

                        "Username" = $Lockout.Properties[0].Value
                        "Lockout Origin" = $Lockout.Properties[1].Value
                        "Lockout Time" = $Lockout.TimeCreated
                        "Domain Controller" = $env:COMPUTERNAME

                    }

                }

            }

        } -ArgumentList $DomainController | Out-Null #Passes the current domain controller object through to the job's runtime environment

    }

    #Gets a list of the jobs, and instructs the script to wait until they are complete
    Get-Job | Wait-Job | Out-Null

    #Gets a list of the jobs and then receives their data
    $RawData = Get-Job | Receive-Job
    
    #Gets the Raw data, selects the properties that are relavant and then sorts them by username
    $FormattedData = $RawData | Select-Object -Property Username,"Lockout Origin","Lockout Time","Domain Controller" | Sort-Object -Property "Lockout Time" -Descending

    #If query all is selected, return the results without filtering
    If ($QueryEntireLog -eq $True) {

        Write-Output $FormattedData

    } Else {

        #Otherwise filter the results for logs newer than the default number of hours

        $DefaultNumberOfHours = 4

        $FilteredData = $FormattedData | Where {$_."Lockout Time" -gt $((Get-Date).AddHours(-$DefaultNumberOfHours))}

        Write-Output $FilteredData

    }

}
