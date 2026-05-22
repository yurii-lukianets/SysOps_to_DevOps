#!/bin/bash
# =============================================================
# LLM API Test Suite
# Usage: API_KEY=your-key ./test_api.sh [base_url]
# =============================================================

BASE_URL="${1:-https://llm.ai-devops.pp.ua}"
KEY="${API_KEY:-}"
PASS=0; FAIL=0

run_test() {
  local name="$1"; local result="$2"; local expect="$3"
  if echo "$result" | grep -q "$expect"; then
    echo "✅ PASS: $name"; ((PASS++))
  else
    echo "❌ FAIL: $name"; echo "   Got: $(echo $result | head -c 100)"; ((FAIL++))
  fi
}

echo "================================================"
echo "  LLM API Test Suite"
echo "  Target: $BASE_URL"
echo "================================================"

# Test 1: Health (public)
r=$(curl -s "$BASE_URL/health")
run_test "Health endpoint (public)" "$r" "ok"

# Test 2: Auth required
r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/chat" \
  -H "Content-Type: application/json" \
  -d '{"message":"test","max_tokens":10}')
run_test "Auth required without key (expect 403)" "$r" "403"

# Test 3: Auth works
r=$(curl -s -X POST "$BASE_URL/v1/chat" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $KEY" \
  -d '{"message":"Reply with one word: OK","max_tokens":20}')
run_test "Auth with valid key (expect choices)" "$r" "choices"

# Test 4: Models endpoint
r=$(curl -s "$BASE_URL/v1/models" -H "X-API-Key: $KEY")
run_test "Models endpoint" "$r" "Qwen"

# Test 5: LLM responds correctly
r=$(curl -s -X POST "$BASE_URL/v1/chat" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $KEY" \
  -d '{"message":"What is 2+2? Reply with number only.","max_tokens":10}')
run_test "LLM basic reasoning" "$r" "choices"

# Test 6: OpenAI-compatible endpoint
r=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $KEY" \
  -d '{"model":"qwen3","messages":[{"role":"user","content":"Say hello"}],"max_tokens":20}')
run_test "OpenAI-compatible endpoint" "$r" "choices"

echo "================================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================================"
