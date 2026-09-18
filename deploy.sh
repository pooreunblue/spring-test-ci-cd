#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🚀 [CD] Blue/Green 무중단 배포 시작: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

cd ~/

# 1. service-url.inc 점검 및 현재 활성 포트 감지
if [ ! -f ~/service-url.inc ]; then
  echo "proxy_pass http://app-blue:8080;" > ~/service-url.inc
fi

CURRENT_URL=$(cat ~/service-url.inc)

if echo "$CURRENT_URL" | grep -q "app-blue"; then
  CURRENT_SERVICE="app-blue"
  CURRENT_PORT=8081
  TARGET_SERVICE="app-green"
  TARGET_PORT=8082
else
  CURRENT_SERVICE="app-green"
  CURRENT_PORT=8082
  TARGET_SERVICE="app-blue"
  TARGET_PORT=8081
fi

echo "현재 활성 서비스: $CURRENT_SERVICE (포트: $CURRENT_PORT)"
echo "신규 배포 대상: $TARGET_SERVICE (포트: $TARGET_PORT)"

# 2. 신규 배포 대상 최신 이미지 Pull
echo "📥 1. GHCR 최신 이미지 다운로드 중..."
sudo docker compose pull "$TARGET_SERVICE"

# 3. 비활성 컨테이너 기동
echo "🔄 2. 신규 컨테이너($TARGET_SERVICE) 백그라운드 기동 중..."
sudo docker compose up -d "$TARGET_SERVICE"

# 4. 신규 컨테이너 헬스체크 폴링 (최대 10회, 3초 간격)
echo "🔍 3. 신규 컨테이너 헬스체크 시작 (http://localhost:$TARGET_PORT/actuator/health)..."
HEALTH_CHECK_SUCCESS=false

for i in $(seq 1 10); do
  echo "헬스체크 시도 ($i/10)..."
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$TARGET_PORT/" || true)
  if [ "$STATUS_CODE" -eq 200 ]; then
    echo "✅ 헬스체크 통과! (HTTP status: $STATUS_CODE)"
    HEALTH_CHECK_SUCCESS=true
    break
  fi
  sleep 3
done

if [ "$HEALTH_CHECK_SUCCESS" = false ]; then
  echo "🚨 헬스체크 실패! 신규 컨테이너($TARGET_SERVICE)를 즉시 중단하고 롤백합니다."
  sudo docker compose stop "$TARGET_SERVICE"
  exit 1
fi

# 5. Nginx 프록시 대상 스위칭 및 무중단 리로드
echo "🔀 4. Nginx 프록시 대상 전환 -> $TARGET_SERVICE"
echo "proxy_pass http://$TARGET_SERVICE:8080;" > ~/service-url.inc
sudo docker exec nginx-proxy nginx -s reload

# 6. 이전 컨테이너 중지
echo "🛑 5. 이전 컨테이너($CURRENT_SERVICE) 안전 중단..."
sudo docker compose stop "$CURRENT_SERVICE"

# 7. 불필요한 구버전 미태그(Dangling) 이미지 정리
echo "🧹 6. 불필요한 구버전 이미지 정리 중..."
sudo docker image prune -f

echo "=================================================="
echo "✅ [CD] Blue/Green 배포 완료: $TARGET_SERVICE로 전환 완료"
echo "=================================================="