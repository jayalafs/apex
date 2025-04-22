#!/bin/bash

set -e

echo "[INFO] Esperando a que Oracle DB esté disponible..."

until echo "SELECT 1 FROM DUAL;" | sqlplus -s sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba > /dev/null 2>&1
do
  echo "[WARN] Oracle no responde aún, reintentando en 5s..."
  sleep 5
done

echo "[INFO] Oracle DB está disponible, iniciando instalación de APEX y ORDS..."

# =====================
# Instalar APEX
# =====================
if [ -d /opt/oracle/apex ]; then
  echo "[INFO] Instalando APEX..."
  cd /opt/oracle/apex
  sqlplus -s sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba <<EOF
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
sqlplus -s sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${ORACLE_PWD} ACCOUNT UNLOCK;
EXIT;
EOF

# =====================
# Crear usuario ADMIN de APEX
# =====================
sqlplus -s sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba <<EOF
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
if [ -f /opt/oracle/ords/ords.war ]; then
  echo "[INFO] Ejecutando instalación de ORDS..."
  cd /opt/oracle/ords
  java -jar ords.war install \
    --admin-user sys \
    --db-hostname ${DB_HOST} \
    --db-port ${DB_PORT} \
    --db-servicename ${DB_SERVICE} \
    --gateway-mode proxied \
    --gateway-user APEX_PUBLIC_USER \
    --feature-sdw true \
    --feature-db-api true \
    --feature-rest-enabled-sql true \
    --password-stdin <<EOF
${ORACLE_PWD}
${ORACLE_PWD}
EOF
else
  echo "[ERROR] ORDS no encontrado en /opt/oracle/ords/ords.war"
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

echo "[INFO] Iniciando Tomcat..."
exec catalina.sh run