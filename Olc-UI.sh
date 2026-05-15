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
	Platform       string `json:"platform"`
	LinkOrRoom     string `json:"linkOrRoom"`
	ConnectionType string `json:"connectionType"`
	Tunnel         string `json:"tunnel"`
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
		carrier := "custom"
		
		if c.Platform == "SberJazz" { carrier = "jazz" }
		if c.Platform == "Яндекс Телемост" { carrier = "yandex" }

		// Формируем команду (адаптировано под разные платформы)
		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier %s -link %s -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", carrier, c.ConnectionType, c.LinkOrRoom, key, clientID)
		
		if c.Tunnel == "videochannel" || c.Tunnel == "udp" {
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
        .glass-card { background: rgba(30, 33, 40, 0.95); border: 1px solid rgba(255,255,255,0.05); border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); }
        .platform-btn { transition: all 0.3s ease; border: 2px solid transparent; cursor: pointer; border-radius: 12px; background: #1a1d24; padding: 25px 15px; }
        .platform-btn:hover { border-color: #0d6efd; transform: translateY(-5px); background: #22262f; box-shadow: 0 10px 20px rgba(13,110,253,0.15); }
        .step { display: none; animation: fadeIn 0.4s ease-in-out; }
        .step.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(15px); } to { opacity: 1; transform: translateY(0); } }
        .terminal { background: #050505; font-family: monospace; color: #00ff00; padding: 15px; border-radius: 8px; height: 160px; overflow-y: auto; text-align: left; border: 1px solid #333; }
        .history-item { cursor: pointer; transition: background 0.2s; border-radius: 8px; }
        .history-item:hover { background: rgba(255,255,255,0.05); }
    </style>
</head>
<body>
    <div class="container mt-5 text-center" style="max-width: 800px;">
        <h1 class="mb-5 fw-bold" style="color: #fff; letter-spacing: 1px;">OlcRTC <span style="color: #0d6efd;">Studio</span></h1>
        
        <div id="step-1" class="step active glass-card p-5">
            <h4 class="mb-4 text-white">Выберите платформу подключения</h4>
            <div class="row g-4 mb-5">
                <div class="col-md-4">
                    <div class="platform-btn" onclick="selectPlatform('Яндекс Телемост')">
                        <h5 class="mb-0 text-warning" style="font-weight: 600;">Яндекс Телемост</h5>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="platform-btn" onclick="selectPlatform('WebRTC')">
                        <h5 class="mb-0 text-success" style="font-weight: 600;">WebRTC</h5>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="platform-btn" onclick="selectPlatform('SberJazz')">
                        <h5 class="mb-0 text-primary" style="font-weight: 600;">SberJazz</h5>
                    </div>
                </div>
            </div>
            
            <div id="history-container" class="text-start mt-4 d-none">
                <h6 class="text-muted mb-3 text-uppercase" style="letter-spacing: 1px; font-size: 0.85rem;">Последние конфигурации</h6>
                <div id="history-list" class="list-group list-group-flush border-top border-secondary pt-2">
                    </div>
            </div>
        </div>

        <div id="step-2" class="step glass-card p-5">
            <h3 class="mb-4 text-white">Настройка: <span id="selected-platform-name" class="text-primary"></span></h3>
            <div class="text-start">
                
                <div id="form-yandex" class="dynamic-form d-none">
                    <div class="mb-4">
                        <label class="form-label text-muted">Ссылка на встречу</label>
                        <input type="text" id="ya-link" class="form-control form-control-lg bg-dark text-white border-secondary" placeholder="https://telemost.yandex.ru/j/...">
                    </div>
                    <div class="mb-4">
                        <label class="form-label text-muted">Тип соединения</label>
                        <select id="ya-conn" class="form-select form-select-lg bg-dark text-white border-secondary">
                            <option value="direct">Direct (Прямое)</option>
                            <option value="proxy">Proxy (Через сервер)</option>
                        </select>
                    </div>
                    <div class="mb-4">
                        <label class="form-label text-muted">Туннель</label>
                        <select id="ya-tunnel" class="form-select form-select-lg bg-dark text-white border-secondary">
                            <option value="udp">UDP</option>
                            <option value="tcp">TCP</option>
                        </select>
                    </div>
                </div>

                <div id="form-standard" class="dynamic-form d-none">
                    <div class="mb-4">
                        <label class="form-label text-muted">ID Комнаты</label>
                        <input type="text" id="std-room" class="form-control form-control-lg bg-dark text-white border-secondary" placeholder="Например: nlg7d4">
                    </div>
                    <div class="mb-4">
                        <label class="form-label text-muted">Транспорт</label>
                        <select id="std-tunnel" class="form-select form-select-lg bg-dark text-white border-secondary">
                            <option value="videochannel">FFmpeg (Videochannel)</option>
                            <option value="vp8channel">Стандартный (VP8)</option>
                        </select>
                    </div>
                </div>

                <div class="d-flex justify-content-between mt-5">
                    <button class="btn btn-outline-secondary px-4" onclick="showStep(1)">← Назад</button>
                    <button class="btn btn-primary px-5 btn-lg" onclick="startLaunch()">Далее →</button>
                </div>
            </div>
        </div>

        <div id="step-3" class="step glass-card p-5">
            <h3 class="mb-4 text-white" id="launch-title">Подключение...</h3>
            <div class="progress mb-4 bg-dark" style="height: 8px; border-radius: 4px;">
                <div id="launch-progress" class="progress-bar progress-bar-striped progress-bar-animated bg-primary" style="width: 0%"></div>
            </div>
            <div class="terminal shadow-inner mb-4" id="terminal-output">
                > Инициализация подсистемы...<br>
            </div>
            <button id="btn-dashboard" class="btn btn-success btn-lg w-100 d-none shadow" onclick="showStep(4)">Перейти к результату ✨</button>
        </div>

        <div id="step-4" class="step glass-card p-5">
            <div class="text-center mb-5">
                <div class="d-inline-block bg-success bg-opacity-25 p-3 rounded-circle mb-3">
                    <span style="font-size: 2rem;">✅</span>
                </div>
                <h3 class="text-white">Готово! Успешное подключение.</h3>
                <p class="text-muted" id="dash-info">Платформа: - | Туннель: -</p>
            </div>
            
            <div class="text-start p-4 bg-dark rounded-3 border border-secondary mb-4 shadow-sm">
                <label class="form-label text-muted mb-2">Ваша ссылка для доступа:</label>
                <div class="input-group">
                    <input type="text" id="result-link" class="form-control bg-dark text-info border-secondary fs-5" readonly value="Генерация...">
                    <button class="btn btn-outline-secondary" onclick="copyLink()">📋 Копировать</button>
                </div>
            </div>

            <hr class="border-secondary my-4">
            <div class="d-flex gap-3">
                <button class="btn btn-danger w-50" onclick="stopBot()">■ Остановить процесс</button>
                <button class="btn btn-outline-light w-50" onclick="showStep(1)">+ Новая сессия</button>
            </div>
        </div>
    </div>

    <script>
        let currentPlatform = '';
        let currentConfig = {};

        // Загрузка истории при старте
        function loadHistory() {
            const history = JSON.parse(localStorage.getItem('olcrtc_history') || '[]');
            const container = document.getElementById('history-container');
            const list = document.getElementById('history-list');
            
            if (history.length > 0) {
                container.classList.remove('d-none');
                list.innerHTML = '';
                history.forEach((item, index) => {
                    list.innerHTML += `
                        <div class="history-item d-flex justify-content-between align-items-center p-3 mb-2 bg-dark rounded" onclick='loadConfig(${index})'>
                            <div>
                                <strong class="text-white">${item.platform}</strong>
                                <span class="text-muted ms-2 fs-6">${item.linkOrRoom}</span>
                            </div>
                            <span class="badge bg-secondary">▶ Запуск</span>
                        </div>
                    `;
                });
            }
        }

        function loadConfig(index) {
            const history = JSON.parse(localStorage.getItem('olcrtc_history') || '[]');
            const conf = history[index];
            currentPlatform = conf.platform;
            
            if (conf.platform === 'Яндекс Телемост') {
                document.getElementById('ya-link').value = conf.linkOrRoom;
                document.getElementById('ya-conn').value = conf.connectionType;
                document.getElementById('ya-tunnel').value = conf.tunnel;
            } else {
                document.getElementById('std-room').value = conf.linkOrRoom;
                document.getElementById('std-tunnel').value = conf.tunnel;
            }
            selectPlatform(conf.platform);
        }

        function showStep(stepNum) {
            document.querySelectorAll('.step').forEach(el => el.classList.remove('active'));
            document.getElementById('step-' + stepNum).classList.add('active');
            if (stepNum === 1) loadHistory();
        }

        function selectPlatform(platform) {
            currentPlatform = platform;
            document.getElementById('selected-platform-name').innerText = platform;
            
            document.querySelectorAll('.dynamic-form').forEach(el => el.classList.add('d-none'));
            if (platform === 'Яндекс Телемост') {
                document.getElementById('form-yandex').classList.remove('d-none');
            } else {
                document.getElementById('form-standard').classList.remove('d-none');
            }
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
            
            // Собираем данные в зависимости от формы
            if (currentPlatform === 'Яндекс Телемост') {
                currentConfig = {
                    platform: currentPlatform,
                    linkOrRoom: document.getElementById('ya-link').value || 'https://telemost.yandex.ru/',
                    connectionType: document.getElementById('ya-conn').value,
                    tunnel: document.getElementById('ya-tunnel').value
                };
            } else {
                currentConfig = {
                    platform: currentPlatform,
                    linkOrRoom: document.getElementById('std-room').value || 'default',
                    connectionType: 'direct',
                    tunnel: document.getElementById('std-tunnel').value
                };
            }

            // Сохраняем в историю (оставляем только 3 последних)
            let history = JSON.parse(localStorage.getItem('olcrtc_history') || '[]');
            history.unshift(currentConfig);
            if(history.length > 3) history.pop();
            localStorage.setItem('olcrtc_history', JSON.stringify(history));

            // Анимация интерфейса
            document.getElementById('btn-dashboard').classList.add('d-none');
            document.getElementById('terminal-output').innerHTML = '> Инициализация параметров для ' + currentPlatform + '...<br>';
            document.getElementById('launch-progress').style.width = '10%';
            document.getElementById('launch-progress').className = 'progress-bar progress-bar-striped progress-bar-animated bg-primary';

            await writeTerminal('Настройка типа соединения: ' + currentConfig.connectionType + '...', 800);
            document.getElementById('launch-progress').style.width = '40%';
            
            // Отправляем API запрос на бэкенд
            await fetch('/api/launch', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(currentConfig)
            });

            await writeTerminal('Открытие порталов WebRTC (' + currentConfig.tunnel + ')...', 1000);
            document.getElementById('launch-progress').style.width = '70%';
            await writeTerminal('Подключение к медиа-серверу...', 1200);
            
            document.getElementById('launch-progress').style.width = '100%';
            document.getElementById('launch-progress').classList.remove('bg-primary');
            document.getElementById('launch-progress').classList.add('bg-success');
            await writeTerminal('<span style="color: #000; background: #00ff00; padding: 2px 6px; border-radius: 3px;">ЧПОК! Соединение установлено.</span>', 600);
            
            document.getElementById('launch-title').innerText = "Магия совершена!";
            document.getElementById('btn-dashboard').classList.remove('d-none');

            // Подготовка финального экрана
            document.getElementById('dash-info').innerText = `Платформа: ${currentPlatform} | Туннель: ${currentConfig.tunnel.toUpperCase()}`;
            
            // Генерируем красивую ссылку
            const serverIP = window.location.hostname;
            const uniqueId = Math.random().toString(36).substring(2, 8);
            document.getElementById('result-link').value = `http://${serverIP}:8080/join/${uniqueId}`;
        }

        async function stopBot() {
            await fetch('/api/stop');
            alert('Процесс успешно остановлен.');
            showStep(1);
        }

        function copyLink() {
            const link = document.getElementById('result-link');
            link.select();
            document.execCommand('copy');
            alert('Ссылка скопирована!');
        }

        // Запуск
        loadHistory();
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
echo -e "\e[32m✨ OLC-RTC STUDIO УСПЕШНО ОБНОВЛЕНА! ✨\e[0m"
echo -e "🌐 Открой панель (не забудь Ctrl+F5 для сброса кэша):"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
