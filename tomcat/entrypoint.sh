#!/bin/bash
set -e

# Verificar si ya existe configuración previa
if [ ! -f "${ORDS_CONFIG}/ords_params.properties" ]; then
  echo ">> Configurando ORDS..."

  java -jar ${ORDS_HOME}/ords.war configdir ${ORDS_CONFIG}

  java -jar ${ORDS_HOME}/ords.war install \
    --admin-user sys \
    --db-hostname ${DB_HOST} \
    --db-port ${DB_PORT} \
    --db-servicename ${DB_SERVICE} \
    --feature-db-api true \
    --feature-rest-enabled-sql true \
    --feature-sdw true \
    --gateway-mode proxied \
    --gateway-user ${APEX_USER} \
    --password-stdin <<EOF
${SYS_PASSWORD}
${SYS_PASSWORD}
EOF
fi

# Copiar WAR a Tomcat
cp ${ORDS_HOME}/ords.war /usr/local/tomcat/webapps/ords.war

echo ">> Iniciando Tomcat con ORDS..."
exec catalina.sh run