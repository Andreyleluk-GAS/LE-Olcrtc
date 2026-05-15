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
	Platform string `json:"platform"`
	RoomLink string `json:"roomLink"`
	Tunnel   string `json:"tunnel"`
}

func main() {
	fs := http.FileServer(http.Dir("./templates"))
	http.Handle("/", fs)

	// API: Статус
	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("systemctl", "is-active", "olcrtc").Output()
		status := strings.TrimSpace(string(out))
		json.NewEncoder(w).Encode(map[string]bool{"active": status == "active"})
	})

	// API: Остановка
	http.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		w.WriteHeader(http.StatusOK)
	})

	// API: Чтение логов (как в консоли)
	http.HandleFunc("/api/logs", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("journalctl", "-u", "olcrtc", "-n", "30", "--no-pager").Output()
		w.Write(out)
	})

	// API: Удаление (Сброс)
	http.HandleFunc("/api/delete", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		exec.Command("systemctl", "disable", "olcrtc").Run()
		os.Remove("/etc/systemd/system/olcrtc.service")
		exec.Command("systemctl", "daemon-reload").Run()
		w.WriteHeader(http.StatusOK)
	})

	// API: Запуск и сохранение
	http.HandleFunc("/api/launch", func(w http.ResponseWriter, r *http.Request) {
		var c Config
		json.NewDecoder(r.Body).Decode(&c)

		key := "698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
		clientID := "9cf2464e"
		
		carrier := "custom"
		if c.Platform == "SberJazz" { carrier = "jazz" }
		if c.Platform == "Яндекс Телемост" { carrier = "yandex" }

		// Формируем ту самую команду из скрипта
		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier %s -link direct -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", carrier, c.RoomLink, key, clientID)
		
		// Настройка туннеля (как было в скрипте)
		if c.Tunnel == "videochannel" {
			execCmd += " -transport videochannel -video-w 640 -video-h 480 -video-fps 30 -video-bitrate 1000000 -video-hw none"
		} else {
			execCmd += " -transport vp8channel -vp8-fps 60 -vp8-batch 64"
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

echo -e "\e[34m[4/6] Создание фронтенда с логикой скрипта...\e[0m"
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OlcRTC Управление</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #121212; color: #e0e0e0; }
        .menu-card { background: #1e1e1e; border: 1px solid #333; border-radius: 12px; transition: 0.2s; cursor: pointer; }
        .menu-card:hover { border-color: #0d6efd; background: #252525; }
        .view { display: none; }
        .view.active { display: block; }
        .logs-window { background: #000; color: #0f0; font-family: monospace; height: 300px; overflow-y: scroll; padding: 10px; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container mt-5" style="max-width: 800px;">
        <h2 class="mb-4 text-center text-primary">Панель управления OlcRTC</h2>
        
        <div id="view-menu" class="view active">
            <div class="d-flex justify-content-between align-items-center mb-4 p-3 bg-dark rounded border border-secondary">
                <span class="fs-5">Текущий статус службы:</span>
                <span id="status-badge" class="badge bg-secondary fs-6">Проверка...</span>
            </div>

            <div class="row g-3">
                <div class="col-md-6">
                    <div class="menu-card p-4 text-center" onclick="showView('view-setup')">
                        <h4 class="text-success mb-2">▶ Настроить и Запустить</h4>
                        <small class="text-muted">Выбрать платформу и ввести ссылку</small>
                    </div>
                </div>
                <div class="col-md-6">
                    <div class="menu-card p-4 text-center" onclick="openLogs()">
                        <h4 class="text-info mb-2">📋 Посмотреть логи</h4>
                        <small class="text-muted">Проверить консоль (journalctl)</small>
                    </div>
                </div>
                <div class="col-md-6">
                    <div class="menu-card p-4 text-center" onclick="apiAction('stop')">
                        <h4 class="text-warning mb-2">■ Остановить бота</h4>
                        <small class="text-muted">Прервать текущее подключение</small>
                    </div>
                </div>
                <div class="col-md-6">
                    <div class="menu-card p-4 text-center" onclick="deleteService()">
                        <h4 class="text-danger mb-2">🗑 Удалить службу</h4>
                        <small class="text-muted">Полный сброс конфигурации</small>
                    </div>
                </div>
            </div>
        </div>

        <div id="view-setup" class="view">
            <div class="card bg-dark border-secondary">
                <div class="card-header bg-secondary text-white d-flex justify-content-between">
                    <h5 class="mb-0">Мастер настройки</h5>
                    <button class="btn btn-sm btn-dark" onclick="showView('view-menu')">✖ Закрыть</button>
                </div>
                <div class="card-body p-4">
                    
                    <div class="mb-4">
                        <label class="form-label text-info">1. Выберите платформу:</label>
                        <select id="platformSelect" class="form-select bg-dark text-white" onchange="updateForm()">
                            <option value="Яндекс Телемост">Яндекс Телемост</option>
                            <option value="SberJazz">SberJazz</option>
                            <option value="WebRTC">Кастомный WebRTC</option>
                        </select>
                    </div>

                    <div id="yandex-helper" class="alert alert-warning text-dark mb-4">
                        <strong>Шаг 1:</strong> Создайте новую встречу в Яндексе.<br>
                        <a href="https://telemost.yandex.ru/" target="_blank" class="btn btn-sm btn-primary mt-2">Создать комнату Телемост ⭧</a>
                        <p class="mt-2 mb-0 small text-muted">Создайте, скопируйте ссылку и вернитесь сюда.</p>
                    </div>

                    <div class="mb-4">
                        <label class="form-label text-info" id="link-label">2. Вставьте ссылку на встречу:</label>
                        <input type="text" id="roomLink" class="form-control bg-dark text-white border-secondary" placeholder="Вставьте ссылку или ID...">
                    </div>

                    <div class="mb-4">
                        <label class="form-label text-info">3. Выберите туннель/транспорт:</label>
                        <select id="tunnelSelect" class="form-select bg-dark text-white">
                            <option value="videochannel">Videochannel (FFmpeg - Стабильный)</option>
                            <option value="vp8channel">VP8Channel (Встроенный)</option>
                        </select>
                    </div>

                    <button class="btn btn-success btn-lg w-100" onclick="launchBot()">💾 Сохранить и Запустить службу</button>
                </div>
            </div>
        </div>

        <div id="view-logs" class="view">
            <div class="card bg-dark border-secondary">
                <div class="card-header bg-secondary text-white d-flex justify-content-between">
                    <h5 class="mb-0">Системные логи (OlcRTC)</h5>
                    <div>
                        <button class="btn btn-sm btn-light me-2" onclick="openLogs()">🔄 Обновить</button>
                        <button class="btn btn-sm btn-dark" onclick="showView('view-menu')">✖ Назад</button>
                    </div>
                </div>
                <div class="card-body">
                    <pre id="log-output" class="logs-window">Загрузка логов...</pre>
                </div>
            </div>
        </div>

    </div>

    <script>
        function showView(id) {
            document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
            document.getElementById(id).classList.add('active');
            updateForm();
        }

        // Обновление формы при выборе платформы (Показ помощника Яндекса)
        function updateForm() {
            let p = document.getElementById('platformSelect').value;
            let helper = document.getElementById('yandex-helper');
            let label = document.getElementById('link-label');
            let input = document.getElementById('roomLink');

            if(p === 'Яндекс Телемост') {
                helper.style.display = 'block';
                label.innerText = '2. Вставьте скопированную ссылку сюда:';
                input.placeholder = 'https://telemost.yandex.ru/j/...';
            } else {
                helper.style.display = 'none';
                label.innerText = '2. Введите ID комнаты:';
                input.placeholder = 'Например: nlg7d4';
            }
        }

        async function checkStatus() {
            try {
                let res = await fetch('/api/status');
                let data = await res.json();
                let b = document.getElementById('status-badge');
                if(data.active) {
                    b.className = 'badge bg-success fs-6'; b.innerText = 'Служба Запущена (Online)';
                } else {
                    b.className = 'badge bg-danger fs-6'; b.innerText = 'Служба Остановлена (Offline)';
                }
            } catch(e) {}
        }

        async function apiAction(action) {
            await fetch('/api/' + action);
            checkStatus();
            if(action === 'stop') alert('Служба остановлена!');
        }

        async function deleteService() {
            if(confirm("Вы уверены? Это остановит бота и удалит файл службы.")) {
                await fetch('/api/delete');
                checkStatus();
                alert('Служба успешно удалена!');
            }
        }

        async function launchBot() {
            let config = {
                platform: document.getElementById('platformSelect').value,
                roomLink: document.getElementById('roomLink').value,
                tunnel: document.getElementById('tunnelSelect').value
            };
            
            if(!config.roomLink) { alert('Пожалуйста, введите ссылку или ID комнаты!'); return; }

            // Запускаем
            await fetch('/api/launch', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(config)
            });

            // Возвращаемся в меню и сразу открываем логи, чтобы видеть процесс
            alert('Конфигурация сохранена! Бот запускается.');
            checkStatus();
            openLogs();
        }

        async function openLogs() {
            showView('view-logs');
            let res = await fetch('/api/logs');
            let text = await res.text();
            let logWindow = document.getElementById('log-output');
            logWindow.innerText = text || "Логи пусты. Служба еще не запускалась.";
            logWindow.scrollTop = logWindow.scrollHeight; // Прокрутка вниз
        }

        setInterval(checkStatus, 3000);
        checkStatus();
    </script>
</body>
</html>
EOF

echo -e "\e[34m[5/6] Компиляция панели...\e[0m"
go build -o olc-ui-bin main.go

echo -e "\e[34m[6/6] Перезапуск...\e[0m"
systemctl daemon-reload
systemctl restart olc-ui

IP=$(curl -s ifconfig.me)
echo -e "\e[32m=======================================================\e[0m"
echo -e "✅ ГРАФИЧЕСКИЙ СКРИПТ УСТАНОВЛЕН!"
echo -e "🌐 Открой панель:"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
