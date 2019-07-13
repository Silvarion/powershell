function prompt {
    # Grab last exit code
    $PrevExitCode = $?
    # Set the ESC Character
    $ESC = [Char]27
    # Resolve if in Git Repo
    if (Get-Command "git" -ErrorAction SilentlyContinue) {
        $GitStatus = git status
        # Build Git Section
        if ($GitStatus) {
            $GitBranch = $([String]$($GitStatus | Select-String -Pattern "On branch") -split "On branch").Trim(" ")
            $PendingChanges = [String]$($GitStatus | Select-String -Pattern "Changes not staged")
            $PendingChangesNumber = $([String]$($GitStatus | Select-String -Pattern "modified|deleted|created") | Measure-Object).Count
        }
    }
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal] $identity
        # Debug or Admin

        $IsDebug = $(if (test-path variable:/PSDebugContext) { 'DBG' })
        if ($IsDebug) {
            Write-Host "[" -NoNewline
            Write-Host "DBG" -ForegroundColor 'Yellow' -NoNewline
            Write-Host "]" -NoNewline
        }
        $IsAdmin = $(if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) { "ADMIN" })
        if ($IsAdmin) {
            Write-Host "[" -NoNewline
            Write-Host "ADMIN" -ForegroundColor 'Red' -NoNewline
            Write-Host "]" -NoNewline
        }
    }
    if ($IsWindows) {
        $CurrentLocation = $($(Get-Location).ToString() -split '\\')[-1]
    } elseif ($IsLinux) {
        $CurrentLocation = $($(Get-Location).ToString() -split '/')[-1]
    }
    # Username @ Host section
    Write-Host "[" -NoNewline
    if ($IsWindows) {
        Write-Host "$env:USERNAME" -ForegroundColor Cyan -NoNewline
    } elseif ($IsLinux) {
        Write-Host "$env:USER" -ForegroundColor Cyan -NoNewline
    }
    Write-Host "@" -NoNewline
    if ($IsWindows) {
        Write-Host "$env:COMPUTERNAME" -ForegroundColor Yellow -NoNewline
    } elseif ($IsLinux) {
        Write-Host "$(hostname)" -ForegroundColor Yellow -NoNewline
    }
    Write-Host "] " -NoNewline
    # Git Status
    if ($GitStatus) {
        if ($PendingChanges) {
            $GitColor = 'Yellow'
        } else {
            $GitColor = 'Green'
        }
        Write-Host " {$GitBranch | " -NoNewline
        Write-Host "+-$PendingChangesNumber" -ForegroundColor $GitColor -NoNewline
        Write-Host " }" -NoNewline
    }
    # Last Command exit status
    if ($PrevExitCode) {
        Write-Host "(" -NoNewline
        Write-Host "$([Char]8730)" -ForegroundColor Green -OutVariable $LastCommandExit -NoNewline
        Write-Host ")" -NoNewline
    } else {
        Write-Host "(" -NoNewline
        Write-Host "$([Char]0215)" -ForegroundColor Red -OutVariable $LastCommandExit -NoNewline
        Write-Host ")" -NoNewline
    }
    # Current Location
    Write-Host "`n$CurrentLocation -" -NoNewline
    Write-Host $($(if ($nestedpromptlevel -ge 1) { '>>' }) + '>') -NoNewline
    return " "
}
