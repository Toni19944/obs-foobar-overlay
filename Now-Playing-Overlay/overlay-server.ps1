# overlay-server.ps1
# Serves the overlay HTML and proxies Beefweb API requests.
# Keep this window open while streaming.

$port    = 8081
$beefweb = "http://localhost:8880"
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "Overlay server running at http://localhost:$port/" -ForegroundColor Green
Write-Host "Close this window to stop." -ForegroundColor DarkGray
Write-Host ""

while ($listener.IsListening) {
    $ctx   = $listener.GetContext()
    $req   = $ctx.Request
    $res   = $ctx.Response
    $path  = $req.Url.LocalPath.TrimStart('/')
    $query = $req.Url.Query

    $res.Headers.Add("Access-Control-Allow-Origin", "*")

    try {
        if ($path -like "api*") {
            # Proxy to Beefweb
            $wc    = New-Object System.Net.WebClient
            $bytes = $wc.DownloadData("$beefweb/$path$query")
            $res.ContentType = "application/json"
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)

        } elseif ($path -eq "bg-list") {
            # Scan bg/ folder and return JSON array of filenames
            $bgDir = Join-Path $root "bg"
            $files = @()
            if (Test-Path $bgDir) {
                $exts = "*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif"
                foreach ($ext in $exts) {
                    $files += Get-ChildItem -Path $bgDir -Filter $ext |
                              ForEach-Object { "bg/$($_.Name)" }
                }
            }
            $json  = "[" + (($files | ForEach-Object { "`"$_`"" }) -join ",") + "]"
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json"
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)

        } else {
            # Serve static file
            if ($path -eq "") { $path = "nowplaying-overlay.html" }
            $file = Join-Path $root $path

            if (Test-Path $file) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $ext   = [IO.Path]::GetExtension($file).ToLower()
                $res.ContentType = switch ($ext) {
                    ".html" { "text/html" }
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".webp" { "image/webp" }
                    ".avif" { "image/avif" }
                    default { "application/octet-stream" }
                }
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
            }
        }
    } catch {
        $res.StatusCode = 500
        Write-Host "Error: $_" -ForegroundColor Red
    }

    $res.Close()
}
