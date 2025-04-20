# Dockerfile para contenedor con Tomcat + SQL*Plus + APEX + ORDS

FROM tomcat:9.0.82-jdk17-temurin

# =====================
# Variables de entorno
# =====================
ENV ORACLE_PWD=Oracle123 \
    APEX_VERSION=24.1 \
    ORDS_VERSION=25.1.0.100.1652 \
    DB_HOST=oracle-db \
    DB_PORT=1521 \
    DB_SERVICE=FREEPDB1 \
    APEX_ADMIN=ADMIN \
    APEX_ADMIN_EMAIL=jayala@solvet-it.com.py \
    APEX_ADMIN_PWD=OrclAPEX1999!

WORKDIR /opt/oracle

# =====================
# Instalar dependencias necesarias
# =====================
RUN apt update && \
    apt install -y unzip curl libaio1 wget

# =====================
# Instalar SQL*Plus
# =====================
RUN wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    unzip instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    unzip instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    echo "/opt/oracle/instantclient_23_7" > /etc/ld.so.conf.d/oracle-instantclient.conf && \
    ldconfig && \
    ln -s /opt/oracle/instantclient_23_7/sqlplus /usr/local/bin/sqlplus && \
    rm *.zip

ENV PATH=$PATH:/opt/oracle/instantclient_23_7

# =====================
# Descargar e instalar APEX
# =====================
RUN curl -L -o apex_${APEX_VERSION}.zip https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip && \
    unzip apex_${APEX_VERSION}.zip -d /opt/oracle/apex && \
    rm apex_${APEX_VERSION}.zip && \
    cp -r /opt/oracle/apex/apex/images/* /usr/local/tomcat/webapps/i/

# =====================
# Descargar y preparar ORDS
# =====================
RUN curl -L -o ords.zip https://download.oracle.com/otn_software/java/ords/ords-${ORDS_VERSION}.zip && \
    unzip -q ords.zip -d /opt/oracle/ords_tmp && \
    mkdir -p /opt/oracle/ords /etc/ords/config && \
    cp /opt/oracle/ords_tmp/ords.war /opt/oracle/ords/ords.war && \
    chmod +x /opt/oracle/ords/ords.war && \
    rm -rf /opt/oracle/ords_tmp ords.zip

# =====================
# Script de instalación automática APEX + ORDS al iniciar el contenedor
# =====================
COPY startup.sh /opt/oracle/startup.sh
RUN chmod +x /opt/oracle/startup.sh

# =====================
# Iniciar Tomcat y ejecutar instalación de APEX/ORDS
# =====================
CMD ["/opt/oracle/startup.sh"]