#!/bin/bash

echo -e "\e[34m[1/6] Установка зависимостей...\e[0m"
apt-get update -y > /dev/null 2>&1
apt-get install -y golang curl > /dev/null 2>&1

echo -e "\e[34m[2/6] Подготовка директорий...\e[0m"
mkdir -p /opt/olc-ui/templates
cd /opt/olc-ui
go mod init olc-ui 2>/dev/null || true

echo -e "\e[34m[3/6] Создание бэкенда (main.go)...\e[0m"
cat << 'EOF' > main.go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

type Config struct {
	Platform  string `json:"platform"`
	RoomID    string `json:"roomId"`
	Transport string `json:"transport"`
}

func main() {
	fs := http.FileServer(http.Dir("./templates"))
	http.Handle("/", fs)

	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("systemctl", "is-active", "olcrtc").Output()
		status := strings.TrimSpace(string(out))
		json.NewEncoder(w).Encode(map[string]bool{"active": status == "active"})
	})

	http.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/api/launch", func(w http.ResponseWriter, r *http.Request) {
		var c Config
		json.NewDecoder(r.Body).Decode(&c)

		key := "698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
		clientID := "9cf2464e"

		// Базовая логика под Jazz (в будущем добавишь Яндекс)
		carrier := "jazz"
		if c.Platform != "jazz" { carrier = "custom" }

		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier %s -transport %s -link direct -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", carrier, c.Transport, c.RoomID, key, clientID)
		
		if c.Transport == "videochannel" {
			execCmd += " -video-w 640 -video-h 480 -video-fps 30 -video-bitrate 1000000 -video-hw none"
		} else {
			execCmd += " -vp8-fps 60 -vp8-batch 64"
		}

		serviceContent := fmt.Sprintf(`[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=%s
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target`, execCmd)

		os.WriteFile("/etc/systemd/system/olcrtc.service", []byte(serviceContent), 0644)
		exec.Command("systemctl", "daemon-reload").Run()
		exec.Command("systemctl", "restart", "olcrtc").Run()

		w.WriteHeader(http.StatusOK)
	})

	log.Println("Olc-UI Backend is running on port 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "\e[34m[4/6] Создание интерактивного фронтенда (index.html)...\e[0m"
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OlcRTC Studio</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #0f1115; color: #e0e0e0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .glass-card { background: rgba(30, 33, 40, 0.9); border: 1px solid rgba(255,255,255,0.05); border-radius: 16px; backdrop-filter: blur(10px); }
        .platform-btn { transition: all 0.3s ease; border: 2px solid transparent; cursor: pointer; border-radius: 12px; background: #1a1d24; padding: 20px; }
        .platform-btn:hover, .platform-btn.active { border-color: #0d6efd; transform: translateY(-5px); background: #22262f; box-shadow: 0 10px 20px rgba(13,110,253,0.2); }
        .step { display: none; animation: fadeIn 0.5s ease-in-out; }
        .step.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        .terminal { background: #050505; font-family: monospace; color: #00ff00; padding: 15px; border-radius: 8px; height: 150px; overflow-y: auto; text-align: left; }
    </style>
</head>
<body>
    <div class="container mt-5 text-center" style="max-width: 800px;">
        <h1 class="mb-4 fw-bold" style="background: linear-gradient(90deg, #0d6efd, #0dcaf0); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">OlcRTC Studio</h1>
        
        <div id="step-1" class="step active glass-card p-5 shadow-lg">
            <h3 class="mb-4">Куда отправим бота?</h3>
            <div class="row g-4 mb-4">
                <div class="col-md-4">
                    <div class="platform-btn" onclick="selectPlatform('jazz')">
                        <h4 class="mb-2 text-primary">Sber Jazz</h4>
                        <small class="text-muted">Полная поддержка WebRTC</small>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="platform-btn" onclick="alert('Модуль Яндекса в разработке!')">
                        <h4 class="mb-2 text-warning">Yandex</h4>
                        <small class="text-muted">Телемост (Скоро)</small>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="platform-btn" onclick="alert('Модуль кастомной настройки в разработке!')">
                        <h4 class="mb-2 text-success">Custom</h4>
                        <small class="text-muted">Свой SIP / WebRTC</small>
                    </div>
                </div>
            </div>
        </div>

        <div id="step-2" class="step glass-card p-5 shadow-lg">
            <h3 class="mb-4">Настройка комнаты <span id="selected-platform-name" class="text-primary"></span></h3>
            <div class="text-start">
                <div class="mb-4">
                    <label class="form-label text-muted">ID Конференции (Room ID)</label>
                    <input type="text" id="roomId" class="form-control form-control-lg bg-dark text-white border-0" placeholder="Например: nlg7d4">
                </div>
                <div class="mb-4">
                    <label class="form-label text-muted">Технология захвата (Транспорт)</label>
                    <select id="transport" class="form-select form-select-lg bg-dark text-white border-0">
                        <option value="videochannel">FFmpeg Videochannel (Рекомендуется)</option
