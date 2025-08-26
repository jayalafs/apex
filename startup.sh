#!/bin/bash
set -euo pipefail

# ========= helpers =========
sql_sys() {
  sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<'SQL'
SET HEADING OFF FEEDBACK OFF ECHO OFF PAGES 0 LINES 200 TRIMSPOOL ON SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SQL
}

sql_sys_inline() {
  local block="$1"
  sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<SQL
SET HEADING OFF FEEDBACK OFF ECHO OFF PAGES 0 LINES 200 TRIMSPOOL ON SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE
${block}
EXIT;
SQL
}

echo "===================================================="
echo "[INFO] Arranque de APEX + ORDS + Tomcat"
echo "===================================================="

# Variables requeridas
: "${ORACLE_PWD:?ORACLE_PWD no definido}"
: "${DB_HOST:?DB_HOST no definido}"
: "${DB_PORT:?DB_PORT no definido}"
: "${DB_SERVICE:?DB_SERVICE no definido}"
: "${SYSDBA_USER:?SYSDBA_USER no definido}"
: "${ORDS_USER:?ORDS_USER no definido}"
: "${ORDS_PWD:?ORDS_PWD no definido}"
: "${ORDS_CONFIG:?ORDS_CONFIG no definido}"
: "${APEX_VERSION:?APEX_VERSION no definido}"
: "${APEX_ADMIN:?APEX_ADMIN no definido}"
: "${APEX_ADMIN_PWD:?APEX_ADMIN_PWD no definido}"

# ========= Esperar a que el PDB esté READ WRITE =========
echo "[INFO] Esperando a que Oracle DB (${DB_HOST}:${DB_PORT}/${DB_SERVICE}) esté READ WRITE..."
until sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF | grep -q "READ WRITE"
SET HEADING OFF FEEDBACK OFF
SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');
EXIT;
EOF
do
  echo "[WARN] El PDB ${DB_SERVICE} aún no está en modo READ WRITE. Reintentando en 20s..."
  sleep 20
done
echo "[INFO] DB lista."

# ========= Instalar APEX si no existe =========
APEX_HOME="/opt/oracle/apex"
if ! sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<'EOF' | grep -q "1"
SET FEEDBACK OFF HEADING OFF
SELECT 1 FROM dba_users WHERE username='APEX_240100';
EXIT;
EOF
then
  echo "[INFO] APEX 24.1 no detectado, procediendo a descargar e instalar..."
  mkdir -p "${APEX_HOME}"
  if [ ! -f "${APEX_HOME}/apexins.sql" ]; then
    echo "[INFO] Descargando APEX ${APEX_VERSION}..."
    curl -L -o /tmp/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip"
    unzip -o /tmp/apex.zip -d /tmp/apex
    # mover al destino (algunos zips vienen con carpeta apex/apex/*)
    if [ -d "/tmp/apex/apex" ]; then
      mv /tmp/apex/apex/* "${APEX_HOME}/"
    else
      mv /tmp/apex/* "${APEX_HOME}/"
    fi
    rm -rf /tmp/apex /tmp/apex.zip
  fi

  echo "[INFO] Instalando APEX en ${DB_SERVICE} (SYSAUX,SYSAUX,TEMP,/i/)..."
  sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
@${APEX_HOME}/apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF
else
  echo "[INFO] APEX ya instalado, saltando instalación."
fi

# ========= Configurar ADMIN de APEX =========
# Intento no-interactivo: cambia (o crea si corresponde) la password del ADMIN y asigna email.
echo "[INFO] Configurando ADMIN de APEX y email..."
sql_sys_inline "
DECLARE
  l_admin_exists NUMBER;
BEGIN
  -- Verificar existencia de ADMIN
  SELECT COUNT(*) INTO l_admin_exists
    FROM apex_workspace_admins
   WHERE user_name = UPPER('${APEX_ADMIN}');

  IF l_admin_exists = 0 THEN
    -- Crear ADMIN en INTERNAL si no existe (requiere APEX 20.2+)
    apex_instance_admin.add_user(
      p_user_name      => '${APEX_ADMIN}',
      p_web_password   => '${APEX_ADMIN_PWD}',
      p_email_address  => '${APEX_ADMIN_EMAIL}',
      p_developer_privs=> 'ADMIN:CREATE:MONITOR:SQL'
    );
  ELSE
    -- Cambiar password si ya existe
    apex_util.set_security_group_id(10); -- INTERNAL
    apex_util.change_password(
      p_user_name    => '${APEX_ADMIN}',
      p_new_password => '${APEX_ADMIN_PWD}'
    );
    apex_util.set_security_group_id(null);
  END IF;
  -- Actualiza email del ADMIN (si fue provisto)
  BEGIN
    IF '${APEX_ADMIN_EMAIL}' IS NOT NULL THEN
      apex_instance_admin.set_parameter('ADMIN_EMAIL','${APEX_ADMIN_EMAIL}');
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
"

# ========= Desbloquear APEX_PUBLIC_USER =========
echo "[INFO] Desbloqueando ${ORDS_USER}..."
sql_sys_inline "ALTER USER ${ORDS_USER} IDENTIFIED BY \"${ORDS_PWD}\" ACCOUNT UNLOCK;"

# ========= Descargar y preparar ORDS =========
if [ ! -x /opt/oracle/ords/bin/ords ]; then
  echo "[INFO] Descargando ORDS (WAR) y expandiendo..."
  curl -L -o /opt/oracle/ords.war "https://download.oracle.com/java/ords/ords-latest.war"
  mkdir -p /opt/oracle/ords
  unzip -q -o /opt/oracle/ords.war -d /opt/oracle/ords/
fi

# ========= Instalar ORDS (config externa) =========
echo "[INFO] Instalando/actualizando ORDS en modo proxied..."
rm -rf "${ORDS_CONFIG:?}/"* || true
mkdir -p "${ORDS_CONFIG}"
chmod -R 777 "${ORDS_CONFIG}"

# Instalación (idempotente, si existe reconfigura)
# NOTA: --config asegura que usemos el volumen persistente
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

# ========= Mapear /apex si no existe =========
if [ ! -f "${ORDS_CONFIG}/databases/${DB_SERVICE}/mappings/apex.json" ]; then
  echo "[INFO] Asignando mapping /apex al PDB ${DB_SERVICE}..."
  /opt/oracle/ords/bin/ords --config "${ORDS_CONFIG}" map-url \
    --pdb "${DB_SERVICE}" \
    --url-path apex
fi

# ========= Desplegar ords.war en Tomcat =========
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/ords.war
chmod 644 /usr/local/tomcat/webapps/ords.war

# ========= Copiar imágenes estáticas de APEX (/i) =========
if [ -d "${APEX_HOME}/images" ]; then
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r "${APEX_HOME}/images/"* /usr/local/tomcat/webapps/i/
else
  echo "[ERROR] No se encontraron imágenes estáticas de APEX en ${APEX_HOME}/images"
  exit 1
fi

# ========= Lanzar Tomcat =========
echo "[INFO] Inicio completo. Levantando Tomcat..."
exec catalina.sh run