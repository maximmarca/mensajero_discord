#!/usr/bin/env bash
# watcher.sh - Monitorea el canal de Discord y responde via Claude Code CLI

set -euo pipefail

DISCORD_TOKEN="${DISCORD_BOT_TOKEN:-}"
DISCORD_CHANNEL="${DISCORD_CHANNEL_ID:-}"
POLL_INTERVAL=30
STATE_FILE="$(dirname "$0")/.last_seen_id"
BINARY="$(dirname "$0")/mensajero_discord"

# Permitir pasar token y channel por argumento
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

READ_NEW() {
  local after="${1:-}"
  if [[ -n "$after" ]]; then
    "$BINARY" --token "$DISCORD_TOKEN" --channel "$DISCORD_CHANNEL" read --last 5 --after "$after"
  else
    "$BINARY" --token "$DISCORD_TOKEN" --channel "$DISCORD_CHANNEL" read --last 5
  fi
}

# Recuperar último ID procesado
last_id=""
if [[ -f "$STATE_FILE" ]]; then
  last_id=$(cat "$STATE_FILE")
fi

echo "[watcher] Iniciado. Modelo: claude sonnet (medium). Polling cada ${POLL_INTERVAL}s."
echo "[watcher] Último ID procesado: ${last_id:-ninguno}"

while true; do
  # Leer mensajes nuevos
  messages=$(READ_NEW "$last_id" 2>/dev/null || true)

  if [[ -n "$messages" && "$messages" != "No hay mensajes." ]]; then
    echo "[watcher] Mensajes nuevos:"
    echo "$messages"

    # Extraer el último ID del output (formato: [...] username (id:XXXX): ...)
    new_last_id=$(echo "$messages" | grep -oP '\(id:\K[0-9]+' | tail -1)

    if [[ -n "$new_last_id" && "$new_last_id" != "$last_id" ]]; then
      # Filtrar solo mensajes que NO sean nuestros (firma --fer al final)
      foreign_messages=$(echo "$messages" | grep -v -- '--fer$' || true)

      if [[ -n "$foreign_messages" ]]; then
        # Pasar los mensajes a Claude Code CLI para que responda
        prompt="Sos el Claude Code de Fer monitoreando un canal de Discord compartido entre dos agentes (fer y maxi) y posibles usuarios humanos.

Mensajes nuevos recibidos:
${foreign_messages}

Como identificar quien escribio cada mensaje:
- Mensajes del Claude Code de Maxi: terminan con '--maxi'
- Mensajes de usuarios humanos: no tienen firma '--fer' ni '--maxi'
- Tus propios mensajes (ignorar): terminan con '--fer', ya filtrados

Protocolo activo con el agente maxi:
R1: firma --fer al final de cada msg.
R2: [REPLY id=XXX] al contestar msg especifico.
R3: 30s polling fijo.
R4: [CHUNK N/T] si >1500 chars.
R5: persistir last_seen_id (ya implementado).

Para mensajes de HUMANOS: responde de forma natural y conversacional, sin tags de protocolo, aunque si incluye la firma --fer al final.
Para mensajes de MAXI: aplica el protocolo completo.

Si no hay nada que responder, respondé exactamente: NOOP
Si hay respuesta, generá solo el texto del mensaje a enviar, sin comandos ni explicaciones."

        response=$(echo "$prompt" | claude --dangerously-skip-permissions --chrome --model claude-sonnet-4-6 --output-format text 2>/dev/null || true)

        if [[ -n "$response" && "$response" != "NOOP" && "$response" != *"NOOP"* ]]; then
          echo "[watcher] Respondiendo: $response"
          SEND "$response" || echo "[watcher] Error enviando mensaje"
        else
          echo "[watcher] Sin respuesta necesaria."
        fi
      fi

      last_id="$new_last_id"
      echo "$last_id" > "$STATE_FILE"
    fi
  fi

  sleep "$POLL_INTERVAL"
done
