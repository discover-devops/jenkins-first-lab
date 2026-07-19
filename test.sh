cat > test.sh <<'EOF'
#!/usr/bin/env bash
set -e

FILE="build/index.html"

echo "Running pre-deployment checks on $FILE"

if [ ! -f "$FILE" ]; then
  echo "FAIL: build output not found"
  exit 1
fi

if grep -q "__" "$FILE"; then
  echo "FAIL: unreplaced placeholder tokens remain"
  grep -n "__" "$FILE"
  exit 1
fi

if ! grep -q "Deployed by Jenkins" "$FILE"; then
  echo "FAIL: expected heading missing"
  exit 1
fi

echo "PASS: all checks green"
EOF
