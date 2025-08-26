# =========
# Stage A: Tomcat + JRE + SQLcl + APEX (pre-horneados)
# =========
ARG TOMCAT_BASE_TAG=10.1-jdk17-temurin
FROM tomcat:${TOMCAT_BASE_TAG} AS builder

ENV JAVA_HOME=/opt/java/openjdk
ENV CATALINA_HOME=/usr/local/tomcat
ENV PATH=${JAVA_HOME}/bin:${CATALINA_HOME}/bin:${PATH}

ARG APEX_VERSION=24.1

# Herramientas para este stage
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# SQLcl (cliente Oracle en Java)
RUN mkdir -p /opt/sqlcl \
 && curl -L --retry 5 --retry-all-errors \
       -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" \
 && unzip -q /tmp/sqlcl.zip -d /opt/sqlcl \
 && rm -f /tmp/sqlcl.zip

# APEX (pre-descargado y expandido)
RUN mkdir -p /opt/apex \
 && curl -L --retry 5 --retry-all-errors \
       -o /tmp/apex.zip "https://download.oracle.com/otn_software/apex/apex_${APEX_VERSION}.zip" \
 && unzip -q /tmp/apex.zip -d /tmp/apex \
 && if [ -d "/tmp/apex/apex" ]; then mv /tmp/apex/apex/* /opt/apex/; else mv /tmp/apex/* /opt/apex/; fi \
 && rm -rf /tmp/apex /tmp/apex.zip

# =========
# Stage B: ORDS oficial (solo para copiar el producto ya listo)
# =========
ARG ORDS_TAG=latest
FROM container-registry.oracle.com/database/ords:${ORDS_TAG} AS ordsimg
# WorkingDir de esta imagen: /opt/oracle/ords (producto ORDS con bin/, etc.). :contentReference[oaicite:3]{index=3}

# =========
# Stage C (final): Oracle DB Free + (Tomcat/JRE/SQLcl/APEX/ORDS pre-horneados)
# =========
FROM container-registry.oracle.com/database/free:latest

USER root

# Destinos
ENV JAVA_HOME=/opt/java/openjdk
ENV CATALINA_HOME=/opt/tomcat
ENV SQLCL_HOME=/opt/sqlcl
ENV ORDS_HOME=/opt/ords
ENV ORDS_CONFIG=/opt/ords/config
ENV PATH=${JAVA_HOME}/bin:${SQLCL_HOME}/sqlcl/bin:${CATALINA_HOME}/bin:${PATH}

# Copiar desde builder (Tomcat/JRE/SQLcl/APEX)
COPY --from=builder /usr/local/tomcat   ${CATALINA_HOME}
COPY --from=builder /opt/java/openjdk   ${JAVA_HOME}
COPY --from=builder /opt/sqlcl          ${SQLCL_HOME}
COPY --from=builder /opt/apex           /opt/oracle/apex

# Copiar desde ORDS oficial (producto ya listo)
# /opt/oracle/ords -> contiene bin/ (CLI) y ords.war
COPY --from=ordsimg  /opt/oracle/ords   ${ORDS_HOME}

# Hook de arranque de la DB: nuestro script se ejecuta cuando la DB ya está arriba
COPY scripts/30-ords-apex.sh /opt/oracle/scripts/startup/30-ords-apex.sh

# Permisos
RUN chmod +x /opt/oracle/scripts/startup/30-ords-apex.sh \
 && chown -R oracle:oinstall ${JAVA_HOME} ${CATALINA_HOME} ${SQLCL_HOME} ${ORDS_HOME} \
       /opt/oracle/apex /opt/oracle/scripts/startup/30-ords-apex.sh

USER oracle

EXPOSE 1521 8080
# Mantiene ENTRYPOINT/CMD de la imagen oficial de la DB