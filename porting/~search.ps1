param(
    [switch] $FunctionOnly
    [switch] $Verbose
)

function global:Find-InSource {
    param(
        [string] $Pattern,
        [string] $Repository = ".\luci",
        [string[]] $Extensions = @(
            ".lua",
            ".c",
            ".js",
            ".mjs"
        ),
        [switch] $Verbose
    )

    $gitRoot = (git rev-parse --show-toplevel 2>$null)

    $output = [ordered]@{}

    If( $Verbose ) {
        Write-Host "Aggregating source files with extensions: $($Extensions -join ', ')" -ForegroundColor Yellow
        Write-Host "- Wait a moment, this may take a bit..." -ForegroundColor DarkGray
    }

    $files = Get-ChildItem -Path $Repository -File -Recurse | Where-Object {
        $_.Extension -in $Extensions
    }

    if ($files.Count -eq 0) {
        Write-Host "No files found with the specified extensions." -ForegroundColor Yellow
        return $output
    } elseif ( $Verbose ) {
        Write-Host "Searching in $($files.Count) files with extensions: $($Extensions -join ', ')" -ForegroundColor Black -BackgroundColor DarkYellow
    }

    $files | ForEach-Object {
        $filename = $_.FullName.Replace($gitRoot, '').TrimStart('\/')
        $fileContent = Get-Content $_.FullName

        $hits = for ($ln = 0; $ln -lt $fileContent.Count; $ln++) {
            $line = $fileContent | Select-Object -Index $ln
            if ($line -match $pattern) {
                @{
                    Line = $ln + 1
                    Content = $line.Trim()
                }
            }
        }

        if ($hits.Count -gt 0) {
            $output."$filename" = [ordered]@{}

            $hits | ForEach-Object {
                $output."$filename"."$($_.Line)" = $_.Content
            }

            If( $Verbose ){
                Write-Host "$filename`:" -ForegroundColor Cyan

                $hits | ForEach-Object {
                    Write-Host "L$($_.Line)" -NoNewline -ForegroundColor Gray
                    Write-Host ": $($_.Content)"
                }
                Write-Host ""
            }
        }
    }

    If( $Verbose ) {
        $total_files = $output.Keys.Count
        $total_hits = ($output.Values | ForEach-Object { $_.Count }) -as [int[]] | Measure-Object -Sum | Select-Object -ExpandProperty Sum

        Write-Host "Found $total_hits hits in $total_files files." -ForegroundColor Green
    }

    return $output
}

If( $FunctionOnly ) {
    return
}

& { # Search for `uci` in the source code
    $params = @{
        Pattern = '(?<!l)uci'
        Repository = ".\luci"
        Extensions = @(
            ".lua",
            ".c",
            ".js",
            ".mjs"
        )
    }
    If( $Verbose ) { $params.Verbose = $true }
    $hits = Find-InSource @params
    $hits | ConvertTo-Json -Depth 5 | Out-File "porting/searches/uci/hits.json" -Encoding UTF8
    $hits.Keys | Out-File "porting/searches/uci/hits.txt" -Encoding UTF8
}