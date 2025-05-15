# Push changes to the remote repository with force-with-lease
git push --force-with-lease

# Prompt the user for the Jira ticket number
$jiraTicket = gum input --placeholder "Enter Jira Ticket Number:"

# Prompt the user for a description/comment to append
$description = gum input --placeholder "Enter any comment to append to the description (optional):"

# Retrieve a list of optional reviewers using Azure DevOps CLI and filter them interactively with fzf
$reviewers = az devops user list | jq -r '.members[].user.directoryAlias' | fzf -m
if (-not $reviewers) {
    Write-Host "Error: No reviewers selected. Exiting..." -ForegroundColor Red
    exit 1
}

# Get the latest Git commit message
$latestCommitMessage = git log -1 --pretty=%B
if (-not $latestCommitMessage) {
    Write-Host "Error: Unable to retrieve the latest Git commit message. Exiting..." -ForegroundColor Red
    exit 1
}

$commitMessage = "$jiraTicket - $latestCommitMessage"

# Get all commits unique to this branch (not in dev), one per line: <hash> <message>
$branchName = git branch --show-current
$commitList = git log --no-merges --pretty=format:"%s" origin/dev..$branchName

$prDescription = ""

# Format the commits as a bullet list
if ($commitList) {
    $commitBullets = $commitList -split "`n" | ForEach-Object { "* $_" }
    $commitBulletsText = $commitBullets -join "`n"
    $prDescription += "`n`n### Commits in this branch:`n$commitBulletsText"
}

# Construct the pull request description (combining Jira ticket and user-provided description)
$prDescription += "$jiraTicket"
if ($description) {
    $prDescription += " - $description"
}


# Create a pull request using Azure DevOps CLI with auto-complete, squash commits, and optional reviewers
az repos pr create `
    --auto-complete true `
    --optional-reviewers $reviewers `
    --squash true `
    --merge-commit-message "$commitMessage" `
    --description "$prDescription" `
    --title "$commitMessage" `
    --open `
    --delete-source-branch true

# Confirm success or handle errors during PR creation
if ($LASTEXITCODE -eq 0) {
    Write-Host "Pull request created successfully!" -ForegroundColor Green
} else {
    Write-Host "Error: Failed to create the pull request." -ForegroundColor Red
}

