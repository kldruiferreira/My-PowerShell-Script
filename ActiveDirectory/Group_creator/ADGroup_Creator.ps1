#Importing CSV file for data
$value = Import-Csv -Path .\Groups.csv

foreach($data in $value)
{
     New-ADGroup -Name $data.GroupName -SamAccountName $data.GroupName -GroupCategory Security -GroupScope $data.Type -DisplayName $data.GroupName -Path $data.Location -Description $data.Description
     Write-Output "Create group " $data.GroupName
 }