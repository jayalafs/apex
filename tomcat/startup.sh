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
# Descargar e instalar ORDS
# =====================
echo "[INFO] Descargando ORDS..."

ORDS_VERSION=${ORDS_VERSION:-25.1.0.100.1652}
ORDS_DOWNLOAD_DIR="/opt/oracle/ords"
ORDS_CLI_PATH="$ORDS_DOWNLOAD_DIR/bin/ords"
ORDS_WAR_PATH="$ORDS_DOWNLOAD_DIR/ords.war"
ORDS_CONFIG="/etc/ords/config"

# Descargar ORDS completo si no existe
if [ ! -f "$ORDS_CLI_PATH" ]; then
  mkdir -p "$ORDS_DOWNLOAD_DIR" && cd "$ORDS_DOWNLOAD_DIR"
  curl -L -o ords.zip "https://download.oracle.com/otn_software/java/ords/ords-${ORDS_VERSION}.zip"
  unzip -q ords.zip
  chmod +x bin/ords
  rm -f ords.zip
fi

# Configuración de ORDS
mkdir -p "$ORDS_CONFIG"
chmod -R 777 "$ORDS_CONFIG"
export ORDS_CONFIG="$ORDS_CONFIG"

# =====================
# Ejecutar instalación
# =====================
echo "[INFO] Ejecutando instalación de ORDS..."

if [ -f "$ORDS_CLI_PATH" ]; then
  "$ORDS_CLI_PATH" install \
    --admin-user sys \
    --db-hostname "${DB_HOST}" \
    --db-port "${DB_PORT}" \
    --db-servicename "${DB_SERVICE}" \
    --gateway-mode proxied \
    --gateway-user APEX_PUBLIC_USER \
    --feature-sdw true \
    --feature-db-api true \
    --feature-rest-enabled-sql true \
    --password-stdin <<EOF
${ORACLE_PWD}
${ORACLE_PWD}
${ORACLE_PWD}
EOF

  echo "[INFO] ORDS instalado correctamente."
else
  echo "[ERROR] CLI de ORDS no encontrado en $ORDS_CLI_PATH"
  exit 1
fi

# =====================
# Desplegar en Tomcat
# =====================
if [ -f "$ORDS_WAR_PATH" ]; then
  cp "$ORDS_WAR_PATH" /usr/local/tomcat/webapps/ords.war
  echo "[INFO] ORDS.war desplegado en Tomcat."
else
  echo "[ERROR] ords.war no encontrado en $ORDS_WAR_PATH"
  exit 1
fi

echo "[INFO] Instalación finalizada con éxito."

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
