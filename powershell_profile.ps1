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

function gfd
{
    git fetch --prune --depth=1
}

# Works standalone as "gr" no args or with files "gr HEAD~1"
function gr
{
    git reset --hard $args
}

# Works standalone as "gdh" no args or with files "gdh file1.txt"
function gdh
{
    git diff HEAD -- $args
}

function gro
{
    git reset --hard origin/$args
}

function grc
{
    git rebase --continue
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
    git add -- $args
}

function gaa
{
    git add -A
}

function br
{
    git remote show origin
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

function gpsh
{
    git push origin HEAD:refs/for/main
}

function cmt
{
    git commit -m $args
}

function amd
{
    git commit --amend --no-edit
}

function sqsh
{
    git reset --soft $args[0]
    git commit -m $args[1]
}

# Works standalone as "gsu" no args or with args "gsu --init"
function gsu
{
    git submodule update $args
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

function Open-Bin
{
    Start-Process $env:_NTTREE
}

function karto
{
    Push-Location $env:USERPROFILE\documents\karto-unreal
}

function Unity
{
    $vals = (Get-CimInstance Win32_Process -Filter "name = 'Unity.exe'" | Select-Object ProcessId, CommandLine)
    foreach ($val in $vals)
    {
        if ($val.CommandLine -match '.* -projectpath\s([^\s]*)\s.*')
        {
            Write-Host "$($val.ProcessId): $($matches[1])"
        }
    }
}

function bpdiff
{
    karto
    .\bin\windows\bazel run //repoctl -- bpdiff $args[0] $args[1]
    Pop-Location
}