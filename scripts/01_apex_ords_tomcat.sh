#!/bin/bash
set -euo pipefail

log(){ printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

# ====== Entradas (con defaults sensatos) ======
TZ="${TZ:-America/Asuncion}"
ORACLE_PWD="${ORACLE_PWD:?Debes definir ORACLE_PWD (variable de la imagen)}"
DB_SERVICE="${DB_SERVICE:-FREEPDB1}"

APEX_ADMIN_PWD="${APEX_ADMIN_PWD:-}"         # si lo dejas vacío, igual se crea ADMIN (puedes cambiar luego)
APEX_ADMIN_EMAIL="${APEX_ADMIN_EMAIL:-}"

ORDS_PWD="${ORDS_PWD:-Oracle123}"
HTTP_PORT="${HTTP_PORT:-8080}"

# Para Tomcat 10
TOMCAT_VER="${TOMCAT_VER:-10.1.26}"
CATALINA_HOME="/opt/tomcat"

export TZ

log "=== APEX + ORDS (Tomcat) — imagen oficial Oracle DB — DB_SERVICE=${DB_SERVICE} ==="

# ====== Helper SQL local (sqlplus / as sysdba) ======
sql_root() {
  sqlplus -s / as sysdba <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGES 0 LINES 200 TRIMSPOOL ON
WHENEVER SQLERROR EXIT SQL.SQLCODE
SQL
}
sql_root_inline() {
  local block="$1"
  sqlplus -s / as sysdba <<SQL
SET HEADING OFF FEEDBACK OFF PAGES 0 LINES 200 TRIMSPOOL ON
WHENEVER SQLERROR EXIT SQL.SQLCODE
${block}
EXIT;
SQL
}

# ====== Esperar a que el PDB esté READ WRITE ======
log "[DB] Esperando a que ${DB_SERVICE} esté READ WRITE…"
until sqlplus -s / as sysdba <<EOF | grep -q "READ WRITE"
SET HEADING OFF FEEDBACK OFF
SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');
EXIT;
EOF
do
  log "[DB] Aún no READ WRITE; reintento en 10s…"
  sleep 10
done
log "[DB] ${DB_SERVICE} READ WRITE ✓"

# ====== Descargar e instalar APEX (como en tu script) ======
cd /home/oracle
if [ ! -d "/home/oracle/apex" ]; then
  log "[APEX] Descargando apex-latest.zip…"
  curl -fSL -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip
  unzip -q apex-latest.zip
  rm -f apex-latest.zip
fi

log "[APEX] Ejecutando apexins.sql en ${DB_SERVICE}… (SYSAUX,SYSAUX,TEMP,/i/)"
sql_root_inline "
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
@/home/oracle/apex/apexins.sql SYSAUX SYSAUX TEMP /i/
"

# ====== Desbloquear APEX_PUBLIC_USER (igual a tu script) ======
log "[APEX] Desbloqueando APEX_PUBLIC_USER…"
sql_root_inline "
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY \"${ORDS_PWD}\";
"

# ====== Crear ADMIN (igual a tu script, usando INTERNAL y APEX_UTIL) ======
log "[APEX] Creando/ajustando ADMIN en INTERNAL…"
sql_root_inline "
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
BEGIN
  APEX_UTIL.set_security_group_id(10); -- INTERNAL
  -- si no existe, lo crea; si existe, re-asigna password y email
  BEGIN
    APEX_UTIL.create_user(
      p_user_name       => 'ADMIN',
      p_email_address   => '${APEX_ADMIN_EMAIL}',
      p_web_password    => '${APEX_ADMIN_PWD}',
      p_developer_privs => 'ADMIN');
  EXCEPTION WHEN OTHERS THEN
    NULL; -- si ya existe, seguimos
  END;
  -- intentar editar credenciales si existe
  BEGIN
    APEX_UTIL.edit_user(
      p_user_name     => 'ADMIN',
      p_web_password  => '${APEX_ADMIN_PWD}',
      p_email_address => '${APEX_ADMIN_EMAIL}');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  APEX_UTIL.set_security_group_id(NULL);
  COMMIT;
END;
/
"

# ====== Preparar carpetas (como en tu script) ======
log "[FS] Creando carpetas de trabajo…"
/bin/mkdir -p /home/oracle/software/apex /home/oracle/software/ords /home/oracle/scripts
/bin/cp -r /home/oracle/apex/images /home/oracle/software/apex || true

# ====== Instalar utilidades y Java 17 (igual al patrón de tu script) ======
log "[SYS] Instalando utilidades y Java 17… (puede tardar)"
su - <<'EOS'
set -e
# evitar que dnf espere región en OCI
: > /etc/dnf/vars/ociregion || true
dnf -y update
dnf -y install sudo nano java-17-openjdk yum-utils
EOS

# ====== Repos y ORDS RPM (igual a tu script, desde Oracle Yum) ======
log "[ORDS] Instalando ORDS desde Oracle Yum…"
su - <<'EOS'
set -e
yum-config-manager --add-repo=https://yum.oracle.com/repo/OracleLinux/OL8/oracle/software/x86_64
dnf -y install ords
EOS

# ====== Config ORDS (misma instalación en modo proxied) ======
export ORDS_CONFIG=/etc/ords/config
export DB_PORT=1521
export DB_SERVICE="${DB_SERVICE}"
export SYSDBA_USER=SYS
/bin/mkdir -p "${ORDS_CONFIG}" /home/oracle/logs
chmod -R 777 "${ORDS_CONFIG}"

log "[ORDS] Configurando ORDS (proxied) contra ${DB_SERVICE}…"
/usr/bin/ords --config "${ORDS_CONFIG}" install \
  --admin-user "${SYSDBA_USER}" \
  --db-hostname "${HOSTNAME}" \
  --db-port "${DB_PORT}" \
  --db-servicename "${DB_SERVICE}" \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --feature-sdw true \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --password-stdin <<EOT
${ORDS_PWD}
${ORDS_PWD}
EOT

# IMPORTANTÍSIMO: mapear /apex al PDB (como venías haciendo implícito en standalone)
/usr/bin/ords --config "${ORDS_CONFIG}" map-url --pdb "${DB_SERVICE}" --url-path apex || true

# ====== Instalar Tomcat 10 y desplegar ORDS en WAR ======
log "[TC] Instalando Tomcat ${TOMCAT_VER}…"
su - <<EOS
set -e
cd /opt
curl -fSL --retry 5 --retry-all-errors \
  -o /tmp/tomcat.tgz "https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz"
tar -xzf /tmp/tomcat.tgz
mv "apache-tomcat-${TOMCAT_VER}" "${CATALINA_HOME}"
rm -f /tmp/tomcat.tgz
# setenv.sh con puntero a /etc/ords/config
cat > ${CATALINA_HOME}/bin/setenv.sh <<'SH'
export CATALINA_OPTS="${CATALINA_OPTS} -Dords.config.dir=/etc/ords/config -Xms512m -Xmx1024m"
SH
chmod +x ${CATALINA_HOME}/bin/setenv.sh
EOS

# Localiza ords.war del RPM (puede variar de ruta según versión)
/bin/echo "[TC] Buscando ords.war instalado por RPM…"
ORDS_WAR="$(rpm -ql ords 2>/dev/null | grep '/ords\.war$' | head -n1 || true)"
if [ -z "${ORDS_WAR}" ]; then
  # fallback: buscarlo
  ORDS_WAR="$(find / -maxdepth 5 -name 'ords.war' 2>/dev/null | head -n1 || true)"
fi
if [ -z "${ORDS_WAR}" ]; then
  echo "[ERROR] No se encontró ords.war del paquete ORDS. Aborto."
  exit 1
fi
/bin/mkdir -p "${CATALINA_HOME}/webapps"
/bin/cp -f "${ORDS_WAR}" "${CATALINA_HOME}/webapps/ords.war"

# Copiar imágenes estáticas de APEX a /i (Tomcat)
/bin/mkdir -p "${CATALINA_HOME}/webapps/i"
/bin/cp -r /home/oracle/apex/images/* "${CATALINA_HOME}/webapps/i/" || true

# ====== Arrancar Tomcat (detached) y esperar 8080 ======
log "[TC] Arrancando Tomcat en puerto ${HTTP_PORT}…"
# nos aseguramos de owns
chown -R oracle:oinstall "${CATALINA_HOME}" || true
nohup "${CATALINA_HOME}/bin/catalina.sh" start >/opt/tomcat/logs/boot.log 2>&1 || true

log "[TC] Esperando a que 127.0.0.1:8080 quede escuchando…"
ok=0
for i in $(seq 1 24); do
  if bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080' 2>/dev/null; then ok=1; break; fi
  sleep 5
done
if [ "$ok" -eq 1 ]; then
  log "[TC] Tomcat arriba ✓  ->  http://localhost:${HTTP_PORT}/ords"
else
  log "[TC][ERROR] Tomcat NO subió en 120s. Últimas líneas de log:"
  tail -n 200 /opt/tomcat/logs/boot.log || true
  tail -n 200 /opt/tomcat/logs/catalina.out || true
fi

log "ENDPOINTS:"
log "  ORDS:  http://localhost:${HTTP_PORT}/ords"
log "  APEX:  http://localhost:${HTTP_PORT}/ords/apex"