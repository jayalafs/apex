FROM tomcat:9.0.82-jdk17-temurin

LABEL maintainer="jayala@solvet-it.com.py"
ENV DEBIAN_FRONTEND=noninteractive

# Establecer zona horaria y variables clave
ENV TZ=America/Asuncion

# Instalar dependencias necesarias
RUN apt-get update && \
    apt-get install -y curl unzip libaio1 wget && \
    apt-get clean

# Instalar SQL*Plus (Oracle Instant Client)
WORKDIR /opt/oracle

RUN wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    wget https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    unzip -o instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    unzip -o instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
    rm -f instantclient-*.zip && \
    echo "/opt/oracle/instantclient_23_7" > /etc/ld.so.conf.d/oracle-instantclient.conf && \
    ldconfig && \
    ln -s /opt/oracle/instantclient_23_7/sqlplus /usr/local/bin/sqlplus && \
    echo 'export PATH=$PATH:/opt/oracle/instantclient_23_7' > /etc/profile.d/sqlplus.sh && \
    chmod +x /etc/profile.d/sqlplus.sh

# Crear estructura de carpetas
RUN mkdir -p /etc/ords/config \
             /opt/oracle/apex \
             /opt/oracle/ords \
             /usr/local/tomcat/webapps/i

# Copiar scripts
COPY startup.sh /opt/startup.sh

RUN chmod +x /opt/startup.sh /opt/oracle/scripts/unattended_apex_install_23c.sh

# Establecer directorio de trabajo
WORKDIR /opt

# Exponer el puerto web
EXPOSE 8080

# Entrypoint (ejecuta startup.sh como proceso principal)
CMD ["/opt/startup.sh"]