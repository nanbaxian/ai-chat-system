# 快速启动：Cloudflare 全栈认证系统

## 核心概念

```
┌─────────────────────────────────────────────┐
│  前端 (Flutter)                              │
│  - 请求 OTP (邮箱)                           │
│  - 验证 OTP (6位码)                          │
│  - 获取 Session Token                        │
└──────────────┬──────────────────────────────┘
               │ HTTP/JSON
┌──────────────▼──────────────────────────────┐
│  后端 (Cloudflare Workers)                   │
│  ├── /api/auth/request-otp      (发送码)    │
│  ├── /api/auth/verify-otp       (验证码)    │
│  └── /api/auth/verify-session   (验证令牌)  │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┴────────┬──────────┐
       │                │          │
   ┌───▼───┐  ┌────▼────┐  ┌──▼──────┐
   │ D1    │  │ KV      │  │ Brevo   │
   │ 用户  │  │ OTP缓存 │  │ 邮件API │
   └───────┘  └─────────┘  └─────────┘
```

## ⚡ 3分钟快速部署

### 1️⃣ 本地准备（5分钟）

```bash
cd backend

# 安装 wrangler
npm i -g wrangler@latest

# 创建 D1 数据库
wrangler d1 create voice_ai_users

# 👉 复制 database_id，粘贴到 wrangler.toml
```

### 2️⃣ 创建 KV（2分钟）

```bash
# 创建 KV 命名空间
wrangler kv:namespace create OTP_KV

# 👉 复制 id，粘贴到 wrangler.toml
```

### 3️⃣ 环境变量（1分钟）

创建 `.dev.vars`：
```env
BREVO_API_KEY=xxx
SIGNAL_AUTHORIZATION=Bearer demo-token
```

### 4️⃣ 初始化数据库（1分钟）

```bash
wrangler d1 execute voice_ai_users --file ./migrations/d1-init.sql
```

### 5️⃣ 本地测试（2分钟）

```bash
# 启动开发服务器
wrangler dev

# 另一个终端测试
curl -X POST http://localhost:8787/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com"}'
```

## 📱 前端集成（代码片段）

### 添加登录屏幕

在 `main.dart`：
```dart
import 'screens/login_screen.dart';

// 在状态中
String? sessionToken;

// 用 LoginScreen 替换首页
home: sessionToken == null
    ? LoginScreen(
        onLoginSuccess: (token) {
          setState(() => sessionToken = token);
        },
      )
    : const Home(),
```

### 使用认证令牌

```dart
// 发起请求时带上令牌
final headers = {
  'Authorization': 'Bearer $sessionToken',
  'Content-Type': 'application/json',
};

await http.post(url, headers: headers, body: body);
```

## 🚀 部署到生产

```bash
# 1. 设置生产秘密
wrangler secret put BREVO_API_KEY

# 2. 更新 wrangler.toml 中的应用名称和域名

# 3. 部署
wrangler publish

# 4. 验证
curl https://your-app.workers.dev/api/auth/request-otp \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'
```

## 💾 数据库查询

### 检查用户
```bash
wrangler d1 execute voice_ai_users \
  --command "SELECT * FROM users LIMIT 10"
```

### 查看 OTP 代码
```bash
wrangler d1 execute voice_ai_users \
  --command "SELECT email, code, expires_at FROM otp_codes WHERE used = 0"
```

### 清理过期数据
```bash
wrangler d1 execute voice_ai_users \
  --command "DELETE FROM otp_codes WHERE expires_at < datetime('now')"
```

## 🔍 调试

### 查看实时日志
```bash
wrangler tail
```

### 开发时关闭邮件发送（可选）

在 `src/auth/manager.ts` 中：
```dart
// 注释掉邮件发送来测试本地流程
// await this.email.sendOTP(email, code);
console.log(`[DEBUG] OTP: ${code}`);
```

## 📊 成本估算

| 服务 | 免费额度 | 超额价格 |
|------|--------|---------|
| D1 | 5GB | $0.75/GB |
| KV | 100k请求/天 | 按量 |
| Brevo | 300邮件/天 | $0.0035/邮件 |

**小应用每月 $0-5！**

## ✅ 检查清单

- [ ] D1 数据库已创建且初始化
- [ ] KV 命名空间已创建
- [ ] `wrangler.toml` 包含 database_id 和 kv id
- [ ] `.dev.vars` 包含 `BREVO_API_KEY`
- [ ] `wrangler dev` 本地测试成功
- [ ] 前端添加了 `LoginScreen`
- [ ] `verifySession` 集成到 App 加载逻辑

## 🆘 常见问题

**Q: OTP 邮件没发出去？**
- 检查 Brevo API Key
- 检查 `wrangler tail` 日志
- 验证邮箱地址正确

**Q: 验证失败"Invalid OTP"？**
- 确认 OTP 未过期（10分钟）
- 检查代码是否正确
- 查看 D1：`SELECT * FROM otp_codes`

**Q: Session 验证失败？**
- Token 是否过期（30天）
- Token 格式是否正确
- D1 sessions 表是否有记录

## 📚 完整文档

详见 [CLOUDFLARE_SETUP.md](./backend/CLOUDFLARE_SETUP.md)

---

**下一步？**
- [ ] 添加 Magic Link 登录（改进体验）
- [ ] 添加第三方登录 (Google, GitHub)
- [ ] 实现用户资料管理
- [ ] 添加邮箱验证后的权限检查
