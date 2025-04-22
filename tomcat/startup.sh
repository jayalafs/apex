#!/bin/bash
set -e

echo "[INFO] Esperando a que Oracle DB esté disponible..."

# Espera robusta a que la base de datos esté completamente disponible
until sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF > /dev/null 2>&1
SET PAGESIZE 1
SELECT 'READY' FROM v\$instance WHERE status='OPEN';
EXIT;
EOF
do
  echo "[WARN] Oracle aún no está completamente operativa. Reintentando en 5s..."
  sleep 5
done

echo "[INFO] Oracle DB está disponible y abierta."

# Verificar que el listener esté operativo
echo "[INFO] Verificando listener con lsnrctl status..."
until echo "lsnrctl status" | sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" > /dev/null 2>&1
do
  echo "[WARN] Listener aún no responde, reintentando en 5s..."
  sleep 5
done

echo "[INFO] Listener activo. Iniciando instalación de APEX y ORDS..."

# =====================
# Instalar APEX
# =====================
if [ -d /opt/oracle/apex ]; then
  echo "[INFO] Instalando APEX..."
  cd /opt/oracle/apex
  sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF
else
  echo "[ERROR] No se encontró /opt/oracle/apex"
  exit 1
fi

# =====================
# Desbloquear APEX_PUBLIC_USER
# =====================
sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${ORACLE_PWD} ACCOUNT UNLOCK;
EXIT;
EOF

# =====================
# Crear usuario ADMIN de APEX
# =====================
sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
BEGIN
  APEX_UTIL.set_security_group_id(10);
  APEX_UTIL.create_user(
    p_user_name => '${APEX_ADMIN}',
    p_email_address => '${APEX_ADMIN_EMAIL}',
    p_web_password => '${APEX_ADMIN_PWD}',
    p_developer_privs => 'ADMIN'
  );
  COMMIT;
END;
/
EXIT;
EOF

# =====================
# Instalar ORDS
# =====================
cd /opt/oracle
if [ ! -d ords ]; then
  echo "[INFO] Descargando y extrayendo ORDS..."
  curl -L -o ords-${ORDS_VERSION}.zip https://download.oracle.com/otn_software/java/ords/ords-${ORDS_VERSION}.zip
  unzip -q ords-${ORDS_VERSION}.zip -d ords && rm -f ords-${ORDS_VERSION}.zip
fi

# =========================
# Preparar estructura de configuración
# =========================
mkdir -p /etc/ords/config

# =========================
# Configurar ORDS
# =========================
/opt/oracle/ords/bin/ords --config /etc/ords/config config set standalone.context.path /ords
/opt/oracle/ords/bin/ords --config /etc/ords/config config set standalone.http.port 8080
/opt/oracle/ords/bin/ords --config /etc/ords/config config set standalone.static.context.path /i
/opt/oracle/ords/bin/ords --config /etc/ords/config config set standalone.static.path /opt/oracle/apex/images/

# =========================
# Instalar ORDS con opciones predefinidas
# =========================
/opt/oracle/ords/bin/ords install \
  --config /etc/ords/config \
  --admin-user ${SYSDBA_USER} \
  --db-hostname ${DB_HOST} \
  --db-port ${DB_PORT} \
  --db-servicename ${DB_SERVICE} \
  --gateway-mode proxied \
  --gateway-user ${ORDS_USER} \
  --gateway-password ${ORDS_PWD} \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --feature-apex true \
  --proxy-user \
  --log-folder /opt/oracle/ords/logs \
  --schema-tablespace SYSAUX \
  --temp-tablespace TEMP \
  --password ${ORDS_PWD} \
  --pre-mapped

# =========================
# Desplegar en Tomcat
# =========================
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/ords.war

if [ ! -f /usr/local/tomcat/webapps/ords.war ]; then
  echo "[ERROR] El archivo ords.war no fue desplegado correctamente. Abortando."
  exit 1
fi

# =====================
# Copiar archivos estáticos de APEX
# =====================
if [ -d /opt/oracle/apex/images ]; then
  echo "[INFO] Copiando imágenes estáticas de APEX..."
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r /opt/oracle/apex/images/* /usr/local/tomcat/webapps/i/
else
  echo "[ERROR] Carpeta de imágenes de APEX no encontrada."
  exit 1
fi

# =========================
# Iniciar Tomcat
# =========================
echo "[INFO] Instalación completa. Iniciando Tomcat en primer plano..."
exec catalina.sh run
