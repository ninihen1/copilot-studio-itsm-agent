#Requires -Version 5.1

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.md'   = 'text/markdown; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
}

$listener = $null
$prefix = $null
foreach ($candidatePort in $Port..($Port + 20)) {
    $candidatePrefix = "http://localhost:$candidatePort/"
    $candidateListener = [System.Net.HttpListener]::new()
    $candidateListener.Prefixes.Add($candidatePrefix)

    try {
        $candidateListener.Start()
        $listener = $candidateListener
        $prefix = $candidatePrefix
        break
    }
    catch {
        $candidateListener.Close()
        if ($candidatePort -eq ($Port + 20)) {
            throw
        }
    }
}

Write-Host "Serving $root"
Write-Host "Open ${prefix}PROJECT_KANBAN.html"
Write-Host 'Press Ctrl+C to stop.'

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $requestPath = [System.Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($requestPath)) {
            $requestPath = 'PROJECT_KANBAN.html'
        }

        $candidate = Join-Path $root ($requestPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $resolved = $null
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
        }

        if (-not $resolved -or -not $resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $context.Response.StatusCode = 404
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.Close()
            continue
        }

        $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
        $context.Response.ContentType = $contentTypes[$extension]
        if (-not $context.Response.ContentType) {
            $context.Response.ContentType = 'application/octet-stream'
        }

        $bytes = [System.IO.File]::ReadAllBytes($resolved)
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
