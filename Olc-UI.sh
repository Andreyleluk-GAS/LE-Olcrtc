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

// Структура для приема настроек из браузера
type Config struct {
	RoomID    string `json:"roomId"`
	Transport string `json:"transport"`
	Width     string `json:"width"`
	Fps       string `json:"fps"`
}

func main() {
	fs := http.FileServer(http.Dir("./templates"))
	http.Handle("/", fs)

	// Статус бота
	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("systemctl", "is-active", "olcrtc").Output()
		status := strings.TrimSpace(string(out))
		json.NewEncoder(w).Encode(map[string]bool{"active": status == "active"})
	})

	// Управление питанием
	http.HandleFunc("/api/start", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "start", "olcrtc").Run()
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		w.WriteHeader(http.StatusOK)
	})

	// МАГИЯ: Сохранение настроек и перезапись системной службы
	http.HandleFunc("/api/save", func(w http.ResponseWriter, r *http.Request) {
		var c Config
		json.NewDecoder(r.Body).Decode(&c)

		// Базовые ключи (в будущем можно генерировать случайно)
		key := "698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
		clientID := "9cf2464e"

		// Формируем базовую команду
		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier jazz -transport %s -link direct -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", c.Transport, c.RoomID, key, clientID)

		// Добавляем специфичные флаги в зависимости от транспорта
		if c.Transport == "videochannel" {
			execCmd += fmt.Sprintf(" -video-w %s -video-h 480 -video-fps %s -video-bitrate 1000000 -video-hw none", c.Width, c.Fps)
		} else {
			execCmd += " -vp8-fps 60 -vp8-batch 64"
		}

		// Шаблон системной службы
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

		// Записываем файл в Linux
		os.WriteFile("/etc/systemd/system/olcrtc.service", []byte(serviceContent), 0644)
		
		// Перезагружаем демоны и перезапускаем бота
		exec.Command("systemctl", "daemon-reload").Run()
		exec.Command("systemctl", "restart", "olcrtc").Run()

		w.WriteHeader(http.StatusOK)
	})

	log.Println("Olc-UI Backend is running on port 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "\e[34m[4/6] Создание фронтенда (index.html)...\e[0m"
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Olc-UI Dashboard</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>body { background-color: #121212; color: #e0e0e0; } .card { background-color: #1e1e1e; border: 1px solid #333; }</style>
</head>
<body>
    <div class="container mt-5">
        <h2 class="mb-4 text-primary">Olc-UI <small class="text-muted fs-6">v1.0</small></h2>
        
        <div class="row">
            <div class="col-md-6 mb-4">
                <div class="card shadow-sm h-100">
                    <div class="card-header bg-dark d-flex justify-content-between align-items-center">
                        <h5 class="mb-0 text-white">Управление ботом</h5>
                        <span id="status-badge" class="badge bg-secondary">Ожидание...</span>
                    </div>
                    <div class="card-body text-center py-5">
                        <button onclick="controlBot('start')" class="btn btn-success btn-lg mx-2 w-100 mb-3" id="btn-start">▶ Запустить бота</button>
                        <button onclick="controlBot('stop')" class="btn btn-danger btn-lg mx-2 w-100" id="btn-stop">■ Остановить бота</button>
                    </div>
                </div>
            </div>

            <div class="col-md-6 mb-4">
                <div class="card shadow-sm h-100">
                    <div class="card-header bg-dark"><h5 class="mb-0 text-white">Настройки конфигурации</h5></div>
                    <div class="card-body">
                        <form id="configForm">
                            <div class="mb-3">
                                <label class="form-label">ID Комнаты (Jazz)</label>
                                <input type="text" id="roomId" class="form-control bg-dark text-light border-secondary" value="nlg7d4">
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Транспорт</label>
                                <select id="transport" class="form-select bg-dark text-light border-secondary">
                                    <option value="videochannel">videochannel (FFmpeg - Рекомендуется)</option>
                                    <option value="vp8channel">vp8channel (Встроенный)</option>
                                </select>
                            </div>
                            <div class="row">
                                <div class="col-6 mb-3">
                                    <label class="form-label">Ширина (px)</label>
                                    <input type="number" id="width" class="form-control bg-dark text-light border-secondary" value="640">
                                </div>
                                <div class="col-6 mb-3">
                                    <label class="form-label">FPS</label>
                                    <input type="number" id="fps" class="form-control bg-dark text-light border-secondary" value="30">
                                </div>
                            </div>
                            <button type="button" class="btn btn-primary w-100" id="btn-save" onclick="saveConfig()">💾 Сохранить и Перезапустить</button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        async function checkStatus() {
            try {
                let res = await fetch('/api/status');
                let data = await res.json();
                let badge = document.getElementById('status-badge');
                
                if (data.active) {
                    badge.className = 'badge bg-success'; badge.innerText = 'Online';
                    document.getElementById('btn-start').disabled = true;
                    document.getElementById('btn-stop').disabled = false;
                } else {
                    badge.className = 'badge bg-danger'; badge.innerText = 'Offline';
                    document.getElementById('btn-start').disabled = false;
                    document.getElementById('btn-stop').disabled = true;
                }
            } catch(e) {}
        }

        async function controlBot(action) {
            await fetch('/api/' + action);
            setTimeout(checkStatus, 1000);
        }

        // НОВАЯ ФУНКЦИЯ: Сохранение настроек
        async function saveConfig() {
            let btn = document.getElementById('btn-save');
            btn.innerText = "⏳ Сохранение...";
            btn.disabled = true;

            const configData = {
                roomId: document.getElementById('roomId').value,
                transport: document.getElementById('transport').value,
                width: document.getElementById('width').value,
                fps: document.getElementById('fps').value
            };

            await fetch('/api/save', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(configData)
            });

            setTimeout(() => {
                btn.innerText = "✅ Успешно! (Сохранить еще раз)";
                btn.disabled = false;
                checkStatus();
            }, 1500);
        }

        setInterval(checkStatus, 3000); 
        checkStatus();
    </script>
</body>
</html>
EOF

echo -e "\e[34m[5/6] Компиляция панели...\e[0m"
go build -o olc-ui-bin main.go

echo -e "\e[34m[6/6] Перезапуск службы панели...\e[0m"
systemctl daemon-reload
systemctl restart olc-ui

IP=$(curl -s ifconfig.me)
echo -e "\e[32m=======================================================\e[0m"
echo -e "\e[32m✅ ОБНОВЛЕНИЕ ДО V1.0 УСПЕШНО ЗАВЕРШЕНО!\e[0m"
echo -e "🌐 Открой панель (или обнови страницу):"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
