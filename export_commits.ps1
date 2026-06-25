# This script exports all git commit messages to commit_messages.txt
$outputFile = "commit_messages.txt"

Write-Host "Exporting git commit history to $outputFile..." -ForegroundColor Cyan

# Output commit log with format: "Hash - Date - Message"
git log --pretty=format:"%h - %cd - %s" --date=short | Out-File -Encoding utf8 $outputFile

if ($?) {
    Write-Host "Successfully exported commit history." -ForegroundColor Green
}
else {
    Write-Host "Failed to export commit history." -ForegroundColor Red
}
