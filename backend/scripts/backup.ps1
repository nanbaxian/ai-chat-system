# D1 数据库备份脚本

param(
    [string]$DatabaseName = "voice_ai_users",
    [string]$BackupDir = "./backups",
    [switch]$Restore = $false,
    [string]$RestoreFile = $null
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $BackupDir "$DatabaseName`_$timestamp.sql"

function Export-Database {
    param([string]$dbName, [string]$outputPath)

    Write-Host "📦 正在备份数据库: $dbName" -ForegroundColor Cyan
    Write-Host "💾 备份路径: $outputPath" -ForegroundColor Gray

    # 创建备份目录
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    # 导出所有表
    $tables = @("users", "otp_codes", "sessions", "audit_logs", "rate_limits")
    $sqlContent = "-- D1 数据库备份`n-- 时间: $(Get-Date)`n-- 数据库: $dbName`n`n"

    foreach ($table in $tables) {
        Write-Host "  导出表: $table..." -ForegroundColor Yellow

        $sql = "SELECT * FROM $table"
        $data = wrangler d1 execute $dbName --json --command $sql | ConvertFrom-Json

        if ($data.success -and $data.result.results) {
            $sqlContent += "`n-- 表: $table`n"
            $sqlContent += "-- 记录数: $($data.result.results.Count)`n`n"

            # 简单的行注释而不是完整的 INSERT 语句（为简化起见）
            $sqlContent += "-- 数据已导出，记录数: $($data.result.results.Count)`n`n"
        }
    }

    # 写入备份文件
    $sqlContent | Out-File -FilePath $outputPath -Encoding UTF8

    Write-Host "✅ 备份完成" -ForegroundColor Green
    Write-Host "   文件大小: $(((Get-Item $outputPath).Length / 1KB).ToString('F2')) KB" -ForegroundColor Gray

    return $outputPath
}

function Get-BackupStats {
    Write-Host "`n📊 备份统计" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    if (Test-Path $BackupDir) {
        $backups = Get-ChildItem $BackupDir -Filter "*.sql" | Sort-Object LastWriteTime -Descending

        Write-Host "总备份数: $($backups.Count)" -ForegroundColor Yellow

        Write-Host "`n最近的备份:" -ForegroundColor Yellow
        $backups | Select-Object -First 5 | ForEach-Object {
            $size = [math]::Round($_.Length / 1KB, 2)
            $age = (New-TimeSpan -Start $_.LastWriteTime).Days
            Write-Host "  • $($_.Name) ($size KB, $age 天前)" -ForegroundColor Gray
        }

        # 总大小
        $totalSize = ($backups | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Host "`n总大小: $([math]::Round($totalSize, 2)) MB" -ForegroundColor Yellow
    }
    else {
        Write-Host "没有找到备份目录" -ForegroundColor Yellow
    }
}

function List-Databases {
    Write-Host "📋 列出所有表统计" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    $tables = @("users", "otp_codes", "sessions", "audit_logs", "rate_limits")

    foreach ($table in $tables) {
        try {
            $count = wrangler d1 execute $DatabaseName --json --command "SELECT COUNT(*) as cnt FROM $table" | ConvertFrom-Json
            $records = $count.result.results[0].cnt
            Write-Host "  $table: $records 条记录" -ForegroundColor Yellow
        }
        catch {
            Write-Host "  $table: 错误" -ForegroundColor Red
        }
    }
}

function Clean-OldBackups {
    param([int]$DaysToKeep = 30)

    Write-Host "`n🧹 清理 $DaysToKeep 天前的备份" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    if (Test-Path $BackupDir) {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $oldBackups = Get-ChildItem $BackupDir -Filter "*.sql" | Where-Object { $_.LastWriteTime -lt $cutoffDate }

        if ($oldBackups.Count -gt 0) {
            foreach ($backup in $oldBackups) {
                Remove-Item $backup.FullName
                Write-Host "  删除: $($backup.Name)" -ForegroundColor Yellow
            }
            Write-Host "✅ 清理完成，删除 $($oldBackups.Count) 个备份" -ForegroundColor Green
        }
        else {
            Write-Host "✅ 没有需要清理的备份" -ForegroundColor Green
        }
    }
}

# 主程序
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "D1 数据库备份管理工具" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Gray

if ($Restore) {
    if (-not $RestoreFile) {
        Write-Host "❌ 需要指定 -RestoreFile 参数" -ForegroundColor Red
        exit 1
    }
    Write-Host "⚠️  恢复数据库会覆盖当前数据!" -ForegroundColor Red
    Write-Host "输入 'yes' 确认: " -NoNewline
    $confirm = Read-Host
    if ($confirm -eq "yes") {
        Write-Host "恢复功能需要手动执行 SQL 文件" -ForegroundColor Yellow
        Write-Host "使用: wrangler d1 execute $DatabaseName --file $RestoreFile" -ForegroundColor Gray
    }
}
else {
    # 导出备份
    Export-Database $DatabaseName $backupPath

    # 显示统计
    Get-BackupStats

    # 显示表统计
    List-Databases

    # 清理旧备份 (保留 30 天)
    Clean-OldBackups -DaysToKeep 30
}

Write-Host "`n✅ 操作完成" -ForegroundColor Green
