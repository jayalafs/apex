#!/bin/bash

set -e

start_time=$(date +%s)

# Variables
APEX_ZIP="apex_24.1.zip"
APEX_URL="https://download.oracle.com/otn_software/apex/${APEX_ZIP}"
APEX_PWD="Oracle123"
ORDS_ZIP="ords-25.1.0.100.1652.zip"
ORDS_URL="https://download.oracle.com/otn_software/java/ords/${ORDS_ZIP}"
INSTANTCLIENT_VERSION="23_7"
SYSUSER="sys/${APEX_PWD}@oracle-db:1521/FREEPDB1 as sysdba"

# Instalar dependencias
apt update && apt install -y unzip curl libaio1

# Crear estructura de carpetas
mkdir -p /opt/oracle && cd /opt/oracle

# =====================
# Instalar SQL*Plus
# =====================

echo ">> Instalando Oracle Instant Client + SQL*Plus"

curl -O https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linux.x64-23.7.0.0.0dbru.zip
curl -O https://download.oracle.com/otn_software/linux/instantclient/instantclient-sqlplus-linux.x64-23.7.0.0.0dbru.zip

unzip -q instantclient-basiclite-*.zip
unzip -q instantclient-sqlplus-*.zip
rm -f instantclient-*.zip

cd instantclient_23_7

echo "/opt/oracle/instantclient_${INSTANTCLIENT_VERSION}" > /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig
export PATH=$PATH:/opt/oracle/instantclient_${INSTANTCLIENT_VERSION}

cd /opt/oracle

# =====================
# Descargar e instalar APEX
# =====================

echo ">> Descargando APEX..."
curl -o ${APEX_ZIP} ${APEX_URL}
unzip -q ${APEX_ZIP} && rm -f ${APEX_ZIP}
cd apex

# Verificar sqlplus
if ! command -v sqlplus &> /dev/null; then
    echo "❌ sqlplus no está disponible. Abortando."
    exit 1
fi

# Instalar APEX
echo ">> Instalando APEX..."
sqlplus "$SYSUSER" <<EOF
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

# Desbloquear usuario APEX_PUBLIC_USER
sqlplus "$SYSUSER" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${APEX_PWD} ACCOUNT UNLOCK;
EXIT;
EOF

# Crear usuario ADMIN
sqlplus "$SYSUSER" <<EOF
BEGIN
    APEX_UTIL.set_security_group_id( 10 );
    APEX_UTIL.create_user(
        p_user_name       => 'ADMIN',
        p_email_address   => 'admin@example.com',
        p_web_password    => 'OrclAPEX1999!',
        p_developer_privs => 'ADMIN');
    COMMIT;
END;
/
EXIT;
EOF

# Copiar imágenes a Tomcat
if [ -d "/usr/local/tomcat/webapps" ]; then
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r /opt/oracle/apex/images/* /usr/local/tomcat/webapps/i/
  echo ">> Imágenes de APEX copiadas a /usr/local/tomcat/webapps/i/"
fi

# =====================
# Descargar e instalar ORDS 25.1.0
# =====================

cd /opt/oracle

echo ">> Descargando ORDS..."
curl -o ${ORDS_ZIP} ${ORDS_URL}
unzip -q ${ORDS_ZIP} && rm -f ${ORDS_ZIP}

ORDS_HOME="/opt/oracle/ords"
ORDS_CONFIG="/etc/ords/config"

mkdir -p ${ORDS_HOME} ${ORDS_CONFIG}
cp ords.war ${ORDS_HOME}/ords.war

# Configurar ORDS
${ORDS_HOME}/ords.war configdir ${ORDS_CONFIG}

# Instalar ORDS
java -jar ${ORDS_HOME}/ords.war install \
  --admin-user sys \
  --db-hostname oracle-db \
  --db-port 1521 \
  --db-servicename FREEPDB1 \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin <<EOF
${APEX_PWD}
${APEX_PWD}
EOF

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
echo "✅ Instalación completa en $((elapsed_time / 60)) min $((elapsed_time % 60)) seg."

exit 0