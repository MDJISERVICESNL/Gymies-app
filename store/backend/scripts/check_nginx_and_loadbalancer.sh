#!/usr/bin/env bash
# Controleer Nginx-config en load balancer setup.
# Run op de server: sudo bash scripts/check_nginx_and_loadbalancer.sh

echo "=== 1. Load balancer / proxy check ==="
echo ""

if command -v haproxy &>/dev/null; then
  echo "[HAProxy] Geïnstalleerd"
  for cfg in /etc/haproxy/haproxy.cfg /etc/haproxy.cfg; do
    [[ -f "$cfg" ]] && echo "  Config: $cfg" && grep -E "backend|server |listen " "$cfg" 2>/dev/null | head -15
  done
else
  echo "[HAProxy] Niet geïnstalleerd"
fi

echo ""
echo "[Nginx upstreams (load balancing)]"
grep -rh "upstream\|proxy_pass" /etc/nginx/ 2>/dev/null | grep -v "\.default" | sort -u | head -20 || echo "  Geen gevonden"

echo ""
echo "[Aantal Nginx workers]"
ps aux | grep nginx | grep -v grep | wc -l

echo ""
echo "=== 2. Nginx configs met gymies/var/www ==="
echo ""

for cfg in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
  [[ ! -f "$cfg" ]] && continue
  if grep -q "gymies\|/var/www" "$cfg" 2>/dev/null; then
    echo ">>> $cfg <<<"
    if grep -q "HTTP_AUTHORIZATION\|HTTP_X_GYMIES" "$cfg" 2>/dev/null; then
      echo "  [OK] Auth headers aanwezig"
      grep -n "fastcgi_param HTTP_AUTHORIZATION\|fastcgi_param HTTP_X_GYMIES\|include fastcgi_params" "$cfg" 2>/dev/null
    else
      echo "  [!!] GEEN auth headers"
    fi
    echo ""
    echo "  Location blocks:"
    grep -n "location " "$cfg" 2>/dev/null | head -15
    echo ""
  fi
done

echo "=== 3. Welke location verwerkt PHP (index.php)? ==="
echo ""

for cfg in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
  [[ ! -f "$cfg" ]] && continue
  if grep -q "\.php\|index\.php\|fastcgi" "$cfg" 2>/dev/null; then
    echo "--- $cfg ---"
    # Toon location + fastcgi block
    grep -n "location\|fastcgi_param\|include fastcgi" "$cfg" 2>/dev/null
    echo ""
  fi
done

echo "=== 4. Test: waar staat HTTP_AUTHORIZATION? ==="
echo ""
grep -rn "HTTP_AUTHORIZATION\|http_authorization" /etc/nginx/ 2>/dev/null || echo "Nergens gevonden"
