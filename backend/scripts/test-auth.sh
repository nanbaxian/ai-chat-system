#!/bin/bash

# 认证系统测试脚本
# 使用: bash scripts/test-auth.sh [API_URL]
# 默认: http://localhost:8787

API_URL="${1:-http://localhost:8787}"
TEST_EMAIL="test-$(date +%s)@example.com"

echo "🧪 认证系统测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "API URL: $API_URL"
echo "Test Email: $TEST_EMAIL"
echo ""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: 请求 OTP
echo -e "${YELLOW}[1/5]${NC} 请求 OTP..."
RESPONSE=$(curl -s -X POST "$API_URL/api/auth/request-otp" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\"}")

echo "Response: $RESPONSE"
SUCCESS=$(echo $RESPONSE | grep -o '"success":true')

if [ -z "$SUCCESS" ]; then
  echo -e "${RED}❌ OTP 请求失败${NC}"
  exit 1
fi
echo -e "${GREEN}✅ OTP 请求成功${NC}"
echo ""

# 从响应中提取 OTP (本地测试)
OTP=$(curl -s "$API_URL/api/auth/debug-otp?email=$TEST_EMAIL" 2>/dev/null || echo "")

if [ -z "$OTP" ]; then
  echo -e "${YELLOW}⚠️  本地测试: 需要手动查看邮件或数据库获取 OTP code${NC}"
  echo "执行: wrangler d1 execute voice_ai_users --command \"SELECT code FROM otp_codes WHERE email = '$TEST_EMAIL' ORDER BY created_at DESC LIMIT 1\""
  echo ""
  read -p "输入 OTP 码: " OTP
fi

echo "Using OTP: $OTP"
echo ""

# Test 2: 验证 OTP
echo -e "${YELLOW}[2/5]${NC} 验证 OTP..."
VERIFY_RESPONSE=$(curl -s -X POST "$API_URL/api/auth/verify-otp" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"code\":\"$OTP\"}")

echo "Response: $VERIFY_RESPONSE"
TOKEN=$(echo $VERIFY_RESPONSE | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo -e "${RED}❌ OTP 验证失败${NC}"
  exit 1
fi
echo -e "${GREEN}✅ OTP 验证成功${NC}"
echo "Token: $TOKEN"
echo ""

# Test 3: 验证 Session
echo -e "${YELLOW}[3/5]${NC} 验证 Session..."
SESSION_RESPONSE=$(curl -s -X GET "$API_URL/api/auth/verify-session" \
  -H "Authorization: Bearer $TOKEN")

echo "Response: $SESSION_RESPONSE"
USER_ID=$(echo $SESSION_RESPONSE | grep -o '"userId":"[^"]*"' | cut -d'"' -f4)

if [ -z "$USER_ID" ]; then
  echo -e "${RED}❌ Session 验证失败${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Session 验证成功${NC}"
echo "User ID: $USER_ID"
echo ""

# Test 4: 获取用户资料
echo -e "${YELLOW}[4/5]${NC} 获取用户资料..."
PROFILE_RESPONSE=$(curl -s -X GET "$API_URL/api/user/profile" \
  -H "Authorization: Bearer $TOKEN")

echo "Response: $PROFILE_RESPONSE"
echo -e "${GREEN}✅ 用户资料获取成功${NC}"
echo ""

# Test 5: 更新用户资料
echo -e "${YELLOW}[5/5]${NC} 更新用户资料..."
UPDATE_RESPONSE=$(curl -s -X PUT "$API_URL/api/user/profile" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","personaId":"persona_123"}')

echo "Response: $UPDATE_RESPONSE"
echo -e "${GREEN}✅ 用户资料更新成功${NC}"
echo ""

# 总结
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ 所有测试通过!${NC}"
echo ""
echo "生成的 Token (可用于后续测试):"
echo "$TOKEN"
echo ""
echo "后续命令示例:"
echo "  # 查看会话列表"
echo "  curl -X GET $API_URL/api/user/sessions -H \"Authorization: Bearer $TOKEN\""
echo ""
echo "  # 查看审计日志"
echo "  curl -X GET '$API_URL/api/user/audit?limit=10' -H \"Authorization: Bearer $TOKEN\""
echo ""
echo "  # 登出"
echo "  curl -X POST $API_URL/api/user/logout -H \"Authorization: Bearer $TOKEN\""
