#!/bin/bash
# Builds fictional demo repositories and renders docs/screenshot.png from them,
# so the README never shows real repos, commits or people.
#   ./scripts/make_showcase.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
D="$HOME/Project/showcase"   # under ~ so paths render as ~/Project/showcase
rm -rf "$D"; mkdir -p "$D"; cd "$D"
trap 'rm -rf "$D"' EXIT

commit() { git -c user.name="$1" -c user.email="$2" commit -qm "$3" --date="$4"; }
ALEX=("Alex Chen" alex@example.com); SAM=("Sam Rivera" sam@example.com); MAYA=("Maya Putri" maya@example.com)

for r in api-server web-dashboard mobile-app docs-site; do
  git init -q --bare -b main "$r.git"; git clone -q "$r.git" "$r" 2>/dev/null
done

cd api-server
mkdir -p internal/booking internal/payment cmd
echo 'package main' > cmd/main.go; git add .; commit "${ALEX[@]}" "chore: initial service layout" "10 days ago"
for m in "feat(booking): create reservation endpoint" "feat(booking): validate party size" "fix(booking): reject past dates"; do
  echo "// $m" >> internal/booking/handler.go; git add .; commit "${SAM[@]}" "$m" "8 days ago"
done
git push -q -u origin main
git switch -q -c feature/payments
for m in "feat(payment): add provider interface" "feat(payment): webhook signature check" "test(payment): cover refunds"; do
  echo "// $m" >> internal/payment/service.go; git add .; commit "${MAYA[@]}" "$m" "5 days ago"
done
git push -q -u origin feature/payments
git switch -q main
echo "// cache" >> internal/booking/cache.go; git add .; commit "${ALEX[@]}" "perf(booking): cache availability lookups" "4 days ago"
T3="@$(date -v-3d +%s) +0800"; GIT_AUTHOR_DATE="$T3" GIT_COMMITTER_DATE="$T3" \
  git -c user.name="Alex Chen" -c user.email=alex@example.com merge -q --no-ff feature/payments -m "Merge branch 'feature/payments'"
echo "// limits" >> internal/booking/handler.go; git add .; commit "${SAM[@]}" "feat(booking): rate limit public endpoints" "2 days ago"
git push -q origin main
echo "// retry" >> internal/payment/service.go; git add .; commit "${MAYA[@]}" "fix(payment): retry idempotent webhook delivery" "3 hours ago"
echo "// wip" >> internal/booking/handler.go; echo 'package booking' > internal/booking/handler_test.go

cd ../web-dashboard; echo a > index.ts; git add .; commit "${SAM[@]}" "init" "6 days ago"; git push -q -u origin main
cd ../mobile-app; echo a > App.tsx; git add .; commit "${MAYA[@]}" "init" "6 days ago"; git push -q -u origin main
git switch -q -c develop; echo b >> App.tsx; git add .; commit "${MAYA[@]}" "feat: onboarding" "1 day ago"
cd ../docs-site; echo a > README.md; git add .; commit "${ALEX[@]}" "init" "6 days ago"; git push -q -u origin main; echo b > guide.md
cd "$D"; rm -rf ./*.git

cd "$ROOT"
swift build -c release >/dev/null
mkdir -p docs
GAB_RENDER_TAB=history GAB_RENDER_WIDTH=1440 GAB_LANG=en GAB_ROOTS="$D" GAB_RENDER_REPO=api-server \
  GAB_RENDER="$ROOT/docs/screenshot.png" .build/release/GitAppBar &
PID=$!
sleep 14
kill $PID 2>/dev/null || true
echo "✅ docs/screenshot.png"
