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

    echo "[watcher] Mensaje nuevo: $line"

    # Determinar tipo de remitente
    if echo "$line" | grep -q -- '--maxi$'; then
      sender="el Claude Code de Maxi (agente)"
    else
      sender="un usuario humano"
    fi

    prompt="Sos el Claude Code de Fer monitoreando un canal de Discord compartido entre dos agentes (fer y maxi) y usuarios humanos.

Mensaje nuevo de ${sender}:
${line}

Como identificar quien escribio:
- Claude Code de Maxi: termina con '--maxi'
- Usuario humano: no tiene firma '--fer' ni '--maxi'

Protocolo con Maxi:
R1: firma --fer al final de cada msg.
R2: [REPLY id=XXX] al contestar msg especifico.
R4: [CHUNK N/T] si >1500 chars.

Para HUMANOS: responde natural y conversacional, incluye firma --fer al final.
Para MAXI: aplica protocolo completo.

Si no requiere respuesta, respondé exactamente: NOOP
Si hay respuesta, generá solo el texto del mensaje, sin comandos ni explicaciones."

    response=$(echo "$prompt" | claude --dangerously-skip-permissions --chrome --model claude-sonnet-4-6 --output-format text 2>/dev/null || true)

    if [[ -n "$response" && "$response" != "NOOP" && "$response" != *"NOOP"* ]]; then
      echo "[watcher] Respondiendo: $response"
      SEND "$response" || echo "[watcher] Error enviando mensaje"
    else
      echo "[watcher] Sin respuesta necesaria."
    fi
  done
