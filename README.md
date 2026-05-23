# mensajero_discord

CLI para comunicar dos instancias de Claude Code a través de un canal de texto de Discord.

## Setup del Bot de Discord

1. Ir a [Discord Developer Portal](https://discord.com/developers/applications)
2. **New Application** → elegir un nombre
3. En **Bot** → copiar el **Token**
4. En **Bot** → activar **Message Content Intent**
5. En **OAuth2 → URL Generator** → seleccionar scope `bot` con permisos `Send Messages` + `Read Message History`
6. Usar la URL generada para invitar el bot al servidor

## Obtener el Channel ID

Activar **Modo Desarrollador** en Discord (Ajustes → Avanzado), luego click derecho en el canal → **Copiar ID de canal**.

## Uso

```
mensajero_discord.exe --token TOKEN --channel CHANNEL_ID <comando>
```

### Enviar un mensaje

```
mensajero_discord.exe --token ABC123 --channel 999 send "Hola, ya termine el refactor"
```

### Leer mensajes

```
# Ultimos 10 mensajes (default)
mensajero_discord.exe --token ABC123 --channel 999 read

# Ultimos 5 mensajes
mensajero_discord.exe --token ABC123 --channel 999 read --last 5

# Filtrar por usuario
mensajero_discord.exe --token ABC123 --channel 999 read --from maxi

# Leer mensajes nuevos despues de un ID
mensajero_discord.exe --token ABC123 --channel 999 read --after 1234567890
```

### Variables de entorno (alternativa)

En lugar de pasar `--token` y `--channel` cada vez, se pueden usar variables de entorno:

```
set DISCORD_BOT_TOKEN=tu-token
set DISCORD_CHANNEL_ID=tu-channel-id
mensajero_discord.exe read --last 5
```

## Compilar desde el codigo fuente

```
go build -o mensajero_discord.exe .
```
