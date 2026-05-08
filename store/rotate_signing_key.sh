#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# GYMIES: Roteer Android signing key
# ═══════════════════════════════════════════════════════════════
#
# WANNEER UITVOEREN:
#   Als je de huidige key.properties + .jks wilt vervangen
#   door een nieuwe, veiligere combinatie.
#
# NA HET UITVOEREN:
#   1. Upload de nieuwe key naar Google Play Console:
#      Play Console → App → Setup → App signing → Upload new key
#   2. Sla het wachtwoord op in een password manager
#   3. Verwijder dit script (bevat het wachtwoord tijdelijk)
#
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "$0")/../android" && pwd)"
NEW_PASSWORD="Wm2s5Q7WNKnY8dEvA2Gn8vTMEA7NFpnCAlnFxQ"
NEW_ALIAS="gymies-upload-v2"
NEW_KEYSTORE="gymies-upload-v2.jks"

echo ""
echo "═══ GYMIES Signing Key Rotatie ═══"
echo ""

# Stap 1: Genereer nieuwe keystore
echo "1. Nieuwe keystore genereren..."
keytool -genkey -v \
    -keystore "$ANDROID_DIR/$NEW_KEYSTORE" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 10950 \
    -alias "$NEW_ALIAS" \
    -storepass "$NEW_PASSWORD" \
    -keypass "$NEW_PASSWORD" \
    -dname "CN=Gymies Development, OU=Engineering, O=MDJI Services, L=Netherlands, C=NL"

echo "   ✓ Keystore aangemaakt: $ANDROID_DIR/$NEW_KEYSTORE"

# Stap 2: Update key.properties
echo ""
echo "2. key.properties bijwerken..."
cat > "$ANDROID_DIR/key.properties" << EOF
storePassword=$NEW_PASSWORD
keyPassword=$NEW_PASSWORD
keyAlias=$NEW_ALIAS
storeFile=../$NEW_KEYSTORE
EOF
chmod 600 "$ANDROID_DIR/key.properties"
echo "   ✓ key.properties bijgewerkt (chmod 600)"

# Stap 3: Verifieer
echo ""
echo "3. Verificatie..."
keytool -list -keystore "$ANDROID_DIR/$NEW_KEYSTORE" -storepass "$NEW_PASSWORD" -alias "$NEW_ALIAS" 2>/dev/null | head -5
echo "   ✓ Keystore is geldig"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Signing key geroteerd!"
echo ""
echo "  VOLGENDE STAPPEN:"
echo "  1. Sla wachtwoord op in password manager:"
echo "     $NEW_PASSWORD"
echo ""
echo "  2. Upload naar Google Play Console:"
echo "     Play Console → GYMIES → Setup → App signing"
echo "     → 'Request upload key reset'"
echo ""
echo "  3. Test een release build:"
echo "     cd $(dirname "$ANDROID_DIR")"
echo "     flutter build appbundle --release"
echo ""
echo "  4. Verwijder dit script na gebruik!"
echo "     rm $0"
echo "═══════════════════════════════════════════════════════════"
