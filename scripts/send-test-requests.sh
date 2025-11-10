#!/bin/bash

echo "📊 Bookinfo APIへテストリクエストを送信中..."
echo ""

# 成功リクエスト
echo "✅ 成功リクエスト送信中..."
for i in {1..20}; do
  curl -s http://localhost:8000/products > /dev/null && echo "  ✓ GET /products"
  sleep 0.3
done

for i in {1..10}; do
  curl -s http://localhost:8000/products/0 > /dev/null && echo "  ✓ GET /products/0"
  sleep 0.3
done

for i in {1..10}; do
  curl -s http://localhost:8000/products/0/reviews > /dev/null && echo "  ✓ GET /products/0/reviews"
  sleep 0.3
done

for i in {1..10}; do
  curl -s http://localhost:8000/products/0/ratings > /dev/null && echo "  ✓ GET /products/0/ratings"
  sleep 0.3
done

for i in {1..5}; do
  curl -s http://localhost:8000/details/0 > /dev/null && echo "  ✓ GET /details/0"
  sleep 0.3
done

# エラーリクエスト
echo ""
echo "❌ エラーリクエスト送信中..."
for i in {1..10}; do
  curl -s http://localhost:8000/products/999 > /dev/null && echo "  ✗ GET /products/999 (404)"
  sleep 0.3
done

for i in {1..5}; do
  curl -s http://localhost:8000/notfound > /dev/null && echo "  ✗ GET /notfound (404)"
  sleep 0.3
done

echo ""
echo "✅ 完了!"
echo "   - 成功: 55リクエスト (200 OK)"
echo "   - エラー: 15リクエスト (404 Not Found)"
echo "   - 合計: 70リクエスト"
echo ""
echo "📊 Grafanaで確認: http://localhost:3000"
echo ""
echo "推奨クエリ:"
echo "  - sum(rate(kong_http_requests_total[1m])) by (code)"
echo "  - sum(rate(kong_http_requests_total[1m])) by (service)"
echo "  - histogram_quantile(0.95, rate(kong_latency_bucket[1m]))"
