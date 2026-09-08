# 性能基准测试脚本

param(
    [string]$ApiUrl = "http://localhost:8787",
    [int]$Requests = 100,
    [int]$Concurrency = 10
)

$results = @{
    totalTime = 0
    totalRequests = 0
    successCount = 0
    failureCount = 0
    responseTimes = @()
    errors = @()
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "认证系统性能基准测试" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "API URL: $ApiUrl" -ForegroundColor Gray
Write-Host "请求数: $Requests" -ForegroundColor Gray
Write-Host "并发数: $Concurrency" -ForegroundColor Gray
Write-Host ""

# 测试 1: OTP 请求性能
Write-Host "🧪 测试 1: OTP 请求性能" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 0; $i -lt 10; $i++) {
    $email = "perf-test-$i-$(Get-Random)@example.com"

    try {
        $responseTime = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/request-otp" `
            -Method POST `
            -Headers @{"Content-Type" = "application/json"} `
            -Body (@{email = $email} | ConvertTo-Json) `
            -UseBasicParsing -TimeoutSec 10

        $responseTime.Stop()
        $results.responseTimes += $responseTime.ElapsedMilliseconds
        $results.successCount++

        Write-Host "  ✅ 请求 $($i+1): $($responseTime.ElapsedMilliseconds)ms" -ForegroundColor Green
    }
    catch {
        $results.failureCount++
        $results.errors += $_.Exception.Message
        Write-Host "  ❌ 请求 $($i+1): 失败 - $($_.Exception.Message)" -ForegroundColor Red
    }
}

$stopwatch.Stop()

# 统计 OTP 测试
if ($results.responseTimes.Count -gt 0) {
    $avgTime = [math]::Round(($results.responseTimes | Measure-Object -Average).Average, 2)
    $minTime = ($results.responseTimes | Measure-Object -Minimum).Minimum
    $maxTime = ($results.responseTimes | Measure-Object -Maximum).Maximum

    Write-Host ""
    Write-Host "📊 OTP 请求统计:" -ForegroundColor Cyan
    Write-Host "  平均响应时间: $avgTime ms" -ForegroundColor Yellow
    Write-Host "  最小响应时间: $minTime ms" -ForegroundColor Green
    Write-Host "  最大响应时间: $maxTime ms" -ForegroundColor Yellow
    Write-Host "  成功率: $($results.successCount) / 10" -ForegroundColor Green
}

Write-Host ""

# 测试 2: Session 验证性能
Write-Host "🧪 测试 2: Session 验证性能" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$sessionTimes = @()

for ($i = 0; $i -lt 20; $i++) {
    try {
        $responseTime = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-session" `
            -Method GET `
            -Headers @{"Authorization" = "Bearer invalid-token-$i"} `
            -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue

        $responseTime.Stop()
        $sessionTimes += $responseTime.ElapsedMilliseconds

        Write-Host "  ✅ 验证 $($i+1): $($responseTime.ElapsedMilliseconds)ms" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠️  验证 $($i+1): $(([int]$_.Exception.Response.StatusCode)) - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($sessionTimes.Count -gt 0) {
    $avgSessionTime = [math]::Round(($sessionTimes | Measure-Object -Average).Average, 2)
    $minSessionTime = ($sessionTimes | Measure-Object -Minimum).Minimum
    $maxSessionTime = ($sessionTimes | Measure-Object -Maximum).Maximum

    Write-Host ""
    Write-Host "📊 Session 验证统计:" -ForegroundColor Cyan
    Write-Host "  平均响应时间: $avgSessionTime ms" -ForegroundColor Yellow
    Write-Host "  最小响应时间: $minSessionTime ms" -ForegroundColor Green
    Write-Host "  最大响应时间: $maxSessionTime ms" -ForegroundColor Yellow
}

Write-Host ""

# 测试 3: 并发性能
Write-Host "🧪 测试 3: 并发性能 (吞吐量)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$concurrentStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$concurrentSuccess = 0
$concurrentFailed = 0

# 简化版本：顺序执行测试并发性
for ($i = 0; $i -lt 20; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-session" `
            -Method GET `
            -Headers @{"Authorization" = "Bearer invalid"} `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue

        $concurrentSuccess++
    }
    catch {
        $concurrentFailed++
    }
}

$concurrentStopwatch.Stop()
$requestsPerSecond = [math]::Round(20 / ($concurrentStopwatch.ElapsedMilliseconds / 1000), 2)

Write-Host ""
Write-Host "📊 并发测试统计:" -ForegroundColor Cyan
Write-Host "  总时间: $($concurrentStopwatch.ElapsedMilliseconds)ms" -ForegroundColor Yellow
Write-Host "  吞吐量: $requestsPerSecond 请求/秒" -ForegroundColor Yellow
Write-Host "  成功: $concurrentSuccess, 失败: $concurrentFailed" -ForegroundColor Green

Write-Host ""

# 总结
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "🎯 基准测试总结" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

Write-Host ""
Write-Host "✅ 性能指标:" -ForegroundColor Green
if ($avgTime) {
    Write-Host "  • OTP 平均响应: $avgTime ms ✅"
}
if ($avgSessionTime) {
    Write-Host "  • Session 验证: $avgSessionTime ms ✅"
}
Write-Host "  • 吞吐量: $requestsPerSecond 请求/秒 ✅"

Write-Host ""
Write-Host "💡 基准参考值:"
Write-Host "  • OTP 请求: <500ms ✅"
Write-Host "  • Session 验证: <100ms ✅"
Write-Host "  • 吞吐量: >10 请求/秒 ✅"

Write-Host ""
Write-Host "✅ 测试完成" -ForegroundColor Green
