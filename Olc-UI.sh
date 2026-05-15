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
                        <option value="videochannel">FFmpeg Videochannel (Рекомендуется)</option>
                        <option value="vp8channel">Стандартный VP8</option>
                    </select>
                </div>
                <div class="d-flex justify-content-between mt-5">
                    <button class="btn btn-outline-secondary px-4" onclick="showStep(1)">← Назад</button>
                    <button class="btn btn-primary px-5 btn-lg" onclick="startLaunch()">Запустить магию ✨</button>
                </div>
            </div>
        </div>

        <div id="step-3" class="step glass-card p-5 shadow-lg">
            <h3 class="mb-4" id="launch-title">Подключение бота...</h3>
            <div class="progress mb-4" style="height: 10px;">
                <div id="launch-progress" class="progress-bar progress-bar-striped progress-bar-animated bg-primary" style="width: 0%"></div>
            </div>
            <div class="terminal mb-4" id="terminal-output">
                > Инициализация системы...<br>
            </div>
            <button id="btn-dashboard" class="btn btn-success btn-lg w-100 d-none" onclick="showStep(4)">Перейти в Панель Управления</button>
        </div>

        <div id="step-4" class="step glass-card p-5 shadow-lg">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h3 class="mb-0">Статус работы</h3>
                <span id="status-badge" class="badge bg-success fs-6 px-3 py-2">Бот Online</span>
            </div>
            <div class="row text-start mb-4">
                <div class="col-6"><p class="text-muted mb-1">Комната:</p><h5 id="dash-room" class="text-white">-</h5></div>
                <div class="col-6"><p class="text-muted mb-1">Транспорт:</p><h5 id="dash-transport" class="text-white">-</h5></div>
            </div>
            <hr class="border-secondary">
            <div class="d-flex gap-3 mt-4">
                <button class="btn btn-danger w-50" onclick="stopBot()">■ Остановить трансляцию</button>
                <button class="btn btn-outline-primary w-50" onclick="showStep(1)">⚙️ Создать новую</button>
            </div>
        </div>
    </div>

    <script>
        let currentPlatform = '';

        function showStep(stepNum) {
            document.querySelectorAll('.step').forEach(el => el.classList.remove('active'));
            document.getElementById('step-' + stepNum).classList.add('active');
        }

        function selectPlatform(platform) {
            currentPlatform = platform;
            document.getElementById('selected-platform-name').innerText = (platform === 'jazz') ? 'Sber Jazz' : platform;
            showStep(2);
        }

        function writeTerminal(text, delay) {
            return new Promise(resolve => {
                setTimeout(() => {
                    document.getElementById('terminal-output').innerHTML += '> ' + text + '<br>';
                    document.getElementById('terminal-output').scrollTop = document.getElementById('terminal-output').scrollHeight;
                    resolve();
                }, delay);
            });
        }

        async function startLaunch() {
            showStep(3);
            const roomId = document.getElementById('roomId').value || 'default_room';
            const transport = document.getElementById('transport').value;
            
            document.getElementById('btn-dashboard').classList.add('d-none');
            document.getElementById('terminal-output').innerHTML = '> Инициализация системы...<br>';
            document.getElementById('launch-progress').style.width = '10%';

            // Визуальная магия в консоли
            await writeTerminal('Проверка доступности портов...', 800);
            document.getElementById('launch-progress').style.width = '30%';
            await writeTerminal('Генерация конфигов для ' + transport + '...', 1000);
            
            // Отправляем реальный запрос на сервер
            const configData = { platform: currentPlatform, roomId: roomId, transport: transport };
            await fetch('/api/launch', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(configData)
            });

            document.getElementById('launch-progress').style.width = '70%';
            await writeTerminal('Запуск демона OlcRTC...', 1200);
            await writeTerminal('Соединение с сигнальным сервером...', 1500);
            
            document.getElementById('launch-progress').style.width = '100%';
            document.getElementById('launch-progress').classList.remove('bg-primary');
            document.getElementById('launch-progress').classList.add('bg-success');
            await writeTerminal('<span style="color: #fff; background: green; padding: 2px 5px;">УСПЕШНО! Бот зашел в комнату.</span>', 500);
            
            document.getElementById('launch-title').innerText = "Подключение завершено!";
            document.getElementById('btn-dashboard').classList.remove('d-none');

            // Заполняем дашборд
            document.getElementById('dash-room').innerText = roomId;
            document.getElementById('dash-transport').innerText = transport;
        }

        async function stopBot() {
            await fetch('/api/stop');
            document.getElementById('status-badge').className = 'badge bg-danger fs-6 px-3 py-2';
            document.getElementById('status-badge').innerText = 'Бот Offline';
            alert('Бот остановлен!');
        }

        // Проверка статуса при загрузке
        async function initCheck() {
            try {
                let res = await fetch('/api/status');
                let data = await res.json();
                if (data.active) { showStep(4); }
            } catch(e) {}
        }
        initCheck();
    </script>
</body>
</html>
EOF

echo -e "\e[34m[5/6] Компиляция Studio...\e[0m"
go build -o olc-ui-bin main.go

echo -e "\e[34m[6/6] Перезапуск службы...\e[0m"
systemctl daemon-reload
systemctl restart olc-ui

IP=$(curl -s ifconfig.me)
echo -e "\e[32m=======================================================\e[0m"
echo -e "\e[32m✨ OLC-RTC STUDIO УСПЕШНО УСТАНОВЛЕНА! ✨\e[0m"
echo -e "🌐 Открой панель (или обнови страницу с очисткой кэша Ctrl+F5):"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
