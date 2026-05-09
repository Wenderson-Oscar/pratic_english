#!/bin/bash
set -euo pipefail

APP_NAME="PraticEnglish"
BUNDLE="${APP_NAME}.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT"

echo "▸ Compilando (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

# (Re)gera o ícone se faltar, ou se a fonte for mais recente.
if [ ! -f "App/Icon.icns" ] || [ "tools/make-icon.swift" -nt "App/Icon.icns" ]; then
    echo "▸ Gerando ícone..."
    ./tools/build-icon.sh
fi

echo "▸ Empacotando ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "App/Info.plist" "${BUNDLE}/Contents/Info.plist"
cp "App/Icon.icns" "${BUNDLE}/Contents/Resources/Icon.icns"

# Assinatura ad-hoc para que o macOS aceite a app sem Gatekeeper bloquear.
# (--deep é deprecated; assinamos o binário e depois o bundle.)
codesign --force --sign - "${BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || true
codesign --force --sign - "${BUNDLE}" >/dev/null 2>&1 || true

echo "✅ Pronto: ${BUNDLE}"
echo
echo "Para executar:"
echo "  open ${BUNDLE}"
echo
echo "Na 1ª execução, conceda permissão em:"
echo "  Ajustes do Sistema → Privacidade e Segurança → Acessibilidade"
echo "  → marque ${APP_NAME}"
