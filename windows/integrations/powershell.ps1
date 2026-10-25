# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
    return
}

$sporeHintExecutable = Join-Path (Split-Path -Parent $PSScriptRoot) 'store\spore\spore.exe'

Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    $line = $null
    $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $match = [regex]::Match($line, '^\s*spore(?=\s|$)')
    if (-not $match.Success) {
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext()
        return
    }

    $bodyOffset = $match.Length
    if ($line.Length -gt $bodyOffset -and [char]::IsWhiteSpace($line[$bodyOffset])) {
        $bodyOffset++
    }
    $body = $line.Substring($bodyOffset)
    $hintCursor = [Math]::Max(0, $cursor - $bodyOffset)
    $escapedBody = $body.Replace('\', '\\').Replace('"', '\"')
    $hint = "hint body=`"$escapedBody`" cursor=$hintCursor"
    if ($hintCursor -eq $body.Length) {
        $hint += ' eol'
    }

    & $sporeHintExecutable $hint
}
