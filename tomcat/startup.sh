#!/bin/bash

set -e

echo "[INFO] Esperando a que Oracle DB esté disponible..."

until sqlplus -L "sys/$ORACLE_PWD@$DB_HOST:$DB_PORT/$DB_SERVICE as sysdba" <<< "EXIT" >/dev/null 2>&1; do
  echo "."
  sleep 5
done

echo "[INFO] Oracle DB conectado. Instalando APEX..."

sqlplus "sys/$ORACLE_PWD@$DB_HOST:$DB_PORT/$DB_SERVICE as sysdba" <<EOF
@/opt/oracle/apex/apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

echo "[INFO] Desbloqueando usuario APEX_PUBLIC_USER..."

sqlplus "sys/$ORACLE_PWD@$DB_HOST:$DB_PORT/$DB_SERVICE as sysdba" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY $ORACLE_PWD ACCOUNT UNLOCK;
EXIT;
EOF

echo "[INFO] Creando usuario ADMIN de APEX si no existe..."

sqlplus "sys/$ORACLE_PWD@$DB_HOST:$DB_PORT/$DB_SERVICE as sysdba" <<EOF
SET SERVEROUTPUT ON
DECLARE
  v_exists NUMBER;
BEGIN
  APEX_UTIL.set_security_group_id(10);

  SELECT COUNT(*) INTO v_exists
  FROM APEX_240100.WWV_FLOW_FND_USER
  WHERE user_name = '$APEX_ADMIN';

  IF v_exists = 0 THEN
    APEX_UTIL.create_user(
      p_user_name       => '$APEX_ADMIN',
      p_email_address   => '$APEX_ADMIN_EMAIL',
      p_web_password    => '$APEX_ADMIN_PWD',
      p_developer_privs => 'ADMIN');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Usuario ADMIN creado correctamente.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Usuario ADMIN ya existe.');
  END IF;
END;
/
EXIT;
EOF

echo "[INFO] Configurando ORDS..."

mkdir -p /etc/ords/config
/opt/oracle/ords/ords.war configdir /etc/ords/config

echo "[INFO] Instalando ORDS..."
echo "$ORACLE_PWD" > /tmp/ords_pass.txt
echo "$ORACLE_PWD" >> /tmp/ords_pass.txt

java -jar /opt/oracle/ords/ords.war install \
  --admin-user sys \
  --db-hostname $DB_HOST \
  --db-port $DB_PORT \
  --db-servicename $DB_SERVICE \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin < /tmp/ords_pass.txt

rm -f /tmp/ords_pass.txt

echo "[INFO] Copiando ORDS a Tomcat..."
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/

echo "[INFO] Iniciando Tomcat..."
exec /usr/local/tomcat/bin/catalina.sh run