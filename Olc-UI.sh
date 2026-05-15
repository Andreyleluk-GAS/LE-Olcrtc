#!/bin/bash

echo -e "\e[34m[1/6] Установка свежей версии Go и зависимостей...\e[0m"
apt-get update -y > /dev/null 2>&1
apt-get install -y curl wget git tar > /dev/null 2>&1

# Удаляем старый системный Go (чтобы избежать конфликтов)
apt-get remove -y golang-go golang > /dev/null 2>&1
rm -rf /usr/local/go

# Узнаем самую последнюю версию Go напрямую с серверов Google
LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
echo -e "\e[32m➤ Скачиваем и устанавливаем ${LATEST_GO}...\e[0m"

# Скачиваем, распаковываем и прописываем пути
wget -qO go.tar.gz "https://go.dev/dl/${LATEST_GO}.linux-amd64.tar.gz"
tar -C /usr/local -xzf go.tar.gz
rm go.tar.gz
ln -sf /usr/local/go/bin/go /usr/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt

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
	Provider  string `json:"provider"`
	Transport string `json:"transport"`
	RoomLink  string `json:"roomLink"`
}

func main() {
	fs := http.FileServer(http.Dir("./templates"))
	http.Handle("/", fs)

	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("systemctl", "is-active", "olcrtc").Output()
		status := strings.TrimSpace(string(out))
		json.NewEncoder(w).Encode(map[string]bool{"active": status == "active"})
	})

	http.HandleFunc("/api/logs", func(w http.ResponseWriter, r *http.Request) {
		out, _ := exec.Command("journalctl", "-u", "olcrtc", "-n", "50", "--no-pager").Output()
		w.Write(out)
	})

	http.HandleFunc("/api/delete", func(w http.ResponseWriter, r *http.Request) {
		exec.Command("systemctl", "stop", "olcrtc").Run()
		exec.Command("systemctl", "disable", "olcrtc").Run()
		os.Remove("/etc/systemd/system/olcrtc.service")
		exec.Command("systemctl", "daemon-reload").Run()
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/api/install", func(w http.ResponseWriter, r *http.Request) {
		var c Config
		json.NewDecoder(r.Body).Decode(&c)

		key := "698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
		clientID := "9cf2464e"
		
		carrier := "yandex"
		if c.Provider == "1" { carrier = "yandex" }
		if c.Provider == "2" { carrier = "wbstream" }
		if c.Provider == "3" { carrier = "jazz" }

		roomID := strings.TrimSpace(c.RoomLink)
		execCmd := fmt.Sprintf("/opt/olcrtc/olcrtc -mode srv -carrier %s -link direct -dns 1.1.1.1:53 -data data -id \"%s\" -key \"%s\" -client-id \"%s\"", carrier, roomID, key, clientID)
		
		if c.Transport == "2" {
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

	http.HandleFunc("/api/info", func(w http.ResponseWriter, r *http.Request) {
		content, err := os.ReadFile("/etc/systemd/system/olcrtc.service")
		if err != nil {
			json.NewEncoder(w).Encode(map[string]string{"error": "Служба не установлена"})
			return
		}
		str := string(content)
		carrier := "Неизвестно"
		if strings.Contains(str, "-carrier yandex") { carrier = "telemost (Yandex)" }
		if strings.Contains(str, "-carrier wbstream") { carrier = "wbstream (Wildberries)" }
		if strings.Contains(str, "-carrier jazz") { carrier = "jazz (Sber SaluteJazz)" }

		link := ""
		re := regexp.MustCompile(`-id "([^"]+)"`)
		if m := re.FindStringSubmatch(str); len(m) > 1 { link = m[1] }

		tunnel := "1) vp8channel"
		if strings.Contains(str, "-transport videochannel") { tunnel = "2) videochannel" }

		json.NewEncoder(w).Encode(map[string]string{"platform": carrier, "link": link, "tunnel": tunnel})
	})

	log.Println("Olc-UI Backend is running on port 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "\e[34m[4/6] Создание светлого фронтенда...\e[0m"
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Установка OlcRTC</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f4f6f9; color: #333; font-family: 'Segoe UI', system-ui, sans-serif; }
        .main-card { background: #fff; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.05); overflow: hidden; border: 1px solid #e9ecef; }
        .view { display: none; }
        .view.active { display: block; animation: fadeIn 0.3s; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        
        .menu-list { list-style: none; padding: 0; margin: 0; }
        .menu-list li { border-bottom: 1px solid #eee; }
        .menu-list li:last-child { border-bottom: none; }
        .menu-btn { width: 100%; text-align: left; background: transparent; border: none; padding: 18px 25px; font-size: 1.1rem; color: #2c3e50; font-weight: 500; transition: 0.2s; }
        .menu-btn:hover { background: #f8f9fa; color: #0d6efd; padding-left: 30px; }
        
        .step-header { color: #0d6efd; font-weight: 600; margin-bottom: 15px; border-bottom: 2px solid #e9ecef; padding-bottom: 10px; }
        .radio-card { display: block; padding: 15px; border: 1px solid #dee2e6; border-radius: 8px; margin-bottom: 10px; cursor: pointer; transition: 0.2s; }
        .radio-card:hover { border-color: #0d6efd; background: #f8f9fa; }
        .radio-card input[type="radio"] { margin-right: 10px; }
        
        .console-box { background: #1e1e1e; color: #0f0; padding: 15px; border-radius: 8px; height: 400px; overflow-y: auto; font-family: 'Courier New', monospace; font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="container mt-5 mb-5" style="max-width: 750px;">
        <div class="text-center mb-4">
            <h2 class="fw-bold" style="color: #2c3e50;">Интерактивная установка OlcRTC</h2>
            <p class="text-muted">Графический интерфейс прокси-сервера</p>
        </div>

        <div class="main-card">
            
            <div id="view-menu" class="view active">
                <ul class="menu-list">
                    <li><button class="menu-btn" onclick="showView('view-install')">🛠 Установить (Настройка конфигурации)</button></li>
                    <li><button class="menu-btn" onclick="deleteService()">🗑 Удалить службу</button></li>
                    <li><button class="menu-btn" onclick="openLogs()">📋 Посмотреть логи</button></li>
                    <li><button class="menu-btn" onclick="openInfo()">ℹ️ Проверить статус / Реквизиты</button></li>
                </ul>
            </div>

            <div id="view-install" class="view p-4">
                <div class="alert alert-warning border-warning border-start border-4 mb-4" style="background-color: #fff3cd; color: #856404;">
                    <strong>ВНИМАНИЕ:</strong> Перед продолжением вы должны ВРУЧНУЮ создать комнату на сайте провайдера и скопировать ссылку-приглашение!
                </div>

                <form id="installForm">
                    <div class="mb-4">
                        <h5 class="step-header">Шаг 1: Выберите провайдера</h5>
                        
                        <label class="radio-card">
                            <input type="radio" name="provider" value="1" checked>
                            <strong>1) telemost (Yandex)</strong> <span class="text-success">— стабильно работает</span>
                        </label>
                        <label class="radio-card">
                            <input type="radio" name="provider" value="2">
                            <strong>2) wbstream (Wildberries)</strong> <span class="text-muted">— работает, но не у всех и не всегда</span>
                        </label>
                        <label class="radio-card">
                            <input type="radio" name="provider" value="3">
                            <strong>3) jazz (Sber SaluteJazz)</strong> <span class="text-danger">— пока НЕ работает (система блокирует от VPS)</span>
                        </label>
                    </div>

                    <div class="mb-4">
                        <h5 class="step-header">Шаг 2: Выберите тип транспорта</h5>
                        <div class="alert alert-danger py-2 px-3 mb-3 small">
                            ⚠️ Для Telemost провайдера: datachannel и seichannel - не поддерживаются!
                        </div>
                        
                        <label class="radio-card">
                            <input type="radio" name="transport" value="1" checked>
                            <strong>1) vp8channel</strong> <span class="badge bg-success ms-2">рекомендуется</span> <span class="text-muted ms-1">(высокая скорость)</span>
                        </label>
                        <label class="radio-card">
                            <input type="radio" name="transport" value="2">
                            <strong>2) videochannel</strong> <span class="text-muted ms-1">(низкая скорость)</span>
                        </label>
                    </div>

                    <div class="mb-4">
                        <h5 class="step-header">Шаг 3: Настройка ID звонка (комнаты)</h5>
                        
                        <div class="bg-light p-3 rounded border mb-3 small text-muted">
                            <strong>💡 Как получить ID звонка?</strong><br>
                            ID звонка — это идентификатор конференции, внутри которой прячется трафик.<br>
                            Создайте комнату и скопируйте ID (код в конце ссылки) или вставьте ссылку целиком:<br>
                            ▶ WB Stream: <code>https://stream.wb.ru/room/[ваш_id]</code><br>
                            ▶ Yandex Telemost: <code>https://telemost.yandex.ru/j/[ваш_id]</code><br>
                            ▶ SaluteJazz: <code>https://salutejazz.ru/calls/[ваш_id]</code>
                        </div>

                        <label class="form-label fw-bold">Введите ID звонка или полную ссылку:</label>
                        <input type="text" id="roomLink" class="form-control form-control-lg border-primary shadow-sm" placeholder="Например: https://telemost.yandex.ru/j/36561031851482">
                    </div>

                    <div class="d-flex justify-content-between mt-4 border-top pt-3">
                        <button type="button" class="btn btn-light border" onclick="showView('view-menu')">← Назад в меню</button>
                        <button type="button" class="btn btn-primary px-5" onclick="installBot()">Установить и Запустить</button>
                    </div>
                </form>
            </div>

            <div id="view-logs" class="view p-4">
                <div class="d-flex justify-content-between align-items-center mb-3">
                    <h5 class="mb-0 text-primary fw-bold">Системные логи (journalctl)</h5>
                    <button class="btn btn-sm btn-light border" onclick="showView('view-menu')">← Назад</button>
                </div>
                <div id="log-output" class="console-box mb-3">Загрузка логов...</div>
                <button class="btn btn-outline-primary w-100" onclick="openLogs()">🔄 Обновить логи</button>
            </div>

            <div id="view-info" class="view p-4">
                <div class="d-flex justify-content-between align-items-center mb-4 border-bottom pb-3">
                    <h5 class="mb-0 text-primary fw-bold">Статус и Реквизиты</h5>
                    <button class="btn btn-sm btn-light border" onclick="showView('view-menu')">← Назад</button>
                </div>
                
                <div class="mb-4">
                    <span class="text-muted">Статус службы systemd:</span><br>
                    <span id="status-badge" class="badge bg-secondary fs-6 mt-1">Проверка...</span>
                </div>

                <div class="bg-light p-3 rounded border">
                    <div class="mb-3">
                        <small class="text-muted d-block">Установленный провайдер:</small>
                        <strong id="info-platform" class="fs-5 text-dark">-</strong>
                    </div>
                    <div class="mb-3">
                        <small class="text-muted d-block">Тип транспорта:</small>
                        <strong id="info-tunnel" class="fs-5 text-dark">-</strong>
                    </div>
                    <div>
                        <small class="text-muted d-block">ID звонка / Ссылка:</small>
                        <strong id="info-link" class="text-primary" style="word-break: break-all;">-</strong>
                    </div>
                </div>
            </div>

        </div>
    </div>

    <script>
        function showView(id) {
            document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
            document.getElementById(id).classList.add('active');
        }

        async function installBot() {
            let link = document.getElementById('roomLink').value;
            if(!link) { alert('Пожалуйста, введите ID звонка или ссылку!'); return; }

            let provider = document.querySelector('input[name="provider"]:checked').value;
            let transport = document.querySelector('input[name="transport"]:checked').value;

            let config = { provider: provider, transport: transport, roomLink: link };
            
            let btn = event.target;
            let oldText = btn.innerText;
            btn.innerText = "Установка..."; btn.disabled = true;

            await fetch('/api/install', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(config)
            });

            btn.innerText = oldText; btn.disabled = false;
            alert('Установка успешно завершена! Служба запущена.');
            openInfo();
        }

        async function deleteService() {
            if(confirm("Вы действительно хотите удалить службу OlcRTC?")) {
                await fetch('/api/delete');
                alert('Служба удалена.');
            }
        }

        async function openLogs() {
            showView('view-logs');
            let res = await fetch('/api/logs');
            let text = await res.text();
            let logBox = document.getElementById('log-output');
            logBox.innerText = text || "Служба не запущена или логов нет.";
            logBox.scrollTop = logBox.scrollHeight;
        }

        async function openInfo() {
            showView('view-info');
            
            let resStatus = await fetch('/api/status');
            let dataStatus = await resStatus.json();
            let badge = document.getElementById('status-badge');
            if(dataStatus.active) {
                badge.className = 'badge bg-success'; badge.innerText = 'Активна (Online)';
            } else {
                badge.className = 'badge bg-danger'; badge.innerText = 'Остановлена (Offline)';
            }

            let resInfo = await fetch('/api/info');
            let dataInfo = await resInfo.json();
            
            if(dataInfo.error) {
                document.getElementById('info-platform').innerText = "Не настроено";
                document.getElementById('info-tunnel').innerText = "-";
                document.getElementById('info-link').innerText = "-";
            } else {
                document.getElementById('info-platform').innerText = dataInfo.platform;
                document.getElementById('info-tunnel').innerText = dataInfo.tunnel;
                document.getElementById('info-link').innerText = dataInfo.link;
            }
        }
    </script>
</body>
</html>
EOF

echo -e "\e[34m[5/6] Компиляция панели...\e[0m"
go build -o olc-ui-bin main.go

echo -e "\e[34m[6/6] Перезапуск службы...\e[0m"
systemctl daemon-reload
systemctl restart olc-ui

IP=$(curl -s ifconfig.me)
echo -e "\e[32m=======================================================\e[0m"
echo -e "✅ ГРАФИЧЕСКИЙ ИНТЕРФЕЙС И GO УСТАНОВЛЕНЫ!"
echo -e "🌐 Откройте в браузере:"
echo -e "👉 \e[1;36mhttp://$IP:8080\e[0m"
echo -e "\e[32m=======================================================\e[0m"
