# Cloudflare 全栈认证部署指南

完全迁出 Supabase，所有数据存储在 Cloudflare 上。

## 前置条件

- Wrangler CLI: `npm i -g wrangler@latest`
- Cloudflare 账户
- Brevo API Key（邮件发送）

## 第 1 步：创建 D1 数据库

```bash
cd backend

# 创建数据库
wrangler d1 create voice_ai_users

# 复制输出的 database_id 到 wrangler.toml
# 输出示例：
# [[d1_databases]]
# binding = "DB"
# database_name = "voice_ai_users"
# database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 初始化表结构
wrangler d1 execute voice_ai_users --file ./migrations/d1-init.sql
```

## 第 2 步：创建 KV 命名空间

```bash
# 创建 KV 命名空间
wrangler kv:namespace create OTP_KV

# 如果需要 staging 环境
wrangler kv:namespace create OTP_KV --preview

# 复制输出的 id 到 wrangler.toml
# 输出示例：
# [[kv_namespaces]]
# binding = "OTP_KV"
# id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

## 第 3 步：设置环境变量

创建 `.dev.vars` 文件（本地开发）：

```env
BREVO_API_KEY=your_brevo_api_key_here
SIGNAL_AUTHORIZATION=Bearer demo-token
ASSEMBLYAI_API_KEY=your_key
DEEPINFRA_API_KEY=your_key
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_key
ELEVENLABS_API_KEY=your_key
DEEPGRAM_API_KEY=your_key
```

设置生产环境变量：

```bash
# 逐个设置
wrangler secret put BREVO_API_KEY
wrangler secret put SIGNAL_AUTHORIZATION
# ... 其他秘密变量
```

## 第 4 步：测试认证端点

### 本地测试

```bash
# 启动本地开发服务器
wrangler dev

# 在另一个终端测试
# 1. 请求 OTP
curl -X POST http://localhost:8787/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'

# 2. 验证 OTP（查看日志中的代码）
curl -X POST http://localhost:8787/api/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","code":"123456"}'

# 3. 验证 Session
curl -X GET http://localhost:8787/api/auth/verify-session \
  -H "Authorization: Bearer <token_from_step_2>"
```

## 第 5 步：部署

```bash
# 检查 wrangler.toml 中的所有配置
wrangler publish

# 生产环境验证
curl -X POST https://voice-ai-demo.your-domain.com/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'
```

## API 端点

### 1. 请求 OTP
```
POST /api/auth/request-otp
Content-Type: application/json

{
  "email": "user@example.com"
}

Response (200):
{
  "success": true,
  "message": "OTP sent to email"
}
```

### 2. 验证 OTP
```
POST /api/auth/verify-otp
Content-Type: application/json

{
  "email": "user@example.com",
  "code": "123456"
}

Response (200):
{
  "success": true,
  "token": "session_token_here",
  "message": "OTP verified"
}
```

### 3. 验证 Session
```
GET /api/auth/verify-session
Authorization: Bearer <session_token>

Response (200):
{
  "success": true,
  "userId": "user_xxx",
  "user": {
    "id": "user_xxx",
    "email": "user@example.com",
    "name": null,
    "personaId": null
  }
}
```

## 数据库表结构

### users
- `id` - 用户ID (PRIMARY KEY)
- `email` - 邮箱 (UNIQUE)
- `name` - 用户名
- `persona_id` - 关联的人物ID
- `created_at` - 创建时间
- `updated_at` - 更新时间

### otp_codes
- `id` - OTP 记录ID (PRIMARY KEY)
- `email` - 邮箱
- `code` - 验证码
- `attempts` - 尝试次数
- `max_attempts` - 最多尝试次数（默认3）
- `created_at` - 创建时间
- `expires_at` - 过期时间
- `used` - 是否已使用

### sessions
- `id` - Session ID (PRIMARY KEY)
- `user_id` - 用户ID (FOREIGN KEY)
- `token` - Session Token (UNIQUE)
- `created_at` - 创建时间
- `expires_at` - 过期时间（默认30天）
- `ip_address` - IP地址
- `user_agent` - User Agent

## 清理过期数据

定期运行清理任务（可用 Cron Trigger）：

```bash
# 删除过期的 OTP
wrangler d1 execute voice_ai_users --command "DELETE FROM otp_codes WHERE expires_at < datetime('now')"

# 删除过期的 Session
wrangler d1 execute voice_ai_users --command "DELETE FROM sessions WHERE expires_at < datetime('now')"
```

## 故障排查

### OTP 没有发送
1. 检查 Brevo API Key 是否正确
2. 查看 Worker 日志：`wrangler tail`
3. 检查邮箱是否正确

### 验证失败
1. 确认 OTP 未过期（10分钟）
2. 确认 OTP 正确
3. 检查 D1 数据库是否有数据：
   ```bash
   wrangler d1 execute voice_ai_users --command "SELECT * FROM otp_codes WHERE email = 'test@example.com'"
   ```

### Session 验证失败
1. 确认 Token 未过期
2. 确认 Token 格式正确
3. 检查 D1 sessions 表

## 成本估算

- **D1**: 免费层 5GB + $0.75/GB 超额
- **KV**: 免费层 10 万/天 + 按量付费
- **Brevo**: 免费 300 封/天 + $0.0035/封

对于小型应用，成本极低！
