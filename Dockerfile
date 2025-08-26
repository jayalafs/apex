# =========
# Stage 1: runtime assets (Java/Tomcat/SQLcl/ORDS/APEX)
# =========
FROM eclipse-temurin:17-jre AS runtime-assets

ARG TOMCAT_VER=10.1.26
ARG APEX_VERSION=24.1

# Herramientas sólo en el stage (no pasan al final)
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Java ya viene con Temurin; definimos JAVA_HOME para el stage
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH=${JAVA_HOME}/bin:${PATH}

# Tomcat
RUN curl -fsSL "https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz" \
      -o /tmp/tomcat.tgz \
 && mkdir -p /opt \
 && tar -xzf /tmp/tomcat.tgz -C /opt \
 && mv /opt/apache-tomcat-${TOMCAT_VER} /opt/tomcat \
 && rm -f /tmp/tomcat.tgz

# SQLcl (cliente Oracle en Java)
RUN mkdir -p /opt/sqlcl \
 && curl -L -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" \
 && unzip -q /tmp/sqlcl.zip -d /opt/sqlcl \
 && rm -f /tmp/sqlcl.zip

# ORDS: pre-descargar y expandir
RUN curl -L -o /opt/ords-latest.war "https://download.oracle.com/java/ords/ords-latest.war" \
 && mkdir -p /opt/ords \
 && unzip -q -o /opt/ords-latest.war -d /opt/ords

# APEX: pre-descargar y expandir (para no depender de unzip/curl en runtime)
RUN mkdir -p /opt/apex \
 && curl -L -o /tmp/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip" \
 && unzip -q /tmp/apex.zip -d /tmp/apex \
 && if [ -d "/tmp/apex/apex" ]; then mv /tmp/apex/apex/* /opt/apex/; else mv /tmp/apex/* /opt/apex/; fi \
 && rm -rf /tmp/apex /tmp/apex.zip

# =========
# Stage 2: imagen final = Oracle Database Free + (Java/Tomcat/SQLcl/ORDS/APEX)
# =========
FROM container-registry.oracle.com/database/free:latest

USER root

# Directorios de destino en imagen final
ENV JAVA_HOME=/opt/java/openjdk
ENV CATALINA_HOME=/opt/tomcat
ENV SQLCL_HOME=/opt/sqlcl
ENV ORDS_HOME=/opt/ords
ENV ORDS_CONFIG=/opt/ords/config
ENV PATH=${JAVA_HOME}/bin:${SQLCL_HOME}/sqlcl/bin:${CATALINA_HOME}/bin:${PATH}

# Copiar todo desde el stage
COPY --from=runtime-assets /opt/tomcat          ${CATALINA_HOME}
COPY --from=runtime-assets /opt/java/openjdk    ${JAVA_HOME}
COPY --from=runtime-assets /opt/sqlcl           ${SQLCL_HOME}
COPY --from=runtime-assets /opt/ords            ${ORDS_HOME}
COPY --from=runtime-assets /opt/ords-latest.war /opt/ords-latest.war
# APEX pre-expandido a la ruta esperada por nuestro hook
COPY --from=runtime-assets /opt/apex            /opt/oracle/apex

# Hook de arranque de la DB: nuestro script se ejecuta cuando la DB ya está arriba
COPY scripts/30-ords-apex.sh /opt/oracle/scripts/startup/30-ords-apex.sh

# Permisos
RUN chmod +x /opt/oracle/scripts/startup/30-ords-apex.sh \
 && chown -R oracle:oinstall ${JAVA_HOME} ${CATALINA_HOME} ${SQLCL_HOME} ${ORDS_HOME} /opt/oracle/apex /opt/ords-latest.war /opt/oracle/scripts/startup/30-ords-apex.sh

USER oracle

EXPOSE 1521 8080

# Mantiene el ENTRYPOINT/CMD de la imagen oficial de DB (no lo tocamos)