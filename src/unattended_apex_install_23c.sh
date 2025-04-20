#!/bin/bash

set -e

start_time=$(date +%s)

# Instalar dependencias
apt update && apt install -y unzip curl libaio1 wget

# Crear estructura de carpetas
mkdir -p /opt/oracle && cd /opt/oracle

# =====================
# Instalar SQL*Plus
# =====================
mkdir -p /opt/oracle
cd /opt/oracle || exit 1

# Descargar los paquetes necesarios
wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip || exit 1
wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip || exit 1

# Descomprimir los paquetes
unzip -o instantclient-basic-linux.x64-23.7.0.25.01.zip || exit 1
unzip -o instantclient-sqlplus-linux.x64-23.7.0.25.01.zip || exit 1

# Configurar librerías compartidas
echo "/opt/oracle/instantclient_23_7" > /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig

# Agregar al PATH actual y permanente
echo 'export PATH=$PATH:/opt/oracle/instantclient_23_7' > /etc/profile.d/sqlplus.sh
chmod +x /etc/profile.d/sqlplus.sh
export PATH=$PATH:/opt/oracle/instantclient_23_7

# Crear symlink para que funcione como comando global
ln -sf /opt/oracle/instantclient_23_7/sqlplus /usr/local/bin/sqlplus

# Confirmar instalación
echo "Probando sqlplus:"
sqlplus -v

# =====================
# Descargar e instalar APEX
# =====================

echo ">> Descargando APEX 24.1..."
curl -L -o apex_24.1.zip https://download.oracle.com/otn_software/apex/apex_24.1.zip || { echo "Error descargando APEX"; exit 1; }

echo ">> Descomprimiendo..."
mkdir -p /opt/oracle/apex
unzip -o apex_24.1.zip -d /opt/oracle/apex || { echo "Error descomprimiendo APEX"; exit 1; }
rm -f apex_24.1.zip
cd /opt/oracle/apex/apex || exit 1

# =====================
# Instalar APEX
# =====================

echo ">> Instalando APEX en la base de datos..."
/opt/oracle/instantclient_23_7/sqlplus "sys/Oracle123@oracle-db:1521/FREEPDB1 as sysdba" <<EOF
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

# =====================
# Desbloquear APEX_PUBLIC_USER
# =====================

echo ">> Desbloqueando APEX_PUBLIC_USER..."
/opt/oracle/instantclient_23_7/sqlplus "sys/Oracle123@oracle-db:1521/FREEPDB1 as sysdba" <<EOF
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY Oracle123 ACCOUNT UNLOCK;
EXIT;
EOF

# =====================
# Crear usuario ADMIN de APEX
# =====================

echo ">> Creando usuario ADMIN (si no existe)..."
/opt/oracle/instantclient_23_7/sqlplus "sys/Oracle123@oracle-db:1521/FREEPDB1 as sysdba" <<EOF
SET SERVEROUTPUT ON
DECLARE
  v_exists NUMBER;
BEGIN
  APEX_UTIL.set_security_group_id(10);

  SELECT COUNT(*) INTO v_exists
  FROM APEX_240100.WWV_FLOW_FND_USER
  WHERE user_name = 'ADMIN';

  IF v_exists = 0 THEN
    APEX_UTIL.create_user(
      p_user_name       => 'ADMIN',
      p_email_address   => 'jayala@solvet-it.com.py',
      p_web_password    => 'OrclAPEX1999!',
      p_developer_privs => 'ADMIN');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Usuario ADMIN creado correctamente.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Usuario ADMIN ya existe. No se creó nuevamente.');
  END IF;
END;
/
EXIT;
EOF

# =====================
# Desplegar ORDS en Tomcat
# =====================

echo ">> Copiando ords.war a Tomcat..."
cp /opt/oracle/ords/ords.war /usr/local/tomcat/webapps/ || {
  echo "Error: no se pudo copiar ords.war a Tomcat"; exit 1;
}

echo ">> Reiniciando Tomcat..."
# Asegurarse de detener y volver a iniciar Tomcat
# Si estás usando supervisord o un script de arranque, adaptá este paso

# Opción 1: usando catalina directamente
/usr/local/tomcat/bin/catalina.sh stop
sleep 5
/usr/local/tomcat/bin/catalina.sh start

# Opción 2: si tu contenedor se gestiona con supervisord
# supervisorctl restart tomcat

echo "✅ ORDS desplegado en Tomcat. Esperá unos segundos y accedé a:"
echo "👉 http://<IP_DEL_SERVIDOR>:8080/ords/"


# =====================
# Descargar e instalar ORDS 25.1.0
# =====================

cd /opt/oracle || exit 1

echo ">> Descargando ORDS 25.1.0..."
curl -L -o ords-25.1.0.100.1652.zip https://download.oracle.com/otn_software/java/ords/ords-25.1.0.100.1652.zip || {
  echo "Error descargando ORDS"; exit 1;
}

echo ">> Descomprimiendo ORDS en carpeta temporal..."
mkdir -p /opt/oracle/tmp_ords
unzip -q ords-25.1.0.100.1652.zip -d /opt/oracle/tmp_ords && rm -f ords-25.1.0.100.1652.zip

echo ">> Preparando carpetas de instalación..."
mkdir -p /opt/oracle/ords /etc/ords/config

echo ">> Copiando WAR a /opt/oracle/ords..."
cp /opt/oracle/tmp_ords/ords.war /opt/oracle/ords/ords.war
chmod +x /opt/oracle/ords/ords.war

echo ">> Limpiando archivos temporales..."
rm -rf /opt/oracle/tmp_ords

# Limpiar temporales
rm -rf /opt/oracle/tmp_ords
# =====================
# Instalar ORDS
# =====================

echo ">> Instalando ORDS..."
# Guardar contraseña en un archivo temporal
echo "Oracle123" > /tmp/ords_pass.txt
echo "Oracle123" >> /tmp/ords_pass.txt

# Ejecutar instalación con stdin redirigido
java -jar /opt/oracle/ords/ords.war install \
  --admin-user sys \
  --db-hostname oracle-db \
  --db-port 1521 \
  --db-servicename FREEPDB1 \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin < /tmp/ords_pass.txt

rm -f /tmp/ords_pass.txt

# =====================
# Mensaje de confirmación
# =====================

echo "✅ ORDS instalado correctamente en /opt/oracle/ords"