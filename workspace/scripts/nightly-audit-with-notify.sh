#!/usr/bin/env bash
# 安全巡检 + Telegram 通知 Wrapper

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
TELEGRAM_BOT_TOKEN="8669875133:AAFwD1yebdomJr8PEZp3ijMlSHzSzosqpOw"
TELEGRAM_CHAT_ID="8369187343"

DATE_STR=$(date +%F)
REPORT_FILE="/tmp/openclaw/security-reports/report-$DATE_STR.txt"
LOG_FILE="/tmp/openclaw/audit-cron.log"

# 运行巡检脚本（后台运行，超时 5 分钟）
timeout 300 /Users/guruocen/.openclaw/workspace/scripts/nightly-security-audit.sh >> "$LOG_FILE" 2>&1
AUDIT_EXIT=$?

# 等待报告生成
sleep 2

# 提取简报（从日志中提取）
SUMMARY=$(grep -A 15 "🛡️ OpenClaw 每日安全巡检简报" "$LOG_FILE" 2>/dev/null | tail -15)

# 如果没找到简报，生成一个简化的
if [ -z "$SUMMARY" ]; then
  SUMMARY="🛡️ OpenClaw 每日安全巡检简报 ($DATE_STR)

巡检已执行，详细报告:
$REPORT_FILE

状态码: $AUDIT_EXIT"
fi

# 发送到 Telegram
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${SUMMARY}" \
    --max-time 30 > /dev/null 2>&1
fi
