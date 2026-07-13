
<# Please read the instruction in ONeNote before running the script, there are important modification to csv before running the script.

https://eddomemea.sharepoint.com/IT/L3/_layouts/OneNote.aspx?id=%2FIT%2FL3%2FSiteAssets%2FSystem%20Administration%20L3%20Notebook&wd=target%28CommVault%20-%20UK.one%7C15EF4F3E-2243-4376-B19F-1BD08F10AAC1%2FTape%20Audit%20procedure%7C2D04DAEE-462A-4689-BF89-8BB6E3BA57C9%2F%29
onenote:https://eddomemea.sharepoint.com/IT/L3/SiteAssets/System%20Administration%20L3%20Notebook/CommVault%20-%20UK.one#Tape%20Audit%20procedure&section-id={15EF4F3E-2243-4376-B19F-1BD08F10AAC1}&page-id={2D04DAEE-462A-4689-BF89-8BB6E3BA57C9}&end
#>


#Creating parameters for the require files for this script.
Param(
    [Parameter(Mandatory=$true)]
    $commvaultTapeInfCSV,



    [Parameter(Mandatory=$true)]
    $ironMoutainTapeInfoCSV
)

#Import the CSV files, one from commvault and one from iron mountain portal. 
$cvmTapeInfoList = Import-Csv -Path $commvaultTapeInfCSV | Select-Object "Bar Code", location
$ironTapeInfoList = Import-Csv -Path $ironMoutainTapeInfoCSV | Select-Object "Media #", Status

#Creating an array for results
$outfile = ".\results.csv"
$tape = @()

#Check location of the tapes
$ironTapeInfoList | ForEach-Object {
    if (($cvmTapeInfoList."Bar Code" -contains $_."Media #") -and ($_.Status -eq  "At Iron Mountain")) {
        #Tape in correct location
     }
    elseif (($cvmTapeInfoList."Bar Code" -contains $_."Media #" ) -and ($_.Status -ne  "At Iron Mountain" ))
    {
        #Tape location mismatch
        $tape += $_."Media #"

    }
    else 
    {
        #Tape number not found in commvault report
    }
}

#Exporting the results
$tape | Out-File $outfile