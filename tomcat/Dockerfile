# Dockerfile para contenedor ORDS + APEX sobre Tomcat

FROM tomcat:9.0.82-jdk17-temurin

# =====================
# Variables de entorno desde build args
# =====================
ARG ORACLE_PWD
ARG DB_HOST
ARG DB_PORT
ARG DB_SERVICE
ARG APEX_ADMIN
ARG APEX_ADMIN_EMAIL
ARG APEX_ADMIN_PWD
ARG ORDS_VERSION
ARG APEX_VERSION
ARG TZ

ENV ORACLE_PWD=$ORACLE_PWD \
    DB_HOST=$DB_HOST \
    DB_PORT=$DB_PORT \
    DB_SERVICE=$DB_SERVICE \
    APEX_ADMIN=$APEX_ADMIN \
    APEX_ADMIN_EMAIL=$APEX_ADMIN_EMAIL \
    APEX_ADMIN_PWD=$APEX_ADMIN_PWD \
    ORDS_VERSION=$ORDS_VERSION \
    APEX_VERSION=$APEX_VERSION \
    TZ=$TZ

WORKDIR /opt/oracle

# =====================
# Instalar utilidades necesarias
# =====================
RUN apt update && \
    apt install -y unzip curl libaio1 wget

# =====================
# Instalar SQL*Plus
# =====================
RUN wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    unzip -qo instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    unzip -qo instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    echo "/opt/oracle/instantclient_23_7" > /etc/ld.so.conf.d/oracle-instantclient.conf && \
    ldconfig && \
    ln -sf /opt/oracle/instantclient_23_7/sqlplus /usr/local/bin/sqlplus && \
    rm -f instantclient-*.zip

ENV PATH=$PATH:/opt/oracle/instantclient_23_7

# =====================
# Descargar ORDS
# =====================
RUN curl -L -o ords.zip https://download.oracle.com/otn_software/java/ords/ords-${ORDS_VERSION}.zip && \
    unzip -q ords.zip -d /opt/oracle/ords_tmp && \
    mkdir -p /opt/oracle/ords /etc/ords/config && \
    cp /opt/oracle/ords_tmp/ords.war /opt/oracle/ords/ords.war && \
    chmod +x /opt/oracle/ords/ords.war && \
    rm -rf /opt/oracle/ords_tmp ords.zip

# =====================
# Descargar APEX
# =====================
RUN curl -o apex_${APEX_VERSION}.zip https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip && \
    unzip -q apex_${APEX_VERSION}.zip -d /opt/oracle && \
    rm -f apex_${APEX_VERSION}.zip

# =====================
# Copiar script de arranque (instalación APEX + ORDS + arranque de Tomcat)
# =====================
COPY startup.sh /opt/oracle/startup.sh
RUN chmod +x /opt/oracle/startup.sh

# =====================
# Comando por defecto: espera Oracle + instala + arranca Tomcat
# =====================
CMD ["/opt/oracle/startup.sh"]