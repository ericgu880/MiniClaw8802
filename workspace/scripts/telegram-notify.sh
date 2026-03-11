#!/usr/bin/env bash
# Telegram 通知脚本 - 用于安全巡检报告推送

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-8369187343}"
MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
  echo "Usage: $0 'message text'"
  exit 1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "Error: TELEGRAM_BOT_TOKEN not set"
  exit 1
fi

# 发送消息
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=${MESSAGE}" \
  -d "parse_mode=Markdown" \
  --max-time 30

echo ""
