#!/bin/bash
set -e

echo "[INFO] Esperando a que Oracle DB esté disponible..."
until echo exit | sqlplus -L -s "${ORACLE_ADMIN_USER}/${ORACLE_ADMIN_PASSWORD}@//${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE_NAME} as sysdba" | grep "Connected"; do
  sleep 5
done

echo "[INFO] Oracle DB conectado. Instalando APEX..."

cd /opt/oracle

# Descargar e instalar APEX
curl -L -o apex_${APEX_VERSION}.zip https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip
unzip -q apex_${APEX_VERSION}.zip -d /opt/oracle/apex && rm apex_${APEX_VERSION}.zip

cd /opt/oracle/apex

echo "[INFO] Instalando APEX..."
sqlplus -s "${ORACLE_ADMIN_USER}/${ORACLE_ADMIN_PASSWORD}@//${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE_NAME} as sysdba" <<EOF
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT
EOF

echo "[INFO] Desbloqueando usuario APEX_PUBLIC_USER..."
sqlplus -s "${ORACLE_ADMIN_USER}/${ORACLE_ADMIN_PASSWORD}@//${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE_NAME} as sysdba" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${ORDS_PUBLIC_PASSWORD} ACCOUNT UNLOCK;
EXIT;
EOF

echo "[INFO] Creando usuario ADMIN de APEX si no existe..."
sqlplus -s "${ORACLE_ADMIN_USER}/${ORACLE_ADMIN_PASSWORD}@//${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE_NAME} as sysdba" <<EOF
BEGIN
  APEX_UTIL.set_security_group_id(10);
  APEX_UTIL.create_user(
    p_user_name       => 'ADMIN',
    p_email_address   => '${APEX_ADMIN_EMAIL}',
    p_web_password    => '${APEX_ADMIN_PASSWORD}',
    p_developer_privs => 'ADMIN');
  COMMIT;
END;
/
EXIT;
EOF

echo "[INFO] Configurando ORDS..."
cd /opt/oracle/ords
java -jar ords.war configdir ${ORDS_CONFIG_DIR}

echo "[INFO] Instalando ORDS..."
java -jar ords.war install \
  --admin-user "${ORACLE_ADMIN_USER}" \
  --db-hostname "${ORACLE_HOST}" \
  --db-port "${ORACLE_PORT}" \
  --db-servicename "${ORACLE_SERVICE_NAME}" \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin <<EOF
${ORACLE_ADMIN_PASSWORD}
${ORDS_PUBLIC_PASSWORD}
EOF

echo "[INFO] Copiando archivos estáticos de APEX a Tomcat..."
mkdir -p /usr/local/tomcat/webapps/i
cp -r /opt/oracle/apex/images/* /usr/local/tomcat/webapps/i/

echo "[INFO] Iniciando Tomcat..."
catalina.sh run