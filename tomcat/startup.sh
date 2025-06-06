#!/bin/bash
set -e

echo "[INFO] Esperando a que Oracle DB esté disponible..."

# Espera hasta que Oracle DB esté abierta
until echo "SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');" \
  | sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" \
  | grep -q "READ WRITE"
do
  echo "[WARN] El PDB ${DB_SERVICE} aún no está en modo READ WRITE. Reintentando en 20s..."
  sleep 20
done

echo "[INFO] El PDB ${DB_SERVICE} está en modo READ WRITE. Continuando con la instalación..."


# =====================
# Instalar APEX
# =====================
if [ -d /opt/oracle/apex ]; then
  echo "[INFO] Iniciando instalación de APEX..."
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
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${ORDS_PWD} ACCOUNT UNLOCK;
EXIT;
EOF

# =====================
# Crear usuario ADMIN de APEX
# =====================
sqlplus -s "sys/${ORACLE_PWD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba" <<EOF
DECLARE
  v_exists NUMBER;
BEGIN
  APEX_UTIL.set_security_group_id(10);
  SELECT COUNT(*) INTO v_exists FROM APEX_240100.WWV_FLOW_FND_USER WHERE user_name = '${APEX_ADMIN}';
  IF v_exists = 0 THEN
    APEX_UTIL.create_user(
      p_user_name       => '${APEX_ADMIN}',
      p_email_address   => '${APEX_ADMIN_EMAIL}',
      p_web_password    => '${APEX_ADMIN_PWD}',
      p_developer_privs => 'ADMIN');
    COMMIT;
  END IF;
END;
/
EXIT;
EOF

# =====================
# Instalar ORDS
# =====================
echo "[INFO] Descargando ORDS ${ORDS_VERSION}..."

ORDS_DIR=/opt/oracle/ords
ORDS_WAR=${ORDS_DIR}/ords.war
ORDS_CLI=${ORDS_DIR}/bin/ords

mkdir -p ${ORDS_DIR}
cd ${ORDS_DIR}

if [ ! -f "${ORDS_WAR}" ]; then
  curl -L -o ords.zip "https://download.oracle.com/otn_software/java/ords/ords-${ORDS_VERSION}.zip"
  unzip -oq ords.zip
  rm -f ords.zip
  chmod +x bin/ords
fi

mkdir -p ${ORDS_CONFIG}
chmod -R 777 ${ORDS_CONFIG}
export ORDS_CONFIG

echo "[INFO] Ejecutando instalación de ORDS..."
${ORDS_CLI} install \
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
# Desplegar ORDS en Tomcat
# =====================
echo "[INFO] Desplegando ords.war en Tomcat..."
cp ${ORDS_WAR} /usr/local/tomcat/webapps/ords.war
chmod 644 /usr/local/tomcat/webapps/ords.war

# =====================
# Copiar imágenes estáticas de APEX
# =====================
if [ -d /opt/oracle/apex/images ]; then
  echo "[INFO] Copiando imágenes APEX..."
  mkdir -p /usr/local/tomcat/webapps/i
  cp -r /opt/oracle/apex/images/* /usr/local/tomcat/webapps/i/
else
  echo "[ERROR] No se encontraron imágenes estáticas de APEX."
  exit 1
fi

# =====================
# Iniciar Tomcat
# =====================
echo "[INFO] Inicio completo. Ejecutando Tomcat en primer plano..."
exec catalina.sh run