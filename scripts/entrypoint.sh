#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# ===== helpers =====
log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }
die() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

# ===== env requeridas =====
: "${ORACLE_PWD:?ORACLE_PWD no definido}"
: "${DB_HOST:?DB_HOST no definido}"
: "${DB_PORT:?DB_PORT no definido}"
: "${DB_SERVICE:?DB_SERVICE no definido}"
: "${SYSDBA_USER:?SYSDBA_USER no definido}"        # normalmente 'sys'
: "${ORDS_USER:?ORDS_USER no definido}"            # ORDS_PUBLIC_USER recomendado
: "${ORDS_PWD:?ORDS_PWD no definido}"
: "${ORDS_CONFIG:?ORDS_CONFIG no definido}"
: "${APEX_VERSION:?APEX_VERSION no definido}"      # ej: 24.1
: "${APEX_ADMIN:?APEX_ADMIN no definido}"          # ej: ADMIN
: "${APEX_ADMIN_PWD:?APEX_ADMIN_PWD no definido}"
APEX_ADMIN_EMAIL="${APEX_ADMIN_EMAIL:-}"           # opcional
CLEAN_ORDS_CONFIG="${CLEAN_ORDS_CONFIG:-true}"

# Derivar APEX_SCHEMA desde APEX_VERSION (24.1 -> APEX_240100)
APEX_SCHEMA="APEX_$(echo "${APEX_VERSION}" | awk -F. '{m=$1+0; n=($2=="")?0:$2; printf("%02d%02d00", m, n)}')"
log "APEX_VERSION=${APEX_VERSION} -> APEX_SCHEMA=${APEX_SCHEMA}"

# “sentry” por si accidentalmente se copió YAML aquí
if head -n1 "$0" | grep -q "^services:"; then
  die "Este entrypoint contiene YAML (docker-compose). Revisa tu build/volúmenes."
fi

# ===== funciones SQL (SQLcl) =====
sql_sys() {
  sql -S "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba"
}
sql_sys_inline() {
  local block="$1"
  sql -S "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<SQL
SET HEADING OFF FEEDBACK OFF ECHO OFF PAGES 0 LINES 200 TRIMSPOOL ON SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE
${block}
EXIT;
SQL
}

log "Arranque APEX + ORDS + Tomcat (SQLcl)"

# ===== esperar PDB READ WRITE =====
log "Esperando a DB ${DB_HOST}:${DB_PORT}/${DB_SERVICE} (READ WRITE)…"
until sql_sys <<EOF | grep -q "READ WRITE"
SET HEADING OFF FEEDBACK OFF
SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');
EXIT;
EOF
do
  log "PDB aún no READ WRITE. Reintento en 20s…"
  sleep 20
done
log "DB lista."

# ===== instalar APEX si no existe =====
APEX_HOME="/opt/oracle/apex"
apex_instalado=$(sql_sys <<EOF | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_users WHERE username = UPPER('${APEX_SCHEMA}');
EXIT;
EOF
)
if [ "${apex_instalado}" != "1" ]; then
  log "APEX (${APEX_VERSION}) no detectado. Descargando/instalando…"

  # Usar artifacts si están montados; si no, descargar
  ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
  if [ -f "${ARTIFACTS_DIR}/apex_${APEX_VERSION}.zip" ]; then
    log "Usando ${ARTIFACTS_DIR}/apex_${APEX_VERSION}.zip"
    cp "${ARTIFACTS_DIR}/apex_${APEX_VERSION}.zip" /tmp/apex.zip
  else
    curl -L -o /tmp/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip"
  fi

  mkdir -p "${APEX_HOME}"
  unzip -q /tmp/apex.zip -d /tmp/apex
  if [ -d "/tmp/apex/apex" ]; then
    mv /tmp/apex/apex/* "${APEX_HOME}/"
  else
    mv /tmp/apex/* "${APEX_HOME}/"
  fi
  rm -rf /tmp/apex /tmp/apex.zip

  log "Instalando APEX (SYSAUX,SYSAUX,TEMP,/i/)… esto puede tardar"
  sql_sys <<EOF
@${APEX_HOME}/apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF
else
  log "APEX ya instalado (${APEX_SCHEMA})."
fi

# ===== esperar vistas APEX y configurar ADMIN =====
log "Esperando a que APEX exponga vistas…"
until sql_sys <<EOF | grep -q "READY"
SET HEADING OFF FEEDBACK OFF
SELECT 'READY'
  FROM dba_views
 WHERE owner = UPPER('${APEX_SCHEMA}')
   AND view_name = 'APEX_WORKSPACE_USERS';
EXIT;
EOF
do
  log "Aún no disponibles vistas de APEX en ${APEX_SCHEMA}. Reintento en 10s…"
  sleep 10
done
log "Vistas APEX listas."

log "Configurando usuario ADMIN (${APEX_ADMIN}) en workspace INTERNAL…"
sql_sys <<EOF
SET HEADING OFF FEEDBACK OFF ECHO OFF PAGES 0 LINES 200 TRIMSPOOL ON SERVEROUTPUT ON;

ALTER SESSION SET CURRENT_SCHEMA = ${APEX_SCHEMA};

DECLARE
  l_ws_id   NUMBER;
  l_exists  NUMBER := 0;
BEGIN
  -- Entrar al workspace INTERNAL
  l_ws_id := apex_util.find_security_group_id(p_workspace => 'INTERNAL');
  apex_util.set_security_group_id(l_ws_id);

  -- ¿Existe ADMIN?
  BEGIN
    SELECT 1 INTO l_exists
      FROM apex_workspace_users
     WHERE user_name = UPPER('${APEX_ADMIN}')
       AND security_group_id = l_ws_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    l_exists := 0;
  END;

  IF l_exists = 0 THEN
    apex_util.create_user(
      p_user_name                    => '${APEX_ADMIN}',
      p_web_password                 => '${APEX_ADMIN_PWD}',
      p_email_address                => '${APEX_ADMIN_EMAIL}',
      p_developer_privs              => 'ADMIN:CREATE:MONITOR:SQL',
      p_change_password_on_first_use => 'N'
    );
  ELSE
    apex_util.edit_user(
      p_user_name     => '${APEX_ADMIN}',
      p_web_password  => '${APEX_ADMIN_PWD}',
      p_email_address => '${APEX_ADMIN_EMAIL}'
    );
  END IF;

  apex_util.set_security_group_id(NULL);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line('[WARN] No se pudo crear/editar ADMIN: '||SQLERRM);
END;
/
EXIT;
EOF
log "ADMIN configurado (o ya existente)."

# ===== desbloquear usuarios gateway =====
log "Desbloqueando ORDS_PUBLIC_USER y APEX_PUBLIC_USER…"
sql_sys_inline "ALTER USER ORDS_PUBLIC_USER IDENTIFIED BY \"${ORDS_PWD}\" ACCOUNT UNLOCK;"
sql_sys_inline "ALTER USER APEX_PUBLIC_USER IDENTIFIED BY \"${ORDS_PWD}\" ACCOUNT UNLOCK;"

# ===== ORDS: descargar/preparar si no existe =====
if [ ! -x /opt/oracle/ords/bin/ords ]; then
  log "Preparando ORDS…"
  ARTIFACTS_DIR="${ARTIFACTS_DIR:-/artifacts}"
  if [ -f "${ARTIFACTS_DIR}/ords-latest.war" ]; then
    log "Usando ${ARTIFACTS_DIR}/ords-latest.war"
    cp "${ARTIFACTS_DIR}/ords-latest.war" /opt/oracle/ords.war
  else
    curl -L -o /opt/oracle/ords.war "https://download.oracle.com/java/ords/ords-latest.war"
  fi
  mkdir -p /opt/oracle/ords
  unzip -q -o /opt/oracle/ords.war -d /opt/oracle/ords/
fi

# ===== ORDS: instalar / reconfigurar (modo proxied) =====
log "Instalando/actualizando ORDS (proxied)…"
if [ "${CLEAN_ORDS_CONFIG}" = "true" ]; then
  rm -rf "${ORDS_CONFIG:?}/"* || true
fi
mkdir -p "${ORDS_CONFIG}"
chmod -R 777 "${ORDS_CONFIG}"

/opt/oracle/ords/bin/ords --config "${ORDS_CONFIG}" install \
  --admin-user "${SYSDBA_USER}" \
  --db-hostname "${DB_HOST}" \
  --db-port "${DB_PORT}" \
  --db-servicename "${DB_SERVICE}" \
  --gateway-mode proxied \
  --gateway-user "${ORDS_USER}" \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin <<EOF
${ORDS_PWD}
${ORDS_PWD}
EOF

# Map /apex si no existe
if [ ! -f "${ORDS_CONFIG}/databases/${DB_SERVICE}/mappings/apex.json" ]; then
  log "Asignando mapping /apex -> ${DB_SERVICE}"
  /opt/oracle/ords/bin/ords --config "${ORDS_CONFIG}" map-url \
    --pdb "${DB_SERVICE}" \
    --url-path apex
fi

# ===== desplegar ords.war e imágenes APEX =====
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/ords.war
chmod 644 /usr/local/tomcat/webapps/ords.war

if [ -d "${APEX_HOME}/images" ]; then
  log "Copiando imágenes de APEX a /usr/local/tomcat/webapps/i …"
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r "${APEX_HOME}/images/"* /usr/local/tomcat/webapps/i/
else
  die "No se encontraron imágenes de APEX en ${APEX_HOME}/images"
fi

# ===== lanzar Tomcat =====
log "Inicio completo. Lanzando Tomcat…"
exec catalina.sh run