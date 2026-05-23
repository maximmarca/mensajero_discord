#!/usr/bin/env bash
# watcher.sh - Monitorea el canal de Discord y responde via Claude Code CLI

set -euo pipefail

DISCORD_TOKEN="${DISCORD_BOT_TOKEN:-}"
DISCORD_CHANNEL="${DISCORD_CHANNEL_ID:-}"
POLL_INTERVAL=30
STATE_FILE="$(dirname "$0")/.last_seen_id"
BINARY="$(dirname "$0")/mensajero_discord"

while [[ $# -gt 0 ]]; do
  case $1 in
    --token)    DISCORD_TOKEN="$2"; shift 2 ;;
    --channel)  DISCORD_CHANNEL="$2"; shift 2 ;;
    --interval) POLL_INTERVAL="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1"; exit 1 ;;
  esac
done

if [[ -z "$DISCORD_TOKEN" || -z "$DISCORD_CHANNEL" ]]; then
  echo "Uso: $0 --token TOKEN --channel CHANNEL_ID [--interval SEGUNDOS]"
  echo "  o configurar DISCORD_BOT_TOKEN y DISCORD_CHANNEL_ID como env vars"
  exit 1
fi

SEND() {
  "$BINARY" --token "$DISCORD_TOKEN" --channel "$DISCORD_CHANNEL" send "$1"
}

echo "[watcher] Iniciado. Polling cada ${POLL_INTERVAL}s. State: ${STATE_FILE}"

# Usar el subcomando nativo watch (sin --filter para recibir todos los mensajes)
"$BINARY" --token "$DISCORD_TOKEN" --channel "$DISCORD_CHANNEL" \
  watch --interval "$POLL_INTERVAL" --state "$STATE_FILE" \
  | while IFS= read -r line; do

    # Ignorar mensajes propios (firmados --fer)
    if echo "$line" | grep -q -- '--fer$'; then
      continue
    fi

    # Extraer contenido: formato es "[HH:MM:SS] username (id:XXXX): contenido"
    content=$(echo "$line" | sed 's/^\[[0-9:]*\] [^(]*(id:[0-9]*): //')

    echo "[watcher] Mensaje nuevo de $(echo "$line" | grep -oP '^\[[0-9:]*\] \K[^(]+' | tr -d ' '): '${content}'"

    # Saltar si el contenido está vacío
    if [[ -z "${content// /}" ]]; then
      echo "[watcher] Contenido vacío, ignorando."
      continue
    fi

    # Determinar tipo de remitente
    if echo "$content" | grep -q -- '--maxi$'; then
      sender="el Claude Code de Maxi (agente)"
    else
      sender="un usuario humano"
    fi

    prompt="Sos el Claude Code de Fer en un canal de Discord compartido entre dos agentes (fer y maxi) y usuarios humanos.

Mensaje nuevo de ${sender}: ${content}

Reglas:
- Si es de MAXI (termina con '--maxi'): aplica protocolo [TAG] ... --fer con [REPLY id=XXX] si corresponde.
- Si es de un HUMANO: respondé de forma natural y conversacional. Siempre incluí --fer al final.
- Si el mensaje no requiere respuesta (ej: es solo informativo y no hay nada util que agregar), respondé exactamente: NOOP

Generá solo el texto del mensaje a enviar, sin explicaciones."

    response=$(echo "$prompt" | claude --dangerously-skip-permissions --chrome --model claude-sonnet-4-6 --output-format text 2>/dev/null || true)

    # Eliminar líneas que sean exactamente NOOP o que solo contengan NOOP
    clean_response=$(echo "$response" | grep -v '^NOOP$' || true)

    if [[ -n "${clean_response// /}" ]]; then
      echo "[watcher] Respondiendo: $clean_response"
      SEND "$clean_response" || echo "[watcher] Error enviando mensaje"
    else
      echo "[watcher] Sin respuesta necesaria."
    fi
  done
