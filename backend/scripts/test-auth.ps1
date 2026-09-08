# 认证系统测试脚本 (PowerShell)
# 使用: .\scripts\test-auth.ps1 -ApiUrl "http://localhost:8787"

param(
    [string]$ApiUrl = "http://localhost:8787"
)

$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$testEmail = "test-$timestamp@example.com"

Write-Host "🧪 认证系统测试" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "API URL: $ApiUrl"
Write-Host "Test Email: $testEmail"
Write-Host ""

function Test-Step {
    param([int]$num, [string]$name)
    Write-Host "[$num/5] $name" -ForegroundColor Yellow
}

function Success {
    param([string]$message)
    Write-Host "✅ $message" -ForegroundColor Green
}

function Error {
    param([string]$message)
    Write-Host "❌ $message" -ForegroundColor Red
    exit 1
}

# Test 1: 请求 OTP
Test-Step 1 "请求 OTP..."
$response = Invoke-WebRequest -Uri "$ApiUrl/api/auth/request-otp" `
    -Method POST `
    -Headers @{"Content-Type" = "application/json"} `
    -Body (@{email = $testEmail} | ConvertTo-Json) `
    -UseBasicParsing

$responseBody = $response.Content | ConvertFrom-Json

if (-not $responseBody.success) {
    Error "OTP 请求失败"
}
Success "OTP 请求成功"
Write-Host ""

# Test 2: 获取 OTP (从数据库)
Write-Host "⚠️  需要手动获取 OTP 码" -ForegroundColor Yellow
Write-Host "执行以下命令:"
Write-Host "  wrangler d1 execute voice_ai_users --command ""SELECT code FROM otp_codes WHERE email = '$testEmail' ORDER BY created_at DESC LIMIT 1"""
Write-Host ""

$otp = Read-Host "输入 OTP 码"

if ([string]::IsNullOrWhiteSpace($otp)) {
    Error "OTP 码不能为空"
}

# Test 3: 验证 OTP
Test-Step 2 "验证 OTP..."
$verifyResponse = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-otp" `
    -Method POST `
    -Headers @{"Content-Type" = "application/json"} `
    -Body (@{email = $testEmail; code = $otp} | ConvertTo-Json) `
    -UseBasicParsing

$verifyBody = $verifyResponse.Content | ConvertFrom-Json

if (-not $verifyBody.success -or -not $verifyBody.token) {
    Error "OTP 验证失败: $($verifyBody.message)"
}

$token = $verifyBody.token
Success "OTP 验证成功"
Write-Host "Token: $token" -ForegroundColor Cyan
Write-Host ""

# Test 4: 验证 Session
Test-Step 3 "验证 Session..."
$sessionResponse = Invoke-WebRequest -Uri "$ApiUrl/api/auth/verify-session" `
    -Method GET `
    -Headers @{"Authorization" = "Bearer $token"} `
    -UseBasicParsing

$sessionBody = $sessionResponse.Content | ConvertFrom-Json

if (-not $sessionBody.success) {
    Error "Session 验证失败"
}

$userId = $sessionBody.userId
Success "Session 验证成功"
Write-Host "User ID: $userId" -ForegroundColor Cyan
Write-Host ""

# Test 5: 获取用户资料
Test-Step 4 "获取用户资料..."
$profileResponse = Invoke-WebRequest -Uri "$ApiUrl/api/user/profile" `
    -Method GET `
    -Headers @{"Authorization" = "Bearer $token"} `
    -UseBasicParsing

$profileBody = $profileResponse.Content | ConvertFrom-Json
Success "用户资料获取成功"
Write-Host "Email: $($profileBody.user.email)" -ForegroundColor Cyan
Write-Host ""

# Test 6: 更新用户资料
Test-Step 5 "更新用户资料..."
$updateResponse = Invoke-WebRequest -Uri "$ApiUrl/api/user/profile" `
    -Method PUT `
    -Headers @{"Authorization" = "Bearer $token"; "Content-Type" = "application/json"} `
    -Body (@{name = "Test User"; personaId = "persona_123"} | ConvertTo-Json) `
    -UseBasicParsing

$updateBody = $updateResponse.Content | ConvertFrom-Json
Success "用户资料更新成功"
Write-Host ""

# 总结
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "✅ 所有测试通过!" -ForegroundColor Green
Write-Host ""
Write-Host "生成的 Token (可用于后续测试):" -ForegroundColor Cyan
Write-Host $token
Write-Host ""
Write-Host "后续命令示例:" -ForegroundColor Yellow
Write-Host "  # 查看会话列表"
Write-Host "  Invoke-WebRequest -Uri '$ApiUrl/api/user/sessions' -Headers @{'Authorization'='Bearer $token'}"
Write-Host ""
Write-Host "  # 查看审计日志"
Write-Host "  Invoke-WebRequest -Uri '$ApiUrl/api/user/audit?limit=10' -Headers @{'Authorization'='Bearer $token'}"
Write-Host ""
Write-Host "  # 登出"
Write-Host "  Invoke-WebRequest -Uri '$ApiUrl/api/user/logout' -Method POST -Headers @{'Authorization'='Bearer $token'}"
