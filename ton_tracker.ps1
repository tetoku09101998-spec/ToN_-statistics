try {
    $uri = New-Object System.Uri("ws://localhost:11398/")
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $conn = $ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None)
    $conn.Wait()
} catch {
    Write-Host "エラー：ToN Save Managerに接続できなかったわ。" -ForegroundColor Red
    Write-Host "VRChatとSave Managerがちゃんと起動しているか確認しなさい。" -ForegroundColor Red
    Read-Host "Enterキーを押して終了して"
    exit
}

Write-Host "ToN 統計トラッカー＆連携ツール起動。" -ForegroundColor Cyan
Write-Host "Save Managerに接続完了。テラー情報の監視と統計ログの記録を開始するわ。"

$csvPath = ".\ton_stats.csv"
$watchFile = ".\ton_terror_name.txt"

if (-not (Test-Path $csvPath)) {
    "Timestamp,Map,RoundType,Killers,Result" | Out-File $csvPath -Encoding utf8
}

$buffer = [System.Byte[]]::new(8192)
$segment = [System.ArraySegment[System.Byte]]::new($buffer)

$currentMap = "Unknown"
$currentRoundType = "Unknown"
$currentKillers = "None"

while ($ws.State -eq 'Open') {
    try {
        $result = $ws.ReceiveAsync($segment, [System.Threading.CancellationToken]::None).Result
        
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            Write-Host "接続が閉じられたわ。" -ForegroundColor Yellow
            break
        }

        $jsonString = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        $data = $jsonString | ConvertFrom-Json
        
        $type = $data.Type

        # --- TRACKERイベント（ラウンドの進行や勝敗） ---
        if ($type -eq "TRACKER") {
            $event = $data.event
            $args = $data.args

            if ($event -eq "round_start") {
                $currentMap = "Unknown"
                $currentRoundType = "Unknown"
                $currentKillers = "None"
                Write-Host "`n=== 新しいラウンドが開始されたわ ===" -ForegroundColor Yellow
            }
            elseif ($event -eq "round_map") {
                $currentMap = $args[0]
                if ($args.Count -gt 2) {
                    $currentRoundType = $args[2]
                }
                Write-Host "マップ: $currentMap (種類: $currentRoundType)"
            }
            # ※ round_killers はIDしか入ってないので無視するわ
            
            elseif ($event -match "round_won|round_lost") {
                $matchResult = if ($event -eq "round_won") { "Win" } else { "Lost" }
                $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                
                $newLine = "$timestamp,$currentMap,$currentRoundType,$currentKillers,$matchResult"
                $newLine | Out-File $csvPath -Append -Encoding utf8
                Write-Host "【ログ記録】 ラウンド終了 ($matchResult)。CSVにデータを追記したわ。" -ForegroundColor Green
                
                "" | Out-File $watchFile -Encoding utf8
            }
        }
        # --- TERRORSイベント（正確なテラー名を取得！） ---
        elseif ($type -eq "TERRORS") {
            # Names配列が空（null）じゃない、つまり本当に出現した時だけ処理する
            if ($null -ne $data.Names) {
                $killersArray = $data.Names | Where-Object { $_ -ne $null }
                if ($killersArray.Count -gt 0) {
                    $currentKillers = $killersArray -join "/"
                    
                    # 英語の正確な名前をビュアーに転送
                    ($killersArray -join ",") | Out-File $watchFile -Encoding utf8
                    
                    Write-Host ">>> 警告：テラー出現！ ビュアーにデータを転送したわ <<<" -ForegroundColor Red
                    foreach ($k in $killersArray) {
                        Write-Host "  - $k" -ForegroundColor Red
                    }
                }
            }
        }
    } catch {
        if ($ws.State -ne 'Open') { break }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "通信が切断されたわ。" -ForegroundColor Yellow
Read-Host "Enterキーを押して終了して"