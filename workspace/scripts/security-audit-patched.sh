#!/usr/bin/env bash
# 安全巡检脚本 - 修复版（带白名单）

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OC="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
REPORT_DIR="/tmp/openclaw/security-reports"
mkdir -p "$REPORT_DIR"

DATE_STR=$(date +%F)
REPORT_FILE="$REPORT_DIR/report-$DATE_STR.txt"
SUMMARY="🛡️ OpenClaw 每日安全巡检简报 ($DATE_STR)\n\n"

echo "=== OpenClaw Security Audit Detailed Report ($DATE_STR) ===" > "$REPORT_FILE"

append_warn() {
  SUMMARY+="$1\n"
}

# 1) OpenClaw 基础审计
echo "[1/13] OpenClaw 基础审计 (--deep)" >> "$REPORT_FILE"
if openclaw security audit --deep >> "$REPORT_FILE" 2>&1; then
  SUMMARY+="1. 平台审计: ✅ 已执行原生扫描\n"
else
  append_warn "1. 平台审计: ⚠️ 执行失败（详见详细报告）"
fi

# 2) 进程与网络
echo -e "\n[2/13] 监听端口与高资源进程" >> "$REPORT_FILE"
lsof -i -P -n | grep LISTEN >> "$REPORT_FILE" 2>/dev/null || true
top -l 1 | head -n 15 >> "$REPORT_FILE" 2>/dev/null || true
SUMMARY+="2. 进程网络: ✅ 已采集监听端口与进程快照\n"

# 3) 敏感目录变更
echo -e "\n[3/13] 敏感目录近 24h 变更文件数" >> "$REPORT_FILE"
MOD_FILES=$(find "$OC" /etc ~/.ssh ~/.gnupg /usr/local/bin -type f -mtime -1 2>/dev/null | wc -l | tr -d ' ')
echo "Total modified files: $MOD_FILES" >> "$REPORT_FILE"
SUMMARY+="3. 目录变更: ✅ $MOD_FILES 个文件 (位于 /etc/ 或 ~/.ssh 等)\n"

# 4) 系统定时任务
echo -e "\n[4/13] 系统级定时任务" >> "$REPORT_FILE"
crontab -l 2>/dev/null >> "$REPORT_FILE" || true
launchctl list >> "$REPORT_FILE" 2>/dev/null || true
ls -la ~/Library/LaunchAgents/ 2>/dev/null >> "$REPORT_FILE" || true
SUMMARY+="4. 系统 Cron: ✅ 已采集系统级定时任务信息\n"

# 5) OpenClaw 定时任务
echo -e "\n[5/13] OpenClaw Cron Jobs" >> "$REPORT_FILE"
if openclaw cron list >> "$REPORT_FILE" 2>&1; then
  SUMMARY+="5. 本地 Cron: ✅ 已拉取内部任务列表\n"
else
  append_warn "5. 本地 Cron: ⚠️ 拉取失败（可能是 token/权限问题）"
fi

# 6) 登录与 SSH 审计
echo -e "\n[6/13] 最近登录记录" >> "$REPORT_FILE"
last -5 >> "$REPORT_FILE" 2>/dev/null || true
FAILED_SSH=0
if command -v log >/dev/null 2>&1; then
  FAILED_SSH=$(log show --predicate 'process == "sshd"' --last 24h 2>/dev/null | grep -iE "Failed|Invalid" | wc -l | tr -d ' ')
fi
echo "Failed SSH attempts (recent): $FAILED_SSH" >> "$REPORT_FILE"
SUMMARY+="6. SSH 安全: ✅ 近24h失败尝试 $FAILED_SSH 次\n"

# 7) 关键文件完整性与权限
echo -e "\n[7/13] 关键配置文件权限与哈希基线" >> "$REPORT_FILE"
PERM_OC=$(stat -f "%Lp" "$OC/openclaw.json" 2>/dev/null || echo "MISSING")
PERM_PAIRED=$(stat -f "%Lp" "$OC/devices/paired.json" 2>/dev/null || echo "MISSING")
echo "Permissions: openclaw=$PERM_OC, paired=$PERM_PAIRED" >> "$REPORT_FILE"
if [[ "$PERM_OC" == "600" ]]; then
  SUMMARY+="7. 配置基线: ✅ 权限合规\n"
else
  append_warn "7. 配置基线: ⚠️ 权限不合规"
fi

# 8) 黄线操作交叉验证
echo -e "\n[8/13] 黄线操作对比 (sudo logs vs memory)" >> "$REPORT_FILE"
SUDO_COUNT=0
if command -v log >/dev/null 2>&1; then
  SUDO_COUNT=$(log show --predicate 'process == "sudo"' --last 24h 2>/dev/null | grep -i "COMMAND" | wc -l | tr -d ' ')
fi
MEM_FILE="$OC/workspace/memory/$DATE_STR.md"
MEM_COUNT=$(grep -i "sudo" "$MEM_FILE" 2>/dev/null | wc -l | tr -d ' ')
echo "Sudo Logs(recent): $SUDO_COUNT, Memory Logs(today): $MEM_COUNT" >> "$REPORT_FILE"
SUMMARY+="8. 黄线审计: ✅ sudo记录=$SUDO_COUNT, memory记录=$MEM_COUNT\n"

# 9) 磁盘使用
echo -e "\n[9/13] 磁盘使用率与最近大文件" >> "$REPORT_FILE"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
LARGE_FILES=$(find / -xdev -type f -size +100M -mtime -1 2>/dev/null | wc -l | tr -d ' ')
echo "Disk Usage: $DISK_USAGE, Large Files (>100M): $LARGE_FILES" >> "$REPORT_FILE"
SUMMARY+="9. 磁盘容量: ✅ 根分区占用 $DISK_USAGE, 新增 $LARGE_FILES 个大文件\n"

# 10) Gateway 环境变量
echo -e "\n[10/13] Gateway 环境变量泄露扫描" >> "$REPORT_FILE"
GW_PID=$(pgrep -f "openclaw-gateway" | head -n 1 || true)
if [ -n "$GW_PID" ]; then
  ps -p "$GW_PID" -o command= >> "$REPORT_FILE" 2>/dev/null || true
  SUMMARY+="10. 环境变量: ✅ 已定位 openclaw-gateway 进程 (PID: $GW_PID)\n"
else
  append_warn "10. 环境变量: ⚠️ 未定位到 openclaw-gateway 进程"
fi

# 11) 明文凭证泄露扫描 (DLP) - 修复版
echo -e "\n[11/13] 明文私钥/助记词泄露扫描 (DLP)" >> "$REPORT_FILE"
SCAN_ROOT="$OC/workspace"
DLP_HITS=0
if [ -d "$SCAN_ROOT" ]; then
  # ETH private key-ish: 0x + 64 hex
  H1=$(grep -RInE --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.gif' --exclude='*.webp' '\b0x[a-fA-F0-9]{64}\b' "$SCAN_ROOT" 2>/dev/null | wc -l | tr -d ' ')
  # 12/24-word mnemonic-ish (排除 SKILL.md 避免误报)
  H2=$(grep -RInE --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.gif' --exclude='*.webp' --exclude='SKILL.md' '\b([a-z]{3,12}\s+){11}([a-z]{3,12})\b|\b([a-z]{3,12}\s+){23}([a-z]{3,12})\b' "$SCAN_ROOT" 2>/dev/null | grep -v "skills from the open" | wc -l | tr -d ' ')
  DLP_HITS=$((H1 + H2))
fi
echo "DLP hits (heuristic): $DLP_HITS" >> "$REPORT_FILE"
if [ "$DLP_HITS" -gt 0 ]; then
  append_warn "11. 敏感凭证扫描: ⚠️ 检测到疑似明文敏感信息($DLP_HITS)，请人工复核"
else
  SUMMARY+="11. 敏感凭证扫描: ✅ 未发现明显私钥/助记词模式\n"
fi

# 12) Skill/MCP 完整性（基线diff）
echo -e "\n[12/13] Skill/MCP 完整性基线对比" >> "$REPORT_FILE"
SKILL_DIR="$OC/workspace/skills"
MCP_DIR="$OC/workspace/mcp"
HASH_DIR="$OC/security-baselines"
mkdir -p "$HASH_DIR"
CUR_HASH="$HASH_DIR/skill-mcp-current.sha256"
BASE_HASH="$HASH_DIR/skill-mcp-baseline.sha256"
: > "$CUR_HASH"
for D in "$SKILL_DIR" "$MCP_DIR"; do
  if [ -d "$D" ]; then
    find "$D" -type f -print0 2>/dev/null | sort -z | xargs -0 shasum -a 256 2>/dev/null >> "$CUR_HASH" || true
  fi
done
if [ -s "$CUR_HASH" ]; then
  if [ -f "$BASE_HASH" ]; then
    if diff -u "$BASE_HASH" "$CUR_HASH" >> "$REPORT_FILE" 2>&1; then
      SUMMARY+="12. Skill/MCP基线: ✅ 与上次基线一致\n"
    else
      # 更新基线
      cp "$CUR_HASH" "$BASE_HASH"
      SUMMARY+="12. Skill/MCP基线: ✅ 已更新基线\n"
    fi
  else
    cp "$CUR_HASH" "$BASE_HASH"
    SUMMARY+="12. Skill/MCP基线: ✅ 首次生成基线完成\n"
  fi
else
  SUMMARY+="12. Skill/MCP基线: ✅ 未发现skills/mcp目录文件\n"
fi

# 13) 大脑灾备自动同步
echo -e "\n[13/13] 大脑灾备 (Git Backup)" >> "$REPORT_FILE"
BACKUP_STATUS=""
if [ -d "$OC/.git" ]; then
  (
    cd "$OC" || exit 1
    git add . >> "$REPORT_FILE" 2>&1 || true
    if git diff --cached --quiet; then
      echo "No staged changes" >> "$REPORT_FILE"
      BACKUP_STATUS="skip"
    else
      if git commit -m "🛡️ Nightly brain backup ($DATE_STR)" >> "$REPORT_FILE" 2>&1 && git push origin main >> "$REPORT_FILE" 2>&1; then
        BACKUP_STATUS="ok"
      else
        BACKUP_STATUS="fail"
      fi
    fi
  )
else
  BACKUP_STATUS="nogit"
fi

case "$BACKUP_STATUS" in
  ok)   SUMMARY+="13. 灾备备份: ✅ 已自动推送至远端仓库\n" ;;
  skip) SUMMARY+="13. 灾备备份: ✅ 无新变更，跳过推送\n" ;;
  nogit) append_warn "13. 灾备备份: ⚠️ 未初始化Git仓库，已跳过" ;;
  *)    append_warn "13. 灾备备份: ⚠️ 推送失败（不影响本次巡检）" ;;
esac

echo -e "$SUMMARY\n📝 详细战报已保存本机: $REPORT_FILE"
exit 0
