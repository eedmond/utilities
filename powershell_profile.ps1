$env:PSModulePath += ";D:\analog.devtools.razzle.powershell"

function gs
{
    git status
}

function gss
{
    git status --ignore-submodules=all
}

function gf
{
    git fetch --prune
}

function gr
{
    git reset --hard $args
}

function gdh
{
    git diff HEAD -- $args
}

function gro
{
    git reset --hard origin/$args
}

function gco
{
    git checkout user/ericed/$args
}

function nb
{
    git checkout -b user/ericed/$args
}

function ga
{
    git add -A
}

function br
{
    git remote show origin
}

function rb
{
    git rebase --onto origin/$args[0] HEAD~$args[1]
}

function lg
{
    git log --oneline --graph -$args
}

function psh
{
    git push origin user/ericed/$args
}

function pshf
{
    git push -f origin user/ericed/$args
}

function cmt
{
    git commit -m $args
}

function sqsh
{
    git reset --soft $args[0]
    git commit -m $args[1]
}

function web
{
    Start-Process (git config --get remote.origin.url)
}

function reset-lfs
{
    git rm --cached -r .
    git reset --hard
    git rm .gitattributes
    git reset .
    git checkout .
}

function Patch-SettingsEnvironment
{
    sfpcopyd $env:_NTTREE\analog\bin\settings\settingsenvironment.dll c:\windows\system32\settingsenvironment.dll
}

function Patch-HoloSettingsHandlersResources
{
    sfpcopyd $env:_NTTREE\loc\src\bin\SystemSettings_Holographic_HandlerResources\Windows.UI.SettingsHandlers-nt\resources.pri c:\windows\systemresources\windows.ui.settingshandlers-nt\pris\Windows.UI.SettingsHandlers-nt.en-US.pri
    sfpcopyd $env:_NTTREE\SystemSettings_Holographic_HandlerResources\Windows.UI.SettingsHandlers-nt\neutral.pri c:\windows\systemresources\windows.ui.settingshandlers-nt\Windows.UI.SettingsHandlers-nt.pri
}

function Patch-HoloSettingsResources
{
    sfpcopyd $env:_NTTREE\loc\src\bin\holographicsystemsettings\resources.pri c:\windows\SystemApps\HolographicSystemSettings_cw5n1h2txyewy\pris\resources.en-US.pri
    sfpcopyd $env:_NTTREE\HolographicSystemSettings\neutral.pri c:\windows\SystemApps\HolographicSystemSettings_cw5n1h2txyewy\resources.pri
}

function Open-Bin
{
    start $env:_NTTREE
}

function Unity
{
    $vals = (Get-CimInstance Win32_Process -Filter "name = 'Unity.exe'" | select ProcessId, CommandLine)
    foreach ($val in $vals)
    {
        if ($val.CommandLine -match '.* -projectpath\s([^\s]*)\s.*')
        {
            Write-Host "$($val.ProcessId): $($matches[1])"
        }
    }
}