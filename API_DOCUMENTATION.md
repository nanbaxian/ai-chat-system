# 认证系统 API 文档

**基础 URL**: `https://your-app.workers.dev` (生产) 或 `http://localhost:8787` (本地开发)

## 1️⃣ 认证端点

### 请求 OTP

**端点**: `POST /api/auth/request-otp`

**描述**: 向用户邮箱发送 6 位验证码

**请求体**:
```json
{
  "email": "user@example.com"
}
```

**成功响应** (200):
```json
{
  "success": true,
  "message": "OTP sent to email"
}
```

**错误响应** (400):
```json
{
  "success": false,
  "message": "Invalid email address"
}
```

**错误信息**:
- `"Invalid email address"` - 邮箱格式不正确
- `"Too many attempts, please try later"` - 超过速率限制 (5次/小时)
- `"Failed to send OTP"` - 邮件发送失败

**示例**:
```bash
curl -X POST http://localhost:8787/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com"}'
```

---

### 验证 OTP

**端点**: `POST /api/auth/verify-otp`

**描述**: 验证用户的 OTP 码，返回 Session Token

**请求体**:
```json
{
  "email": "user@example.com",
  "code": "123456"
}
```

**成功响应** (200):
```json
{
  "success": true,
  "token": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "message": "OTP verified"
}
```

**错误响应** (400):
```json
{
  "success": false,
  "message": "Invalid or expired OTP"
}
```

**错误信息**:
- `"Invalid or expired OTP"` - OTP 错误或已过期 (10分钟)
- `"OTP attempts exceeded"` - 尝试次数过多 (3次)
- `"Verification failed"` - 服务器错误

**OTP 有效期**: 10 分钟  
**最大尝试次数**: 3 次

**示例**:
```bash
curl -X POST http://localhost:8787/api/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","code":"123456"}'
```

---

### 验证 Session

**端点**: `GET /api/auth/verify-session`

**描述**: 验证 Session Token 是否有效

**请求头**:
```
Authorization: Bearer <token>
```

**成功响应** (200):
```json
{
  "success": true,
  "userId": "user_1234567890_abc123",
  "user": {
    "id": "user_1234567890_abc123",
    "email": "user@example.com",
    "name": null,
    "personaId": null
  }
}
```

**错误响应** (401):
```json
{
  "success": false
}
```

**Session 有效期**: 30 天

**示例**:
```bash
curl -X GET http://localhost:8787/api/auth/verify-session \
  -H "Authorization: Bearer your_token_here"
```

---

## 2️⃣ 用户管理端点

⚠️ **所有用户端点都需要认证**，需要在请求头中提供有效的 Token：
```
Authorization: Bearer <session_token>
```

### 获取用户资料

**端点**: `GET /api/user/profile`

**描述**: 获取当前登录用户的资料

**成功响应** (200):
```json
{
  "success": true,
  "user": {
    "id": "user_xxx",
    "email": "user@example.com",
    "name": "John Doe",
    "personaId": "persona_123",
    "createdAt": "2025-09-07T10:30:00Z",
    "updatedAt": "2025-09-07T10:30:00Z"
  }
}
```

**示例**:
```bash
curl -X GET http://localhost:8787/api/user/profile \
  -H "Authorization: Bearer your_token"
```

---

### 更新用户资料

**端点**: `PUT /api/user/profile`

**描述**: 更新用户资料（名字、关联的人物 ID 等）

**请求体**:
```json
{
  "name": "New Name",
  "personaId": "new_persona_id"
}
```

**成功响应** (200):
```json
{
  "success": true,
  "user": {
    "id": "user_xxx",
    "email": "user@example.com",
    "name": "New Name",
    "personaId": "new_persona_id",
    "updatedAt": "2025-09-07T10:35:00Z"
  }
}
```

**示例**:
```bash
curl -X PUT http://localhost:8787/api/user/profile \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","personaId":"persona_123"}'
```

---

### 获取会话列表

**端点**: `GET /api/user/sessions`

**描述**: 获取当前用户的所有有效会话

**成功响应** (200):
```json
{
  "success": true,
  "sessions": [
    {
      "id": "sess_xxx",
      "createdAt": "2025-09-07T10:30:00Z",
      "expiresAt": "2025-10-07T10:30:00Z",
      "ipAddress": "192.168.1.1"
    }
  ]
}
```

**示例**:
```bash
curl -X GET http://localhost:8787/api/user/sessions \
  -H "Authorization: Bearer your_token"
```

---

### 登出当前会话

**端点**: `POST /api/user/logout`

**描述**: 注销当前会话，使该 Token 失效

**请求体**: （空）

**成功响应** (200):
```json
{
  "success": true,
  "message": "Logged out"
}
```

**示例**:
```bash
curl -X POST http://localhost:8787/api/user/logout \
  -H "Authorization: Bearer your_token"
```

---

### 注销所有会话

**端点**: `POST /api/user/logout-all`

**描述**: 注销用户的所有会话（在所有设备上登出）

**请求体**: （空）

**成功响应** (200):
```json
{
  "success": true,
  "message": "All sessions revoked"
}
```

**示例**:
```bash
curl -X POST http://localhost:8787/api/user/logout-all \
  -H "Authorization: Bearer your_token"
```

---

### 获取审计日志

**端点**: `GET /api/user/audit`

**描述**: 获取用户的活动审计日志

**查询参数**:
- `limit` (可选, 默认 50): 返回的日志数量 (1-100)

**成功响应** (200):
```json
{
  "success": true,
  "history": [
    {
      "id": "log_xxx",
      "action": "login",
      "details": {},
      "ipAddress": "192.168.1.1",
      "createdAt": "2025-09-07T10:30:00Z"
    },
    {
      "id": "log_xxx",
      "action": "update_profile",
      "details": {"name": "New Name"},
      "ipAddress": "192.168.1.1",
      "createdAt": "2025-09-07T10:35:00Z"
    }
  ]
}
```

**审计操作类型**:
- `login` - 用户登录
- `logout` - 用户登出
- `logout_all` - 所有会话注销
- `view_profile` - 查看资料
- `update_profile` - 更新资料
- `list_sessions` - 查看会话
- `delete_account` - 删除账户

**示例**:
```bash
curl -X GET "http://localhost:8787/api/user/audit?limit=20" \
  -H "Authorization: Bearer your_token"
```

---

### 删除账户

**端点**: `DELETE /api/user/account`

**描述**: 永久删除用户账户及所有相关数据

⚠️ **危险操作** - 无法撤销！

**请求体**:
```json
{
  "password": "confirmation"
}
```

**成功响应** (200):
```json
{
  "success": true
}
```

**示例**:
```bash
curl -X DELETE http://localhost:8787/api/user/account \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{"password":"confirm"}'
```

---

## 📊 错误处理

所有端点都返回以下错误格式：

**401 Unauthorized**:
```json
{
  "error": "Unauthorized"
}
```

**400 Bad Request**:
```json
{
  "success": false,
  "message": "error details"
}
```

**500 Internal Server Error**:
```json
{
  "success": false,
  "message": "Internal server error"
}
```

---

## 🔒 安全特性

### Rate Limiting

- **OTP 请求**: 5次/小时 (按邮箱)
- **OTP 验证**: 3次/OTP 码

### Token Security

- **格式**: 64 字符十六进制字符串
- **有效期**: 30 天
- **存储**: 使用 Cloudflare KV 缓存已撤销的 Token
- **传输**: 始终使用 HTTPS

### CORS Policy

- 允许所有来源 (*)
- 允许方法: GET, POST, PUT, DELETE, OPTIONS
- 允许头: Content-Type, Authorization

---

## 📝 示例流程

### 完整登录流程

```bash
#!/bin/bash

API="http://localhost:8787"
EMAIL="user@example.com"

# 1. 请求 OTP
curl -X POST $API/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\"}"

# [用户收到邮件，获取 OTP 码: 123456]

# 2. 验证 OTP
RESPONSE=$(curl -s -X POST $API/api/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"code\":\"123456\"}")

TOKEN=$(echo $RESPONSE | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

# 3. 验证 Session
curl -X GET $API/api/auth/verify-session \
  -H "Authorization: Bearer $TOKEN"

# 4. 获取用户资料
curl -X GET $API/api/user/profile \
  -H "Authorization: Bearer $TOKEN"

# 5. 更新资料
curl -X PUT $API/api/user/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe"}'

# 6. 登出
curl -X POST $API/api/user/logout \
  -H "Authorization: Bearer $TOKEN"
```

---

## 🔍 调试

### 启用调试模式

```bash
# 查看实时日志
wrangler tail

# 查看特定邮箱的 OTP
wrangler d1 execute voice_ai_users --command \
  "SELECT email, code, expires_at FROM otp_codes WHERE email = 'user@example.com'"
```

### 常见问题

**Q: Token 过期了怎么办？**
A: 需要重新登录，即从请求 OTP 开始。

**Q: 如何在 Token 过期前刷新？**
A: 目前没有刷新机制，需要重新登录。可以通过延长 Token 有效期来改进。

**Q: 支持社交登录吗？**
A: 目前只支持邮件 OTP，社交登录是计划中的功能。

---

## 📚 更多资源

- [快速启动](./QUICKSTART_AUTH.md)
- [详细设置](./backend/CLOUDFLARE_SETUP.md)
- [部署清单](./DEPLOYMENT_CHECKLIST.md)
