# Found at http://zduck.com/2012/powershell-batch-files-exit-codes/
Function Exec
{
    [CmdletBinding()]
    param (
        [Parameter(Position=0, Mandatory=1)]
        [scriptblock]$Command,
        [Parameter(Position=1, Mandatory=0)]
        [string]$ErrorMessage = "Execution of command failed.`n$Command"
    )
    $ErrorActionPreference = "Continue"
    & $Command 2>&1 | %{ "$_" }
    if ($LastExitCode -ne 0) {
        throw "Exec: $ErrorMessage`nExit code: $LastExitCode"
    }
}

Function Progress
{
    [CmdletBinding()]
    param (
        [Parameter(Position=0, Mandatory=0)]
        [string]$Message = ""
    )

    $ProgressMessage = '== ' + (Get-Date) + ': ' + $Message

    Write-Host $ProgressMessage -ForegroundColor Magenta
}

Function DownloadAndUnpack {
    [CmdletBinding()]
    Param()

    # Force-rebuild flag
    Exec { touch DELETE_ME_TO_FORCE_REBUILD }

    Progress "Checking status."
    $StatusOutput = (git status DELETE_ME_TO_FORCE_REBUILD --porcelain) | Out-String

    If ($StatusOutput.Length -ne 0) {
        Write-Host "Forced rebuild, skipping download." -ForegroundColor Yellow
        Return
    }

    $branch = $env:APPVEYOR_REPO_BRANCH
    Progress ("Branch name: " + $branch)
    $version = $branch -replace "-.*$",""
    Progress ("Version: " + $version)

    If ($version -eq "master") {
        Progress "Determining Rtools version"
        $rtoolsver = $(Invoke-WebRequest http://cran.r-project.org/bin/windows/Rtools/VERSION.txt).Content.Split(' ')[2].Split('.')[0..1] -Join ''
    }
    Else {
        $rtoolsver = $version
    }

    $rtoolsurl = "http://cran.r-project.org/bin/windows/Rtools/Rtools$rtoolsver.exe"

    Progress ("Downloading Rtools from: " + $rtoolsurl)
    Invoke-WebRequest $rtoolsurl -OutFile "DL\Rtools-current.exe"

    Progress "Preparing image"
    rm -Recurse -Force .\Image
    md .\Image

    # Rtools
    Progress "Extracting Rtools"
    .\Tools\innounp\innounp.exe -x -dImage .\DL\Rtools-current.exe > .\Rtools-current.log
    mv ".\Image\{app}" .\Image\Rtools
    rm .\Image\install_script.iss
    # Don't seem to need those to build packages -- only to build R
    rm ".\Image\{code_rhome}" -Recurse
    rm ".\Image\{code_rhome64}" -Recurse
}

Function CreateImage {
    [CmdletBinding()]
    Param()

    Progress "Adding files from image."
    Exec { git add -A Image DELETE_ME_TO_FORCE_REBUILD README.md }

    Progress "Checking status."
    $StatusOutput = (git status Image DELETE_ME_TO_FORCE_REBUILD --porcelain) | Out-String

    If ($StatusOutput.Length -ne 0) {
        Progress "Mounting VHD file."
        Exec { bash -c 'gunzip -c R-empty.vhd.gz > Rtools.vhd' }
        $ImageFullPath = Get-ChildItem "Rtools.vhd" | % { $_.FullName }
        $ImageFullPath

        $VHDPath = [string](Mount-DiskImage -ImagePath $ImageFullPath -Passthru | Get-DiskImage | Get-Disk | Get-Partition | Get-Volume).DriveLetter + ":"
        $VHDPath

        Progress "Checking disk space."
        Get-WmiObject -class win32_LogicalDisk

        Progress "Checking size of image."
        Get-ChildItem -Recurse Image | Measure-Object -property length -sum

        Progress "Copying to VHD file."
        cp -Recurse "Image\*" ($VHDPath + "\")

        Progress "Creating ISO file."
        Exec { .\Tools\cdrtools\mkisofs -o Rtools.iso -V R-portable -R -J Image }

        Progress "Compressing ISO file."
        Exec { bash -c 'gzip -c Rtools.iso > Rtools.iso.gz' }

        Progress "Creating TAR-GZ file."
        Exec { bash -c 'cd Image && tar -c * | gzip -c > ../Rtools.tar.gz' }

        Progress "Unmounting VHD file."
        Dismount-DiskImage -ImagePath $ImageFullPath

        Progress "Compressing VHD file."
        Exec { bash -c 'gzip -c Rtools.vhd > Rtools.vhd.gz' }
    }

    If (($StatusOutput.Length + $StatusOutputReadme.Length) -ne 0) {
        SetupGit

        Progress "Committing to Git."
        Exec { git commit -C HEAD }
        Exec { git commit --amend -m "Update image`n`n[ci skip]" }

        Progress "Pulling from Git."
        Exec { git fetch }
        Exec { git merge --no-edit origin/$env:APPVEYOR_REPO_BRANCH -s recursive -X ours }
        Exec { git commit --amend -m "Reconcile`n`n[ci skip]" }

        Progress "Pushing to Git."
        Exec { git push origin }
    }
}

Function SetupGit {
    [CmdletBinding()]
    Param()

    Progress "Writing deploy key."
    Exec { bash -c ("echo $env:DEPLOY_KEY | sed 's/@/\n/g;s/_/ /g' > /c/Users/$env:USERNAME/.ssh/id_rsa") }
    Exec { bash -c ("wc /c/Users/$env:USERNAME/.ssh/id_rsa") }

    Progress "Setting Git configuration."
    Exec { git --version }
    Exec { git config --global user.email "krlmlr+rportable@mailbox.org" }
    Exec { git config --global user.name "r-portable commit bot" }
    Exec { git config --global push.default matching }
    Exec { git config --global core.askpass echo } # doesn't help, but doesn't harm either
    Exec { git config -l }

    Progress "Setting Git remotes."
    Exec { git remote set-url origin git@github.com:krlmlr/r-portable.git }
    Exec { git remote -v }

    Progress "Deleting out branch."
    Exec { git branch -v }
    Exec { git branch -D $env:APPVEYOR_REPO_BRANCH }

    Progress "Checking out branch."
    Exec { git checkout -b $env:APPVEYOR_REPO_BRANCH }
    Exec { git branch -v }
    Exec { git status }
}
