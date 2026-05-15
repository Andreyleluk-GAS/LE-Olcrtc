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
	"regexp"
	"strings"
)

type Config struct {
	Platform string `json:"platform"`
	Link     string `json:"link"`
	Tunnel   string `json:"tunnel"`
}

func main() {
	fs := http.FileServer(http.Dir("./templates"))
	http.Handle("/", fs)

	// API: Проверка статуса
	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("systemctl", "is-active", "olcrtc").Output()
		status := strings.TrimSpace(string(out))
		json.NewEncoder(w).Encode(map[string]bool{"active": status == "active"})
	})

	// API: Просмотр логов
	http.HandleFunc("/api/logs", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("journalctl", "-u", "olcrtc", "-n", "50", "--no-pager").Output()
		w.Write(out)
	})

	// API: Удаление (Остановка и удаление службы)
	http.HandleFunc("/api/delete", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		exec.Command("systemctl", "disable", "olcrtc").Run()
		os.Remove("/etc/systemd/system/olcrtc.service")
		exec.Command("systemctl", "daemon-reload").Run()
		w.WriteHeader(http.StatusOK)
	})

	// API: Реквизиты (Чтение текущей конфигурации из файла)
	http.HandleFunc("/api/info", func(w http.ResponseWriter, r *http.Request) {
		content, err := os.ReadFile("/etc/systemd/system/olcrtc.service")
		if err != nil {
			json.NewEncoder(w).Encode(map[string]string{"error": "Служба не установлена"})
			return
		}
		
		str := string(content)
		carrier := "Неизвестно"
		if strings.Contains(str, "-carrier jazz") { carrier = "SberJazz" }
		if strings.Contains(str, "-carrier yandex") { carrier = "Яндекс Телемост" }
		if strings.Contains(str, "-carrier custom") { carrier = "WebRTC" }

		link := ""
		if strings.Contains(str, "-carrier yandex") {
			re := regexp.MustCompile(`-link direct[^\n]+-id "([^"]+)"`)
			if m := re.FindStringSubmatch(str); len(m) > 1 { link = m[1] }
		} else {
			re := regexp.MustCompile(`-id "([^"]+)"`)
			if m := re.FindStringSubmatch(str); len(m) > 1 { link = m[1] }
		}

		tunnel := "vp8channel (Стандартный)"
		if strings.Contains(str, "-transport videochannel") { tunnel = "videochannel (FFmpeg)" }

		json.NewEncoder(w).Encode(map[string]string{
			"platform": carrier,
			"link": link,
			"tunnel": tunnel,
		})
	})

	// API: Установить (Создание службы и запуск)
	http.HandleFunc("/api/install", func(w http.ResponseWriter, r *http.Request) {
		var c Config
		json.NewDecoder(r.Body).Decode(&c)

		key := "698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
		clientID := "9cf2464e"
		
		carrier := "custom"
		if c.Platform == "2" { carrier = "custom" } // WebRTC
		if c.Platform == "3" { carrier = "jazz" }   // SberJazz
		if c.Platform == "1" { carrier = "yandex" } // Yandex

		// Формируем команду, как в консольном скрипте
		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier %s -link direct -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", carrier, c.Link, key, clientID)
		
		if c.Tunnel == "1" {
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
		exec.Command("systemctl", "enable", "olcrtc").Run()
		exec.Command("systemctl", "restart", "olcrtc").Run()

		w.WriteHeader(http.StatusOK)
	})

	log.Println("Olc-UI Backend is running on port 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "\e[34m[4/6] Создание фронтенда...\e[0m"
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OlcRTC Установщик</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #121212; color: #e0e0e0; font-family: monospace; }
        .menu-btn { display: block; width: 100%; text-align: left; background: #1e1e1e; border: 1px solid #333; color: #fff; padding: 15px 20px; margin-bottom: 10px; cursor: pointer; transition: 0.2s; font-size: 1.1rem; }
        .menu-btn:hover { background: #2a2a2a; border-color: #555; }
        .menu-btn span { color: #0d6efd; font-weight: bold; margin-right: 15px; }
        .view { display: none; }
        .view.active { display: block; }
        .console-box { background: #000; color: #0f0; padding: 15px; border-radius: 5px; height: 350px; overflow-y: auto; font-family: monospace; white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="container mt-5" style="max-width: 600px;">
        <h3 class="mb-4 text-center border-bottom border-secondary pb-3">Установщик OlcRTC Proxy</h3>

        <div id="view-menu" class="view active">
            <p class="text-muted mb-4 text-center">Выберите действие:</p>
            
            <button class="menu-btn" onclick="showView('view-install')">
                <span>[ 1 ]</span> Установить (Настроить платформу)
            </button>
            <button class="menu-btn" onclick="deleteService()">
                <span>[ 2 ]</span> Удалить службу
            </button>
            <button class="menu-btn" onclick="openLogs()">
                <span>[ 3 ]</span> Посмотреть логи
            </button>
            <button class="menu-btn" onclick="openInfo()">
                <span>[ 4 ]</span> Проверить статус / Реквизиты
            </button>
            <button class="menu-btn" onclick="exitApp()">
                <span>[ 0 ]</span> Выйти
            </button>
        </div>

        <div id="view-install" class="view">
            <div class="card bg-dark border-secondary">
                <div class="card-header bg-secondary text-white">Мастер установки</div>
                <div class="card-body p-4">
                    
                    <div class="mb-3">
                        <label class="form-label text-warning">Выберите платформу:</label>
                        <select id="platform" class="form-select bg-dark text-white border-secondary" onchange="updateForm()">
                            <option value="1">1. Яндекс Телемост</option>
                            <option value="2">2. WebRTC</option>
                            <option value="3">3. SberJazz</option>
                        </select>
                    </div>

                    <div id="ya-helper" class="p-3 mb-3 border border-secondary rounded bg-dark d-block">
                        <p class="mb-2">Для Яндекса необходимо сгенерировать ссылку:</p>
                        <a href="https://telemost.yandex.ru/" target="_blank" class="btn btn-primary btn-sm mb-2">Открыть Телемост и создать встречу</a>
                    </div>

                    <div class="mb-3">
                        <label class="form-label text-warning" id="link-label">Вставьте ссылку на встречу:</label>
                        <input type="text" id="link" class="form-control bg-dark text-white border-secondary" placeholder="https://telemost.yandex.ru/j/...">
                    </div>

                    <div class="mb-4">
                        <label class="form-label text-warning">Выберите туннель:</label>
                        <select id="tunnel" class="form-select bg-dark text-white border-secondary">
                            <option value="1">1. Videochannel (FFmpeg)</option>
                            <option value="2">2. VP8Channel (Стандартный)</option>
                        </select>
                    </div>

                    <div class="d-flex justify-content-between">
                        <button class="btn btn-outline-secondary" onclick="showView('view-menu')">Отмена</button>
                        <button class="btn btn-success px-4" onclick="installBot()">Сохранить (OK)</button>
                    </div>
                </div>
            </div>
        </div>

        <div id="view-logs" class="view">
            <div class="d-flex justify-content-between align-items-center mb-2">
                <h5 class="mb-0">Журнал работы (Logs)</h5>
                <button class="btn btn-sm btn-outline-light" onclick="showView('view-menu')">Назад в меню</button>
            </div>
            <div id="log-output" class="console-box">Загрузка...</div>
            <button class="btn btn-primary mt-3 w-100" onclick="openLogs()">Обновить логи</button>
        </div>

        <div id="view-info" class="view">
            <div class="card bg-dark border-secondary">
                <div class="card-header bg-secondary text-white d-flex justify-content-between">
                    <span>Текущие настройки сервера</span>
                    <span id="status-badge" class="badge bg-danger">Остановлено</span>
                </div>
                <div class="card-body p-4">
                    <p class="text-muted mb-1">Платформа:</p>
                    <h5 id="info-platform" class="text-info mb-3">-</h5>
                    
                    <p class="text-muted mb-1">Ссылка / ID:</p>
                    <h5 id="info-link" class="text-success mb-3" style="word-break: break-all;">-</h5>
                    
                    <p class="text-muted mb-1">Туннель:</p>
                    <h5 id="info-tunnel" class="text-warning mb-4">-</h5>

                    <button class="btn btn-outline-light w-100" onclick="showView('view-menu')">Вернуться в меню</button>
                </div>
            </div>
        </div>

    </div>

    <script>
        function showView(id) {
            document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
            document.getElementById(id).classList.add('active');
        }

        function updateForm() {
            let p = document.getElementById('platform').value;
            let helper = document.getElementById('ya-helper');
            let label = document.getElementById('link-label');
            let input = document.getElementById('link');

            if(p === "1") { // Yandex
                helper.style.display = 'block';
                label.innerText = 'Вставьте ссылку на встречу:';
                input.placeholder = 'https://telemost.yandex.ru/j/...';
            } else {
                helper.style.display = 'none';
                label.innerText = 'Введите ID комнаты:';
                input.placeholder = 'nlg7d4';
            }
        }

        async function installBot() {
            let link = document.getElementById('link').value;
            if(!link) { alert('Ошибка: Введите ссылку или ID!'); return; }

            let config = {
                platform: document.getElementById('platform').value,
                link: link,
                tunnel: document.getElementById('tunnel').value
            };
            
            await fetch('/api/install', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(config)
            });

            alert('Установка завершена! Конфигурация применена.');
            showView('view-menu');
        }

        async function deleteService() {
            if(confirm("Вы уверены, что хотите полностью удалить бота и сбросить настройки?")) {
                await fetch('/api/delete');
                alert('Служба удалена.');
            }
        }

        async function openLogs() {
            showView('view-logs');
            let res = await fetch('/api/logs');
            let text = await res.text();
            let logBox = document.getElementById('log-output');
            logBox.innerText = text || "Нет данных. Служба не запущена.";
            logBox.scrollTop = logBox.scrollHeight;
        }

        async function openInfo() {
            showView('view-info');
            
            // Запрашиваем статус работы
            let resStatus = await fetch('/api/status');
            let dataStatus = await resStatus.json();
            let badge = document.getElementById('status-badge');
            if(dataStatus.active) {
                badge.className = 'badge bg-success'; badge.innerText = 'Работает (Active)';
            } else {
                badge.className = 'badge bg-danger'; badge.innerText = 'Остановлено';
            }

            // Запрашиваем реквизиты (чтение конфига)
            let resInfo = await fetch('/api/info');
            let dataInfo = await resInfo.json();
            
            if(dataInfo.error) {
                document.getElementById('info-platform').innerText = "Не настроено";
                document.getElementById('info-link').innerText = "-";
                document.getElementById('info-tunnel').innerText = "-";
            } else {
                document.getElementById('info-platform').innerText = dataInfo.platform;
                document.getElementById('info-link').innerText = dataInfo.link;
                document.getElementById('info-tunnel').innerText = dataInfo.tunnel;
            }
        }

        function exitApp() {
            alert("Вы можете просто закрыть эту вкладку браузера.");
            window.close();
        }

        // Инициализация формы при старте
        updateForm();
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
echo -e "✅ ГРАФИЧЕСКИЙ УСТАНОВЩИК ГОТОВ!"
echo -e "🌐 Перейдите по ссылке:"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
