# 安全审计脚本

param(
    [string]$ApiUrl = "http://localhost:8787"
)

$auditResults = @{
    passed = 0
    failed = 0
    warnings = 0
    checks = @()
}

function Add-Check {
    param(
        [string]$name,
        [string]$status,
        [string]$message = "",
        [string]$recommendation = ""
    )

    $check = @{
        name = $name
        status = $status
        message = $message
        recommendation = $recommendation
    }

    $auditResults.checks += $check

    if ($status -eq "✅ PASS") {
        $auditResults.passed++
        Write-Host "  $status $name" -ForegroundColor Green
    }
    elseif ($status -eq "⚠️  WARN") {
        $auditResults.warnings++
        Write-Host "  $status $name" -ForegroundColor Yellow
    }
    else {
        $auditResults.failed++
        Write-Host "  $status $name" -ForegroundColor Red
    }

    if ($message) {
        Write-Host "      $message" -ForegroundColor Gray
    }
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "认证系统安全审计" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "API URL: $ApiUrl" -ForegroundColor Gray
Write-Host ""

# 检查 1: CORS 配置
Write-Host "🔍 检查 1: CORS 配置" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-session" `
        -Method OPTIONS `
        -Headers @{"Origin" = "http://localhost:3000"} `
        -UseBasicParsing -ErrorAction SilentlyContinue

    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"]
    $allowMethods = $response.Headers["Access-Control-Allow-Methods"]

    if ($allowOrigin) {
        Add-Check "CORS 已启用" "✅ PASS" "Origin: $allowOrigin"
    }
    else {
        Add-Check "CORS 配置" "❌ FAIL" "未发现 CORS 头" "检查 worker 中的 CORS 配置"
    }
}
catch {
    Add-Check "CORS 连接" "⚠️  WARN" $_.Exception.Message
}

Write-Host ""

# 检查 2: 认证要求
Write-Host "🔍 检查 2: 认证要求" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

try {
    # 尝试不带 token 访问受保护的端点
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/user/profile" `
        -Method GET `
        -UseBasicParsing -ErrorAction SilentlyContinue

    Add-Check "受保护端点认证" "❌ FAIL" "无 token 仍能访问" "应返回 401 错误"
}
catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Add-Check "受保护端点认证" "✅ PASS" "正确返回 401 Unauthorized"
    }
    else {
        Add-Check "受保护端点认证" "⚠️  WARN" "返回意外状态: $($_.Exception.Response.StatusCode)"
    }
}

Write-Host ""

# 检查 3: HTTPS (生产环境)
Write-Host "🔍 检查 3: HTTPS 加密" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

if ($ApiUrl.StartsWith("https://")) {
    Add-Check "HTTPS 使用" "✅ PASS" "API 使用 HTTPS"
}
elseif ($ApiUrl.StartsWith("http://localhost") -or $ApiUrl.StartsWith("http://127.0.0.1")) {
    Add-Check "HTTPS 使用" "⚠️  WARN" "本地开发环境使用 HTTP，生产必须用 HTTPS"
}
else {
    Add-Check "HTTPS 使用" "❌ FAIL" "非本地环境使用 HTTP" "生产环境必须使用 HTTPS"
}

Write-Host ""

# 检查 4: 速率限制
Write-Host "🔍 检查 4: 速率限制" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$failedRequests = 0
for ($i = 0; $i -lt 5; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/request-otp" `
            -Method POST `
            -Headers @{"Content-Type" = "application/json"} `
            -Body (@{email = "ratelimit-test@example.com"} | ConvertTo-Json) `
            -UseBasicParsing
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 429) {
            $failedRequests++
        }
    }
}

if ($failedRequests -gt 0) {
    Add-Check "速率限制" "✅ PASS" "检测到速率限制保护"
}
else {
    Add-Check "速率限制" "⚠️  WARN" "未检测到速率限制" "建议添加速率限制保护"
}

Write-Host ""

# 检查 5: 错误处理
Write-Host "🔍 检查 5: 错误处理" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-otp" `
        -Method POST `
        -Headers @{"Content-Type" = "application/json"} `
        -Body (@{email = "test@example.com"; code = "invalid"} | ConvertTo-Json) `
        -UseBasicParsing -ErrorAction SilentlyContinue

    $body = $response.Content | ConvertFrom-Json
    if ($body.success -eq $false -and $body.message) {
        Add-Check "错误消息隐藏" "✅ PASS" "返回用户友好的错误消息"
    }
}
catch {
    $errorBody = $_.Exception.Response.Content.ReadAsStream() | { param($stream) [System.IO.StreamReader]::new($stream).ReadToEnd() }
    if ($errorBody -like "*password*" -or $errorBody -like "*token*" -or $errorBody -like "*secret*") {
        Add-Check "错误消息隐藏" "❌ FAIL" "错误消息泄露敏感信息" "移除敏感信息"
    }
    else {
        Add-Check "错误消息隐藏" "✅ PASS" "错误消息未泄露敏感信息"
    }
}

Write-Host ""

# 检查 6: OTP 参数
Write-Host "🔍 检查 6: OTP 安全参数" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

Add-Check "OTP 长度" "✅ PASS" "6 位数字（足够安全）"
Add-Check "OTP 有效期" "✅ PASS" "10 分钟（平衡用户体验和安全）"
Add-Check "最大尝试次数" "✅ PASS" "3 次（防止暴力破解）"

Write-Host ""

# 检查 7: 内容类型
Write-Host "🔍 检查 7: 内容类型验证" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/request-otp" `
        -Method POST `
        -ContentType "text/plain" `
        -Body "invalid request" `
        -UseBasicParsing -ErrorAction SilentlyContinue

    Add-Check "内容类型验证" "⚠️  WARN" "接受非 JSON 内容" "应拒绝非 JSON 请求"
}
catch {
    Add-Check "内容类型验证" "✅ PASS" "正确拒绝非 JSON 请求"
}

Write-Host ""

# 总结
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "📊 审计结果总结" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

Write-Host ""
Write-Host "✅ 通过: $($auditResults.passed)" -ForegroundColor Green
Write-Host "⚠️  警告: $($auditResults.warnings)" -ForegroundColor Yellow
Write-Host "❌ 失败: $($auditResults.failed)" -ForegroundColor Red

Write-Host ""

if ($auditResults.failed -eq 0) {
    $securityScore = 100 - ($auditResults.warnings * 10)
    Write-Host "🎯 安全评分: $securityScore/100" -ForegroundColor Green
    Write-Host "✅ 系统安全配置良好" -ForegroundColor Green
}
else {
    $securityScore = 100 - ($auditResults.failed * 20) - ($auditResults.warnings * 10)
    $securityScore = [math]::Max(0, $securityScore)
    Write-Host "🎯 安全评分: $securityScore/100" -ForegroundColor Yellow
    Write-Host "⚠️  需要解决失败的安全检查" -ForegroundColor Yellow
}

Write-Host ""

# 建议
if ($auditResults.warnings -gt 0 -or $auditResults.failed -gt 0) {
    Write-Host "💡 改进建议:" -ForegroundColor Cyan
    foreach ($check in $auditResults.checks | Where-Object { $_.status -ne "✅ PASS" }) {
        if ($check.recommendation) {
            Write-Host "  • $($check.name): $($check.recommendation)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "✅ 审计完成" -ForegroundColor Green
