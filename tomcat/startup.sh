#!/bin/bash
set -e

echo "===================================================="
echo "[INFO] Esperando a que Oracle DB esté disponible..."
echo "===================================================="
until sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF | grep -q "READ WRITE"
SET HEADING OFF;
SET FEEDBACK OFF;
SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');
EXIT;
EOF
do
  echo "[WARN] El PDB ${DB_SERVICE} aún no está en modo READ WRITE. Reintentando en 20s..."
  sleep 20
done

# =====================
# Instalar APEX si no existe
# =====================
if [ ! -f "/opt/oracle/apex/apexins.sql" ]; then
  echo "[INFO] Descargando e instalando APEX..."
  curl -L -o /opt/oracle/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip"
  unzip -o /opt/oracle/apex.zip -d /opt/oracle/
  if [ -d "/opt/oracle/apex/apex" ]; then
    mv /opt/oracle/apex/apex/* /opt/oracle/apex/
    rm -rf /opt/oracle/apex/apex
  fi
  rm -f /opt/oracle/apex.zip
fi

cd /opt/oracle/apex
sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

# =====================
# Desbloquear APEX_PUBLIC_USER
# =====================
sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${ORDS_PWD} ACCOUNT UNLOCK;
EXIT;
EOF

# =====================
# Descargar y descomprimir ORDS si no existe
# =====================
if [ ! -x /opt/oracle/ords/bin/ords ]; then
  echo "[INFO] Descargando y descomprimiendo ORDS..."
  curl -L -o /opt/oracle/ords-latest.zip "https://download.oracle.com/java/ords/ords-latest.zip"
  unzip -o /opt/oracle/ords-latest.zip -d /opt/oracle/ords-temp
  mkdir -p /opt/oracle/ords
  mv /opt/oracle/ords-temp/* /opt/oracle/ords/
  rm -rf /opt/oracle/ords-temp /opt/oracle/ords-latest.zip
fi

# =====================
# Instalar ORDS en modo proxied
# =====================
echo "[INFO] Instalando ORDS en modo proxied..."
rm -rf ${ORDS_CONFIG}/*
mkdir -p ${ORDS_CONFIG}
chmod -R 777 ${ORDS_CONFIG}

/opt/oracle/ords/bin/ords install \
  --admin-user ${SYSDBA_USER} \
  --db-hostname ${DB_HOST} \
  --db-port ${DB_PORT} \
  --db-servicename ${DB_SERVICE} \
  --gateway-mode proxied \
  --gateway-user ${ORDS_USER} \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin <<EOF
${ORDS_PWD}
${ORDS_PWD}
EOF

# =====================
# Mapear /apex si no existe
# =====================
if [ ! -f "${ORDS_CONFIG}/databases/${DB_SERVICE}/mappings/apex.json" ]; then
  echo "[INFO] Asignando mapping /apex al PDB ${DB_SERVICE}..."
  /opt/oracle/ords/bin/ords --config ${ORDS_CONFIG} map-url \
    --pdb ${DB_SERVICE} \
    --url-path apex
fi

# =====================
# Desplegar ords.war en Tomcat
# =====================
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/ords.war
chmod 644 /usr/local/tomcat/webapps/ords.war

# =====================
# Copiar imagenes estaticas de APEX
# =====================
if [ -d /opt/oracle/apex/images ]; then
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r /opt/oracle/apex/images/* /usr/local/tomcat/webapps/i/
else
  echo "[ERROR] No se encontraron imágenes estáticas de APEX"
  exit 1
fi

# =====================
# Iniciar Tomcat
# =====================
echo "[INFO] Inicio completo. Ejecutando Tomcat..."
exec catalina.sh run