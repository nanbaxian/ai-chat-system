# 脚本和工具使用指南

本目录包含多个实用脚本，用于测试、监控、备份和维护认证系统。

## 📋 脚本列表

### 1. `test-auth.ps1` / `test-auth.sh`
**功能**: 完整的认证流程测试

**用途**: 验证整个登录流程是否正常工作

**使用方法**:
```powershell
# Windows PowerShell
.\scripts\test-auth.ps1

# 指定自定义 API URL
.\scripts\test-auth.ps1 -ApiUrl "https://your-app.workers.dev"
```

**测试流程**:
1. ✅ 请求 OTP
2. ✅ 验证 OTP
3. ✅ 验证 Session
4. ✅ 获取用户资料
5. ✅ 更新用户资料

**预期结果**: 所有步骤通过

**常见问题**:
- **OTP 邮件未收到**: 检查 Brevo API Key 配置
- **Token 验证失败**: 检查数据库连接
- **超时错误**: 检查 API 服务是否运行

---

### 2. `monitor.ps1`
**功能**: 系统健康监控

**用途**: 实时监控系统状态，检测异常

**使用方法**:
```powershell
# 单次检查
.\scripts\monitor.ps1

# 连续监控 (每 60 秒检查一次)
.\scripts\monitor.ps1 -Continuous

# 自定义检查间隔
.\scripts\monitor.ps1 -Continuous -IntervalSeconds 30

# 指定 API URL
.\scripts\monitor.ps1 -ApiUrl "https://your-app.workers.dev" -Continuous
```

**监控项目**:
- ✅ OTP 端点
- ✅ Session 验证端点
- ✅ 数据库连接
- ✅ 响应时间
- ✅ 错误追踪

**输出解释**:
```
✅ OK - 端点正常响应
❌ FAILED - 端点异常
响应时间 - 毫秒
```

**应用场景**:
- 监控生产环境
- 性能分析
- 故障排查

**建议**:
- 生产环境每 5 分钟检查一次
- 使用外部监控工具 (Uptime Robot 等)

---

### 3. `backup.ps1`
**功能**: 数据库备份和恢复

**用途**: 定期备份 D1 数据库，防止数据丢失

**使用方法**:
```powershell
# 创建备份
.\scripts\backup.ps1

# 指定数据库名称
.\scripts\backup.ps1 -DatabaseName "voice_ai_users"

# 自定义备份目录
.\scripts\backup.ps1 -BackupDir "./my-backups"

# 查看备份统计
.\scripts\backup.ps1  # 自动显示统计

# 恢复备份 (交互式)
.\scripts\backup.ps1 -Restore -RestoreFile "./backups/backup_file.sql"
```

**备份文件**:
- 位置: `./backups/` 目录
- 格式: `voice_ai_users_YYYYMMDD_HHMMSS.sql`
- 内容: 所有表的数据导出

**自动清理**:
- 脚本自动删除 30 天以前的备份
- 修改 `Clean-OldBackups -DaysToKeep 60` 保留更长期

**恢复步骤**:
```bash
# 1. 查看备份列表
Get-ChildItem ./backups/

# 2. 执行恢复命令
wrangler d1 execute voice_ai_users --file ./backups/voice_ai_users_20250907_120000.sql

# 3. 验证恢复
wrangler d1 execute voice_ai_users --command "SELECT COUNT(*) FROM users"
```

**备份策略**:
- 每天运行一次 (使用计划任务)
- 关键操作后立即备份
- 定期测试恢复流程

**Windows 任务计划**:
```powershell
# 创建计划任务 (每天午夜)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-File C:\path\to\backup.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 00:00
Register-ScheduledTask -TaskName "D1-Backup" -Action $action -Trigger $trigger
```

---

### 4. `benchmark.ps1`
**功能**: 性能基准测试

**用途**: 测量系统性能指标，检测性能退化

**使用方法**:
```powershell
# 基本性能测试
.\scripts\benchmark.ps1

# 指定 API URL
.\scripts\benchmark.ps1 -ApiUrl "https://your-app.workers.dev"

# 自定义请求数
.\scripts\benchmark.ps1 -Requests 200

# 自定义并发数
.\scripts\benchmark.ps1 -Concurrency 20
```

**测试项目**:

#### 测试 1: OTP 请求
- 发送 10 个 OTP 请求
- 测量响应时间

#### 测试 2: Session 验证
- 验证 20 个 Session
- 测量平均响应时间

#### 测试 3: 吞吐量
- 测量每秒处理的请求数
- 识别瓶颈

**输出示例**:
```
📊 OTP 请求统计:
  平均响应时间: 245 ms ✅
  最小响应时间: 180 ms
  最大响应时间: 320 ms
  成功率: 10 / 10

📊 Session 验证统计:
  平均响应时间: 45 ms ✅
  最小响应时间: 30 ms
  最大响应时间: 65 ms

📊 并发测试统计:
  总时间: 2500ms
  吞吐量: 8.00 请求/秒 ✅
```

**性能基准**:
```
OTP 请求: <500ms ✅
Session 验证: <100ms ✅
吞吐量: >10 请求/秒 ✅
```

**性能分析**:
- 如果响应时间 > 基准: 检查数据库查询
- 如果吞吐量 < 基准: 检查 Worker 资源限制
- 如果波动大: 可能存在缓存问题

---

### 5. `security-audit.ps1`
**功能**: 安全审计

**用途**: 检查系统安全配置，识别安全问题

**使用方法**:
```powershell
# 完整安全审计
.\scripts\security-audit.ps1

# 指定 API URL
.\scripts\security-audit.ps1 -ApiUrl "https://your-app.workers.dev"

# 定期审计 (每月)
# 使用 Windows 任务计划或 Cron 作业
```

**审计项目**:

| 检查项 | 说明 |
|--------|------|
| CORS 配置 | 检查 CORS 头是否正确 |
| 认证要求 | 验证受保护端点需要 token |
| HTTPS 加密 | 确保使用 HTTPS (生产) |
| 速率限制 | 检测速率限制保护 |
| 错误处理 | 验证错误消息不泄露信息 |
| OTP 参数 | 检查 OTP 安全参数 |
| 内容类型 | 验证内容类型验证 |

**输出示例**:
```
✅ PASS - CORS 已启用
✅ PASS - 受保护端点认证
✅ PASS - HTTPS 使用 (生产)
⚠️  WARN - 未检测到速率限制
✅ PASS - 错误消息隐藏

🎯 安全评分: 85/100
```

**安全评分解释**:
- 90-100: 优秀 (生产就绪)
- 70-89: 良好 (建议改进)
- 50-69: 一般 (需要改进)
- <50: 差 (需要立即修复)

**常见问题修复**:
```powershell
# 问题: HTTPS 未启用
# 解决: 在生产环境使用 HTTPS URL

# 问题: 速率限制未检测
# 解决: 检查 auth/manager.ts 中的 ratelimit 实现

# 问题: CORS 未启用
# 解决: 检查 worker.ts 中的 CORS_HEADERS 配置
```

---

## 🛠 脚本安装和配置

### 预置要求
- PowerShell 5.0+ (Windows)
- Bash 4.0+ (Linux/macOS)
- Wrangler CLI 已安装
- 网络访问 API 端点

### 首次使用

```powershell
# 1. 允许执行 PowerShell 脚本
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 2. 导航到脚本目录
cd backend/scripts

# 3. 运行脚本
.\test-auth.ps1
```

### 设置环境变量 (可选)

```powershell
# 添加到 PowerShell 配置文件
$PROFILE

# 添加别名
New-Alias -Name auth-test -Value "C:\path\to\test-auth.ps1"
New-Alias -Name monitor -Value "C:\path\to\monitor.ps1"
```

---

## 📅 定期维护计划

### 每天
- ☑️ 运行 `monitor.ps1` (或自动监控)
- ☑️ 检查错误日志 (`wrangler tail`)

### 每周
- ☑️ 运行 `benchmark.ps1` (性能趋势)
- ☑️ 检查数据库大小
- ☑️ 验证备份完整性

### 每月
- ☑️ 运行 `security-audit.ps1` (安全审计)
- ☑️ 更新依赖包
- ☑️ 测试灾难恢复流程

### 每季度
- ☑️ 审查审计日志
- ☑️ 优化数据库查询
- ☑️ 容量规划

---

## 🔧 故障排查

### 脚本无法运行
```powershell
# 问题: "脚本被拒绝执行"
# 解决:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 问题: "找不到命令: wrangler"
# 解决:
npm install -g wrangler@latest
```

### 连接超时
```powershell
# 问题: "请求超时"
# 解决:
# 1. 检查 API 是否运行: wrangler dev
# 2. 检查 URL 是否正确
# 3. 检查网络连接
```

### 备份失败
```powershell
# 问题: "无法连接到数据库"
# 解决:
# 1. 验证 D1 数据库 ID
# 2. 检查 wrangler.toml 配置
# 3. 运行: wrangler d1 info voice_ai_users
```

---

## 📊 性能监控仪表板

建议整合以下工具来构建完整的监控系统：

### 本地监控
- `monitor.ps1` - 定期健康检查
- `benchmark.ps1` - 性能基准
- `wrangler tail` - 实时日志

### 外部监控
- **Uptime Robot** - 可用性监控
- **Datadog** - 性能监控
- **Sentry** - 错误追踪

### 告警配置
```
响应时间 > 500ms → 告警
错误率 > 1% → 告警
OTP 失败 > 10% → 告警
数据库 > 4GB → 告警
```

---

## 📚 相关文档

- [QUICKSTART_AUTH.md](../QUICKSTART_AUTH.md) - 快速开始
- [API_DOCUMENTATION.md](../API_DOCUMENTATION.md) - API 文档
- [DEPLOYMENT_CHECKLIST.md](../DEPLOYMENT_CHECKLIST.md) - 部署清单

---

**最后更新**: 2025-09-07  
**脚本状态**: ✅ 生产就绪
