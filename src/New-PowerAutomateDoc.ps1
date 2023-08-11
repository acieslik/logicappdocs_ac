[CmdletBinding(DefaultParameterSetName = 'PowerAutomate')]
Param(
    [Parameter(Mandatory = $true,
        ParameterSetName = 'PowerAutomate')]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true,
        ParameterSetName = 'PowerAutomate')]
    [string]$PowerAutomateName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Get-Location).Path
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'


@"
██╗      ██████╗  ██████╗ ██╗ ██████╗ █████╗ ██████╗ ██████╗ ██████╗  ██████╗  ██████╗███████╗
██║     ██╔═══██╗██╔════╝ ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██╔════╝██╔════╝
██║     ██║   ██║██║  ███╗██║██║     ███████║██████╔╝██████╔╝██║  ██║██║   ██║██║     ███████╗
██║     ██║   ██║██║   ██║██║██║     ██╔══██║██╔═══╝ ██╔═══╝ ██║  ██║██║   ██║██║     ╚════██║
███████╗╚██████╔╝╚██████╔╝██║╚██████╗██║  ██║██║     ██║     ██████╔╝╚██████╔╝╚██████╗███████║
╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚═════╝  ╚═════╝  ╚═════╝╚══════╝
                                                                                                                                                         
Author: Stefan Stranger
Github: https://github.com/stefanstranger/logicappdocs
Version: 1.1.0

"@.foreach({
        Write-Host $_ -ForegroundColor Magenta
    })

#region Import PowerShell Modules. Add more modules if needed
if (Get-Module -ListAvailable -Name PSDocs) {
    Write-Verbose -Message 'PowerShell Module PSDocs is already installed'
}
else {
    Write-Verbose 'Installing PowerShell Module PSDocs'
    Install-Module PSDocs -RequiredVersion 0.9.0 -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck -Confirm:$false -Force | Out-Null
}
if (Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell) {
    Write-Verbose -Message 'PowerShell Module Microsoft.PowerApps.Administration.PowerShell is already installed'
}
else {
    Write-Verbose 'Installing PowerShell Module Microsoft.PowerApps.Administration.PowerShell'
    Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck -Confirm:$false -Force | Out-Null
}
if (Get-Module -ListAvailable -Name Microsoft.PowerApps.PowerShell) {
    Write-Verbose -Message 'PowerShell Module Microsoft.PowerApps.PowerShell is already installed'
}
else {
    Write-Verbose 'Installing PowerShell Module Microsoft.PowerApps.PowerShell'
    Install-Module Microsoft.PowerApps.PowerShell -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck -Confirm:$false -Force | Out-Null
}
#endregion

#region dot source Helper Functions
. (Join-Path $PSScriptRoot 'Helper.ps1')
#endregion

#region Set Variables
$templateName = 'PowerAutomate-Documentation'
$templatePath = (Join-Path $PSScriptRoot 'PowerAutomate.Doc.ps1')
#endregion

#region Helper Functions
Function Create-ExportPackage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        $Flow
    )
    $reqUrl = ('https://preview.api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/{0}/exportPackage?api-version=2016-11-01-preview' -f $($flow.EnvironmentName))

    # Create REST API header
    $headers = @{
        'Authorization' = 'Bearer ' + (Get-JwtToken -Audience 'https://service.powerapps.com')
    }

    # Create REST API body    
    $body = @{
        includedResourceIds = @(
            "/providers/Microsoft.Flow/flows/$($flow.FlowName)"
        )
        details             = @{
            displayName       = $flow.DisplayName
            description       = $flow.DisplayName
            creator           = 'logicappdocs'
            sourceEnvironment = $flow.EnvironmentName
        }
    } | ConvertTo-Json    

    $invokeRestMethodSplat = @{
        Uri         = $reqUrl
        Method      = 'Post'
        Headers     = $headers
        ContentType = 'application/json'
        Body        = $body
    }

    Invoke-RestMethod @invokeRestMethodSplat
}

#region Main Script

#region login to Power Automate and get PowerAutomate Flow
Write-Host ('Login to Power Automate and get PowerAutomate Flow') -ForegroundColor Green
Get-Flow -EnvironmentName $EnvironmentName | Where-Object { $_.DisplayName -eq $PowerAutomateName } -OutVariable PowerAutomateFlow
#endregion

#region Create PowerAutomate Flow Export Package
Write-Host ('Create PowerAutomate Flow Export Package') -ForegroundColor Green
Create-ExportPackage -Flow $PowerAutomateFlow -OutVariable packageDownload
#endregion

#region download PowerAutomate Flow Export Package
Write-Host ('Download PowerAutomate Flow Export Package') -ForegroundColor Green
Start-BitsTransfer -Source $($packageDownload.packageLink.value) -Destination (Join-Path $($env:TEMP) ('{0}.zip' -f $($PowerAutomateFlow.DisplayName)))
#endregion

#region Unzip PowerAutomate Flow Export Package
Write-Host ('Unzip PowerAutomate Flow Export Package') -ForegroundColor Green
Expand-Archive -LiteralPath (Join-Path $($env:TEMP) ('{0}.zip' -f $($PowerAutomateFlow.DisplayName))) -DestinationPath $($env:TEMP) -Force
#endregion

#region refactor PowerAutomate Flow definition.json to align with LogicApp expected format
$PowerAutomateFlowJson = Get-Content -Path (Join-Path $($env:TEMP) ('Microsoft.Flow\flows\{0}\definition.json' -f $($packagedownload.resources.psobject.Properties.name[0]))) -Raw | ConvertFrom-Json
$PowerAutomateFlowDefinition = $PowerAutomateFlowJson.properties.definition
#endregion

$Objects = Get-Action -Actions $($PowerAutomateFlowJson.properties.definition.actions)

# Get Logic App Connections
if ($PowerAutomateFlowJson.properties | Get-Member -MemberType NoteProperty -Name 'connectionReferences') {
    $Connections = $($PowerAutomateFlowJson.properties.connectionReferences.psobject.properties.value)
}
else {
    $Connections = @()
}

# Get Logic App Triggers
if ($PowerAutomateFlowJson.properties.definition | Get-Member -MemberType NoteProperty -Name 'triggers') {
    $triggers = $($PowerAutomateFlowJson.properties.definition.triggers.psobject.Properties)
}
else {
    $triggers = @()
}


if ($VerbosePreference -eq 'Continue') {
    Write-Verbose -Message ('Found {0} actions in PowerAutomate Flow' -f $Objects.Count)
    Write-Verbose ($objects | Format-Table | out-string)
}

# Create the Mermaid code
Write-Host ('Creating Mermaid Diagram for Logic App') -ForegroundColor Green
$mermaidCode = "graph TB" + [Environment]::NewLine
$mermaidCode += "    $($triggers.name)" + [Environment]::NewLine

# Group actions by parent property
$objects | Group-Object -Property Parent | ForEach-Object {
    if (![string]::IsNullOrEmpty($_.Name)) {
        $subgraphName = $_.Name
        $mermaidCode += "    subgraph $subgraphName" + [Environment]::NewLine
        $mermaidCode += "    direction TB" + [Environment]::NewLine
        # Add children action nodes to subgraph
        foreach ($childAction in $_.Group.ActionName) {
            $mermaidCode += "        $childAction" + [Environment]::NewLine
        }
        $mermaidCode += "    end" + [Environment]::NewLine
    }
    else {}        
}

# Create links between runafter and actionname properties
foreach ($object in $objects) {
    if ($object | Get-Member -MemberType NoteProperty -Name 'RunAfter') {
        # Check if the runafter property is not empty
        if (![string]::IsNullOrEmpty($object.RunAfter)) {
            $mermaidCode += "    $($object.RunAfter) --> $($object.ActionName)" + [Environment]::NewLine
        }
    }        
}

# Create link between trigger and first action
$firstActionLink = ($objects | Where-Object { $_.Runafter -eq $null }).ActionName
$mermaidCode += "    $($triggers.name) --> $firstActionLink" + [Environment]::NewLine

Sort-Action -Actions $objects

if ($VerbosePreference -eq 'Continue') {
    Write-Verbose -Message ('Found {0} actions in PowerAutomate Flow' -f $Objects.Count)
    Write-Verbose ($objects | Select-Object -Property ActionName, RunAfter, Type, Parent, Order | Sort-Object -Property Order | Format-Table | Out-String)
}

#region Generate Markdown documentation for Power Automate Flow
$InputObject = [pscustomobject]@{
    'PowerAutomateFlow' = [PSCustomObject]@{
        Name            = $PowerAutomateName
        EnvironmentName = $environmentName
    }
    'Triggers'          = $triggers
    'Actions'           = $objects
    'Connections'       = $Connections
    'Diagram'           = $mermaidCode
}

$options = New-PSDocumentOption -Option @{ 'Markdown.UseEdgePipes' = 'Always'; 'Markdown.ColumnPadding' = 'Single' };
$null = [PSDocs.Configuration.PSDocumentOption]$Options

$invokePSDocumentSplat = @{
    Path = $templatePath
    Name = $templateName
    InputObject = $InputObject
    Culture = 'en-us'
    Option = $options
    OutputPath = $OutputPath
    InstanceName = $PowerAutomateName
}

$markDownFile = Invoke-PSDocument @invokePSDocumentSplat
Write-Host ('PowerAutomate Flow Markdown document is being created at {0}' -f $($markDownFile.FullName)) -ForegroundColor Green
#endregion