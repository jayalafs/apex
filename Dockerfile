# Base: imagen oficial Oracle Database Free
FROM container-registry.oracle.com/database/free:latest

# Usaremos microdnf (Oracle Linux) para paquetes
USER root

# Paquetes necesarios: JDK para Tomcat, unzip, curl, tar, gzip
RUN microdnf install -y java-17-openjdk-headless unzip curl tar gzip which shadow-utils && \
    microdnf clean all

# Directorios y variables
ENV CATALINA_HOME=/opt/tomcat \
    SQLCL_HOME=/opt/sqlcl \
    ORDS_HOME=/opt/ords
ENV PATH=$PATH:$CATALINA_HOME/bin:$SQLCL_HOME/sqlcl/bin

# ---- Instalar Tomcat 10.1.x (Jakarta) ----
ARG TOMCAT_VER=10.1.26
RUN curl -fsSL https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz -o /tmp/tomcat.tgz && \
    mkdir -p /opt && tar -xzf /tmp/tomcat.tgz -C /opt && \
    mv /opt/apache-tomcat-${TOMCAT_VER} ${CATALINA_HOME} && \
    rm -f /tmp/tomcat.tgz

# ---- Instalar SQLcl (cliente Oracle en Java) ----
RUN mkdir -p ${SQLCL_HOME} && \
    curl -L -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" && \
    unzip -q /tmp/sqlcl.zip -d ${SQLCL_HOME} && \
    rm -f /tmp/sqlcl.zip

# ---- Pre-hornear ORDS WAR y expandir ----
RUN curl -L -o /opt/ords-latest.war "https://download.oracle.com/java/ords/ords-latest.war" && \
    mkdir -p ${ORDS_HOME} && unzip -q -o /opt/ords-latest.war -d ${ORDS_HOME}

# Copiar script de arranque al hook oficial de Oracle DB
# (se ejecuta después de que la base esté arriba)
COPY scripts/30-ords-apex.sh /opt/oracle/scripts/startup/30-ords-apex.sh

# Permisos
RUN chmod +x /opt/oracle/scripts/startup/30-ords-apex.sh && \
    chown -R oracle:oinstall ${CATALINA_HOME} ${SQLCL_HOME} ${ORDS_HOME} /opt/ords-latest.war

# Volvemos a usuario 'oracle' (el que usa la imagen oficial)
USER oracle

# Exponer puertos DB y Tomcat
EXPOSE 1521 8080

# Importante:
# No cambiamos ENTRYPOINT/CMD. Mantenemos el entrypoint oficial de la imagen,
# que levanta la DB y ejecuta nuestros scripts en /opt/oracle/scripts/startup.