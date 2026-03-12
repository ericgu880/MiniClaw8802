#!/usr/bin/env bash
# 安全巡检 + Telegram 通知 Wrapper

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-8369187343}"

# 先运行原巡检脚本
/Users/guruocen/.openclaw/workspace/scripts/nightly-security-audit.sh >> /tmp/openclaw/audit-cron.log 2>&1

# 获取今天的报告
DATE_STR=$(date +%F)
REPORT_FILE="/tmp/openclaw/security-reports/report-$DATE_STR.txt"

# 提取简报部分（前 20 行左右是简报）
SUMMARY=$(head -20 "$REPORT_FILE" 2>/dev/null | grep -v "^===")

# 发送到 Telegram
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=$SUMMARY" \
    -d "parse_mode=Markdown" \
    --max-time 30 > /dev/null 2>&1
fi
