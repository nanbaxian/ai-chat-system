# Cloudflare 认证系统部署清单

## ✅ 前置条件检查

- [ ] Node.js 18+ 已安装 (`node --version`)
- [ ] Wrangler CLI 已安装 (`wrangler --version`)
- [ ] 已登录 Cloudflare 账户 (`wrangler login`)
- [ ] Brevo 账户已创建，API Key 已获取
- [ ] Git 已配置（用于部署）

## ⚙️ 第一阶段：本地开发设置

### 1. 创建 Cloudflare 资源

```bash
cd backend

# 1.1 创建 D1 数据库
wrangler d1 create voice_ai_users

# 📝 输出示例:
# [[d1_databases]]
# binding = "DB"
# database_name = "voice_ai_users"
# database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# ✅ 复制 database_id 到 wrangler.toml
```

- [ ] D1 数据库已创建
- [ ] `database_id` 已复制到 `wrangler.toml`

```bash
# 1.2 创建 KV 命名空间
wrangler kv:namespace create OTP_KV

# 📝 输出示例:
# [[kv_namespaces]]
# binding = "OTP_KV"
# id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# ✅ 复制 id 到 wrangler.toml
```

- [ ] KV 命名空间已创建
- [ ] `id` 已复制到 `wrangler.toml`

### 2. 初始化数据库

```bash
# 创建表结构和索引
wrangler d1 execute voice_ai_users --file ./migrations/d1-init.sql

# 验证表已创建
wrangler d1 execute voice_ai_users --command "SELECT name FROM sqlite_master WHERE type='table'"
```

- [ ] 数据库初始化成功
- [ ] 所有表已创建

### 3. 环境变量配置

创建 `backend/.dev.vars`：

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

- [ ] `.dev.vars` 已创建
- [ ] `BREVO_API_KEY` 已填入
- [ ] 所有必要的环境变量已设置

### 4. 本地测试

```bash
# 启动开发服务器
wrangler dev

# 在新终端运行测试脚本
# Windows PowerShell:
.\scripts\test-auth.ps1

# macOS/Linux:
bash scripts/test-auth.sh
```

**测试流程：**
1. [ ] 请求 OTP - 邮件已发送
2. [ ] 验证 OTP - Token 已获取
3. [ ] 验证 Session - 用户信息已返回
4. [ ] 获取资料 - 资料已显示
5. [ ] 更新资料 - 资料已更新

**故障排查：**
- [ ] 检查 `wrangler tail` 日志是否有错误
- [ ] 检查 Brevo API Key 是否正确
- [ ] 检查 D1 数据库是否有数据

## 🚀 第二阶段：前端集成

### 1. 添加认证服务

```dart
// lib/services/auth_service.dart 已创建
```

- [ ] `auth_service.dart` 文件已复制
- [ ] API URL 已配置为本地服务器

### 2. 添加登录屏幕

```dart
// lib/screens/login_screen.dart 已创建
```

- [ ] `login_screen.dart` 文件已复制
- [ ] 在 `main.dart` 中添加登录流程

### 3. 测试前端

```bash
cd frontend/flutter

# 运行 Web 版本
flutter run -d chrome

# 或 iOS/Android
flutter run -d ios
flutter run -d android
```

**前端测试检查：**
- [ ] 登录屏幕可正常显示
- [ ] 邮件输入有验证
- [ ] OTP 输入显示 6 位数字键盘
- [ ] 错误消息正确显示
- [ ] Token 存储到本地

## 🌐 第三阶段：生产部署

### 1. 生产环境变量配置

```bash
# 设置生产秘密
wrangler secret put BREVO_API_KEY
wrangler secret put SIGNAL_AUTHORIZATION
wrangler secret put ASSEMBLYAI_API_KEY
# ... 其他秘密

# 验证已设置
wrangler secret list
```

- [ ] 所有秘密已设置到生产环境
- [ ] 秘密列表已验证

### 2. 更新 wrangler.toml

检查以下配置：
- [ ] `name` = 你的应用名称
- [ ] `main` = "backend/src/worker.ts"
- [ ] `database_id` 正确
- [ ] KV `id` 正确

### 3. 部署

```bash
# 编译和部署
wrangler publish

# 验证部署
wrangler deployments list

# 检查日志
wrangler tail
```

- [ ] 部署成功（没有错误）
- [ ] 可以访问 workers.dev 域名
- [ ] 日志显示应用运行

### 4. 生产测试

```bash
# 使用生产 URL 测试
$ApiUrl = "https://your-app.workers.dev"

# Windows:
.\scripts\test-auth.ps1 -ApiUrl $ApiUrl

# macOS/Linux:
bash scripts/test-auth.sh $ApiUrl
```

**生产测试检查：**
- [ ] OTP 请求成功 (收到邮件)
- [ ] OTP 验证成功
- [ ] Session 验证成功
- [ ] 用户操作正常

### 5. 设置自定义域名（可选）

```bash
# 在 Cloudflare 仪表板中配置
# Zone > Workers > 你的应用 > 设置 > 自定义域
```

- [ ] 自定义域名已添加
- [ ] SSL/TLS 证书已配置
- [ ] DNS 已解析

## 📊 第四阶段：监控和维护

### 1. 设置日志

```bash
# 实时查看日志
wrangler tail

# 保存日志到文件
wrangler tail > logs.txt
```

- [ ] 已设置日志收集
- [ ] 定期检查错误日志

### 2. 数据库维护

```bash
# 清理过期 OTP (每天运行)
wrangler d1 execute voice_ai_users --command "DELETE FROM otp_codes WHERE expires_at < datetime('now')"

# 清理过期 Session (每周运行)
wrangler d1 execute voice_ai_users --command "DELETE FROM sessions WHERE expires_at < datetime('now')"

# 检查存储使用
wrangler d1 info voice_ai_users
```

- [ ] 已设置清理任务
- [ ] 监控数据库大小

### 3. 安全检查

```bash
# 检查秘密是否正确设置
wrangler secret list

# 验证 CORS 配置
curl -X OPTIONS https://your-app.workers.dev/api/auth/request-otp \
  -H "Origin: https://yourapp.com" -v
```

- [ ] 秘密安全存储
- [ ] CORS 配置正确
- [ ] 没有敏感信息在日志中

## 📈 性能优化

### 缓存配置

- [ ] KV 缓存已启用 OTP
- [ ] Session Token 有 TTL
- [ ] D1 查询已优化

### 成本监控

```bash
# 检查 Workers 分析
# Cloudflare 仪表板 > Analytics & Logs > Workers

# 预计成本:
# D1: 免费 5GB + $0.75/GB 超额
# KV: 免费 100k请求/天
# Workers: 免费 100k请求/天
```

- [ ] 已启用成本监控
- [ ] 预算告警已设置

## 🔄 回滚计划

如果生产出现问题：

```bash
# 查看部署历史
wrangler deployments list

# 回滚到之前的版本
wrangler rollback

# 查看 D1 迁移历史
wrangler d1 migrations list voice_ai_users
```

- [ ] 理解回滚流程
- [ ] 有备份计划

## ✨ 最终验收

- [ ] 所有测试通过
- [ ] 前端可以成功登录
- [ ] 生产环境稳定运行
- [ ] 监控和告警已设置
- [ ] 文档已更新

## 🎉 部署完成！

恭喜！你的 Cloudflare 全栈认证系统已上线。

**后续步骤：**
1. 监控应用 24 小时
2. 收集用户反馈
3. 根据使用情况优化
4. 添加更多功能（Magic Link、Social Login 等）
5. 设置自动化清理任务

**需要帮助？**
- 查看 `CLOUDFLARE_SETUP.md` 详细指南
- 查看 `QUICKSTART_AUTH.md` 快速参考
- 检查 `wrangler tail` 查看实时日志
