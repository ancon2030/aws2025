#!/bin/bash
set -euxo pipefail

# ==== 1) Actualizar e instalar dependencias ====
dnf -y update
dnf -y install python3 nmap-ncat tmux

# Asegurar que el comando 'nc' exista aunque el paquete provea 'ncat'
if [ ! -x /usr/bin/nc ] && [ -x /usr/bin/ncat ]; then
  ln -sf /usr/bin/ncat /usr/bin/nc
fi

# ==== 2) Preparar directorio de trabajo para el laboratorio ====
LAB_DIR="/home/ec2-user/tabnapping_attack"
mkdir -p "$LAB_DIR"
chown -R ec2-user:ec2-user "$LAB_DIR"

# Archivo HTML de prueba (opcional) para validar el puerto 80
cat > "$LAB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Lab HTTP 80 – Amazon Linux 2023</title>
</head>
<body>
  <h1>Servidor HTTP activo</h1>
  <p>Si ves esta página, el servidor Python en el puerto 80 funciona.</p>
</body>
</html>
HTML
chown ec2-user:ec2-user "$LAB_DIR/index.html"

# ==== 3) Script opcional para lanzar ambos servicios en tmux ====
# (Útil si quieres que arranquen en dos ventanas listas)
cat > /home/ec2-user/start_lab.sh <<'SH'
#!/bin/bash
set -euo pipefail
SESSION="tablab"
cd ~/tabnapping_attack

# Crear sesión con servidor HTTP en puerto 80 (requiere sudo)
tmux new-session -d -s "$SESSION" -c "$PWD" 'sudo python3 -m http.server 80'

# Nueva ventana con nc escuchando en 8000
tmux new-window  -t "$SESSION:1" -c "$PWD" 'nc -lvnp 8000'

echo "Sesión tmux '$SESSION' creada con:"
echo " - Ventana 0: sudo python3 -m http.server 80"
echo " - Ventana 1: nc -lvnp 8000"
echo "Para adjuntar: tmux attach -t $SESSION"
SH
chmod +x /home/ec2-user/start_lab.sh
chown ec2-user:ec2-user /home/ec2-user/start_lab.sh

# ==== 4) Mensaje de bienvenida con recordatorio ====
cat > /etc/motd <<'MOTD'
========================================================
Amazon Linux 2023 listo para el laboratorio (HTTP 80 + nc 8000)

Carpeta:  ~/tabnapping_attack
Archivo:  ~/tabnapping_attack/index.html

Manualmente:
  Terminal 1:
    cd ~/tabnapping_attack
    sudo python3 -m http.server 80

  Terminal 2:
    cd ~/tabnapping_attack
    nc -lvnp 8000

Atajo con tmux (opcional):
  /home/ec2-user/start_lab.sh
  (Luego: tmux attach -t tablab)

Recuerda: abre en el Security Group los puertos 80 y 8000
desde tu IP (o el rango que corresponda a tu práctica).
========================================================
MOTD
