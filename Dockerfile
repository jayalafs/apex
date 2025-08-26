# =========
# Stage 1: runtime assets (Tomcat + JRE + SQLcl + ORDS + APEX)
# =========
ARG TOMCAT_BASE_TAG=10.1-jdk17-temurin
FROM tomcat:${TOMCAT_BASE_TAG} AS runtime-assets

# En tomcat:<tag> JAVA_HOME suele ser /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV CATALINA_HOME=/usr/local/tomcat
ENV PATH=${JAVA_HOME}/bin:${CATALINA_HOME}/bin:${PATH}

ARG APEX_VERSION=24.1

# Herramientas para este stage
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- SQLcl (cliente Oracle en Java) ---
RUN mkdir -p /opt/sqlcl \
 && curl -L --retry 5 --retry-all-errors -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" \
 && unzip -q /tmp/sqlcl.zip -d /opt/sqlcl \
 && rm -f /tmp/sqlcl.zip

# --- ORDS: pre-descargado y expandido ---
RUN curl -L --retry 5 --retry-all-errors -o /opt/ords-latest.war "https://download.oracle.com/java/ords/ords-latest.war" \
 && mkdir -p /opt/ords \
 && unzip -q -o /opt/ords-latest.war -d /opt/ords

# --- APEX: pre-descargado y expandido ---
RUN mkdir -p /opt/apex \
 && curl -L --retry 5 --retry-all-errors -o /tmp/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip" \
 && unzip -q /tmp/apex.zip -d /tmp/apex \
 && if [ -d "/tmp/apex/apex" ]; then mv /tmp/apex/apex/* /opt/apex/; else mv /tmp/apex/* /opt/apex/; fi \
 && rm -rf /tmp/apex /tmp/apex.zip

# =========
# Stage 2: imagen final = Oracle DB Free + (Tomcat/JRE/SQLcl/ORDS/APEX)
# =========
FROM container-registry.oracle.com/database/free:latest

USER root

# Rutas destino en la imagen final
ENV JAVA_HOME=/opt/java/openjdk
ENV CATALINA_HOME=/opt/tomcat
ENV SQLCL_HOME=/opt/sqlcl
ENV ORDS_HOME=/opt/ords
ENV ORDS_CONFIG=/opt/ords/config
ENV PATH=${JAVA_HOME}/bin:${SQLCL_HOME}/sqlcl/bin:${CATALINA_HOME}/bin:${PATH}

# Copiar desde el stage
COPY --from=runtime-assets /usr/local/tomcat      ${CATALINA_HOME}
COPY --from=runtime-assets /opt/java/openjdk      ${JAVA_HOME}
COPY --from=runtime-assets /opt/sqlcl             ${SQLCL_HOME}
COPY --from=runtime-assets /opt/ords              ${ORDS_HOME}
COPY --from=runtime-assets /opt/ords-latest.war   /opt/ords-latest.war
COPY --from=runtime-assets /opt/apex              /opt/oracle/apex

# Hook de arranque de la DB: se ejecuta cuando la base ya está arriba
COPY scripts/30-ords-apex.sh /opt/oracle/scripts/startup/30-ords-apex.sh

# Permisos
RUN chmod +x /opt/oracle/scripts/startup/30-ords-apex.sh \
 && chown -R oracle:oinstall ${JAVA_HOME} ${CATALINA_HOME} ${SQLCL_HOME} ${ORDS_HOME} /opt/oracle/apex /opt/ords-latest.war /opt/oracle/scripts/startup/30-ords-apex.sh

USER oracle

EXPOSE 1521 8080
# Importante: mantenemos el ENTRYPOINT/CMD de la imagen oficial de DB