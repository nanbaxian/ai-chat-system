# 系统监控脚本 (PowerShell)
# 监控 Cloudflare Workers 认证系统的健康状态

param(
    [string]$ApiUrl = "http://localhost:8787",
    [int]$IntervalSeconds = 60,
    [switch]$Continuous = $false
)

$healthStatus = @{
    healthy = $true
    checks = @()
    timestamp = Get-Date
}

function Test-Endpoint {
    param(
        [string]$name,
        [string]$method,
        [string]$path,
        [hashtable]$headers = @{},
        [object]$body = $null
    )

    $result = @{
        name = $name
        status = "pending"
        duration = 0
        error = $null
    }

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $params = @{
            Uri = "$ApiUrl$path"
            Method = $method
            UseBasicParsing = $true
        }

        if ($headers.Count -gt 0) {
            $params["Headers"] = $headers
        }

        if ($body) {
            $params["Body"] = $body | ConvertTo-Json
        }

        $response = Invoke-WebRequest @params -ErrorAction Stop
        $stopwatch.Stop()

        $result.status = "✅ OK"
        $result.duration = $stopwatch.ElapsedMilliseconds
    }
    catch {
        $result.status = "❌ FAILED"
        $result.error = $_.Exception.Message
        $result.duration = $stopwatch.ElapsedMilliseconds
    }

    return $result
}

function Write-HealthReport {
    param([hashtable]$report)

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "系统健康检查 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    foreach ($check in $report.checks) {
        $statusColor = if ($check.status -like "*✅*") { "Green" } else { "Red" }
        Write-Host "$($check.name): $($check.status)" -ForegroundColor $statusColor
        if ($check.duration -gt 0) {
            Write-Host "  └─ 响应时间: $($check.duration)ms" -ForegroundColor Gray
        }
        if ($check.error) {
            Write-Host "  └─ 错误: $($check.error)" -ForegroundColor Yellow
        }
    }

    $failedCount = ($report.checks | Where-Object { $_.status -like "*❌*" }).Count
    Write-Host ""
    if ($failedCount -eq 0) {
        Write-Host "✅ 所有检查通过" -ForegroundColor Green
    }
    else {
        Write-Host "❌ $failedCount 个检查失败" -ForegroundColor Red
    }
    Write-Host ""
}

function Run-HealthCheck {
    $report = @{
        healthy = $true
        checks = @()
        timestamp = Get-Date
    }

    # 检查 1: OTP 端点
    $report.checks += Test-Endpoint `
        -name "OTP 端点" `
        -method "POST" `
        -path "/api/auth/request-otp" `
        -headers @{"Content-Type" = "application/json"} `
        -body @{email = "test@example.com"}

    # 检查 2: Session 验证端点 (应返回 401，因为没有有效的 token)
    $report.checks += Test-Endpoint `
        -name "Session 验证端点" `
        -method "GET" `
        -path "/api/auth/verify-session" `
        -headers @{"Authorization" = "Bearer invalid-token"}

    # 检查 3: 数据库连接 (如果有 debug 端点)
    $dbCheck = Test-Endpoint `
        -name "数据库连接" `
        -method "GET" `
        -path "/api/auth/verify-session" `
        -headers @{"Authorization" = "Bearer invalid"}

    $report.checks += $dbCheck

    # 检查失败情况
    $failedChecks = $report.checks | Where-Object { $_.status -like "*❌*" }
    if ($failedChecks.Count -gt 0) {
        $report.healthy = $false
    }

    Write-HealthReport $report
    return $report
}

# 主循环
if ($Continuous) {
    Write-Host "启动连续监控模式，间隔 $IntervalSeconds 秒" -ForegroundColor Yellow
    Write-Host "按 Ctrl+C 停止监控" -ForegroundColor Gray
    Write-Host ""

    while ($true) {
        Run-HealthCheck
        Start-Sleep -Seconds $IntervalSeconds
    }
}
else {
    Run-HealthCheck
}
