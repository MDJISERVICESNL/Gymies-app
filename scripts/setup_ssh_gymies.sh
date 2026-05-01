#!/usr/bin/env bash
# SSH-sleutel "Gymies" aanmaken en (optioneel) public key naar server kopiëren.
# Gebruik: ./scripts/setup_ssh_gymies.sh

set -e

KEY_PATH="${HOME}/.ssh/Gymies"
KEY_PUB="${KEY_PATH}.pub"
SERVER="${GYMIES_SERVER:-gymies}"

echo "=== SSH-sleutel Gymies aanmaken ==="
echo ""

if [[ -f "$KEY_PATH" ]]; then
  echo "De sleutel bestaat al: $KEY_PATH"
  echo "Om opnieuw aan te maken, verwijder eerst: rm $KEY_PATH $KEY_PUB"
  echo ""
else
  echo "Genereer key in $KEY_PATH ..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "gymies-deploy"
  echo "Key aangemaakt."
  echo ""
fi

echo "Public key (deze moet op de server staan):"
echo "---"
cat "$KEY_PUB"
echo "---"
echo ""
echo "Kopieer de key naar de server (je wordt om het wachtwoord van $SERVER gevraagd):"
echo "  ssh-copy-id -i $KEY_PUB $SERVER"
echo ""
echo "Daarna kun je inloggen zonder wachtwoord:"
echo "  ssh -i $KEY_PATH $SERVER"
echo ""
