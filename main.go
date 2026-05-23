package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

const baseURL = "https://discord.com/api/v10"

type Message struct {
	ID        string    `json:"id"`
	Content   string    `json:"content"`
	Author    Author    `json:"author"`
	Timestamp time.Time `json:"timestamp"`
}

type Author struct {
	ID            string `json:"id"`
	Username      string `json:"username"`
	GlobalName    string `json:"global_name"`
	Discriminator string `json:"discriminator"`
}

func sendMessage(token, channelID, content string) error {
	url := fmt.Sprintf("%s/channels/%s/messages", baseURL, channelID)
	body := fmt.Sprintf(`{"content":%s}`, jsonString(content))
	req, err := http.NewRequest("POST", url, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bot "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("discord respondio %d: %s", resp.StatusCode, string(respBody))
	}
	return nil
}

func readMessages(token, channelID string, limit int, afterID string) ([]Message, error) {
	url := fmt.Sprintf("%s/channels/%s/messages?limit=%d", baseURL, channelID, limit)
	if afterID != "" {
		url += "&after=" + afterID
	}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bot "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("discord respondio %d: %s", resp.StatusCode, string(respBody))
	}

	var msgs []Message
	if err := json.NewDecoder(resp.Body).Decode(&msgs); err != nil {
		return nil, err
	}

	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	return msgs, nil
}

func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `mensajero_discord - CLI para comunicar Claude Code via Discord

Uso:
  mensajero_discord --token TOKEN --channel ID send <mensaje>
  mensajero_discord --token TOKEN --channel ID read [--last N] [--from nombre] [--after id]

Parametros globales:
  --token    Token del bot de Discord
  --channel  ID del canal de texto

Parametros de read:
  --last N       Cantidad de mensajes a leer (default: 10)
  --from nombre  Filtrar por nombre de usuario
  --after id     Leer mensajes posteriores a este ID

Ejemplos:
  mensajero_discord --token ABC123 --channel 999 send "Hola maxi"
  mensajero_discord --token ABC123 --channel 999 read --last 5
  mensajero_discord --token ABC123 --channel 999 read --from maxi
  mensajero_discord --token ABC123 --channel 999 read --after 1234567890
`)
}

type globalArgs struct {
	token     string
	channelID string
	rest      []string
}

func parseGlobalArgs(args []string) (globalArgs, error) {
	var g globalArgs
	var rest []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--token":
			if i+1 >= len(args) {
				return g, fmt.Errorf("--token requiere un valor")
			}
			i++
			g.token = args[i]
		case "--channel":
			if i+1 >= len(args) {
				return g, fmt.Errorf("--channel requiere un valor")
			}
			i++
			g.channelID = args[i]
		default:
			rest = append(rest, args[i:]...)
			g.rest = rest
			return g, nil
		}
	}
	g.rest = rest
	return g, nil
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	g, err := parseGlobalArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if g.token == "" {
		g.token = os.Getenv("DISCORD_BOT_TOKEN")
	}
	if g.channelID == "" {
		g.channelID = os.Getenv("DISCORD_CHANNEL_ID")
	}
	if g.token == "" {
		fmt.Fprintln(os.Stderr, "Error: falta --token o DISCORD_BOT_TOKEN")
		os.Exit(1)
	}
	if g.channelID == "" {
		fmt.Fprintln(os.Stderr, "Error: falta --channel o DISCORD_CHANNEL_ID")
		os.Exit(1)
	}

	if len(g.rest) == 0 {
		printUsage()
		os.Exit(1)
	}

	switch g.rest[0] {
	case "send":
		if len(g.rest) < 2 {
			fmt.Fprintln(os.Stderr, "Uso: mensajero_discord --token T --channel C send <mensaje>")
			os.Exit(1)
		}
		msg := strings.Join(g.rest[1:], " ")
		if err := sendMessage(g.token, g.channelID, msg); err != nil {
			fmt.Fprintf(os.Stderr, "Error enviando: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Mensaje enviado.")

	case "read":
		limit := 10
		filterFrom := ""
		afterID := ""

		args := g.rest[1:]
		for i := 0; i < len(args); i++ {
			switch args[i] {
			case "--last":
				if i+1 < len(args) {
					i++
					n, err := strconv.Atoi(args[i])
					if err != nil {
						fmt.Fprintf(os.Stderr, "Error: --last requiere un numero\n")
						os.Exit(1)
					}
					limit = n
				}
			case "--from":
				if i+1 < len(args) {
					i++
					filterFrom = strings.ToLower(args[i])
				}
			case "--after":
				if i+1 < len(args) {
					i++
					afterID = args[i]
				}
			}
		}

		msgs, err := readMessages(g.token, g.channelID, limit, afterID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error leyendo: %v\n", err)
			os.Exit(1)
		}

		if len(msgs) == 0 {
			fmt.Println("No hay mensajes.")
			return
		}

		for _, m := range msgs {
			authorName := m.Author.GlobalName
			if authorName == "" {
				authorName = m.Author.Username
			}
			if filterFrom != "" && !strings.Contains(strings.ToLower(authorName), filterFrom) && !strings.Contains(strings.ToLower(m.Author.Username), filterFrom) {
				continue
			}
			fmt.Printf("[%s] %s (id:%s): %s\n",
				m.Timestamp.Local().Format("15:04:05"),
				m.Author.Username,
				m.ID,
				m.Content,
			)
		}

	default:
		printUsage()
		os.Exit(1)
	}
}
