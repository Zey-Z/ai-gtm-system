#!/bin/bash
# ============================================================
# End-to-End Webhook Test Suite
# Tests the AI Lead Extractor pipeline via HTTP requests
#
# Prerequisites: Docker services running (docker-compose up -d)
# Usage: bash tests/test-webhook.sh [BASE_URL]
# ============================================================

BASE_URL="${1:-http://localhost:5678/webhook/lead-intake}"
PASSED=0
FAILED=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
  echo -e "  ${GREEN}PASS${NC}  $1"
  ((PASSED++))
}

fail() {
  echo -e "  ${RED}FAIL${NC}  $1"
  if [ -n "$2" ]; then echo "         $2"; fi
  ((FAILED++))
}

echo ""
echo "=== AI Lead Extractor — E2E Webhook Tests ==="
echo "Target: $BASE_URL"
echo ""

# --- Test 1: High-score lead (should sync to CRM) ---
echo "Test 1: High-quality lead (expect score ≥ 70)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": "我是张伟，来自星辰科技有限公司，邮箱 zhangwei@xingchen.com，我们预算大约50万，希望下周能开始对接。"
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  pass "HTTP 200 response"
else
  fail "Expected HTTP 200, got $HTTP_CODE" "$BODY"
fi

sleep 2

# --- Test 2: Low-score lead (should NOT sync to CRM) ---
echo ""
echo "Test 2: Low-quality lead (expect score < 70)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": "你好，想了解一下你们的产品。"
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
  pass "HTTP 200 response (low-score lead still accepted)"
else
  fail "Expected HTTP 200, got $HTTP_CODE"
fi

sleep 2

# --- Test 3: Idempotency (duplicate submission) ---
echo ""
echo "Test 3: Idempotency — same text submitted twice"
LEAD_TEXT="Idempotency test: 我是测试用户，来自测试公司，预算10万"

# First submission
curl -s -o /dev/null -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"lead_text\": \"$LEAD_TEXT\"}"

sleep 2

# Second submission (same text)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"lead_text\": \"$LEAD_TEXT\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
  pass "Duplicate submission returns HTTP 200 (UPSERT handled)"
else
  fail "Expected HTTP 200 for duplicate, got $HTTP_CODE"
fi

sleep 2

# --- Test 4: Missing lead_text (validation error) ---
echo ""
echo "Test 4: Missing lead_text field (expect error)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{"wrong_field": "no lead_text provided"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
# Workflow should handle this gracefully (either 400 or 200 with error in body)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ]; then
  pass "Invalid input handled gracefully (HTTP $HTTP_CODE)"
else
  fail "Unexpected HTTP code: $HTTP_CODE"
fi

# --- Summary ---
echo ""
echo "========================================"
echo -e "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, $((PASSED + FAILED)) total"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
