# =========
# Stage 1: obtener sqlplus (cliente)
# Requiere una imagen que ya trae Oracle Instant Client + sqlplus
# =========
FROM gvenzl/oracle-sqlplus:21-slim AS sqlplus_src

# =========
# Stage 2: Tomcat + dependencias
# =========
FROM tomcat:10.1-jdk17-temurin

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Paquetes necesarios
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates bash \
    && rm -rf /var/lib/apt/lists/*

# Copiamos sqlplus e instant client desde el stage 1
# (rutas típicas de la imagen gvenzl/oracle-sqlplus)
COPY --from=sqlplus_src /usr/lib/oracle /usr/lib/oracle
COPY --from=sqlplus_src /usr/bin/sqlplus /usr/bin/sqlplus
COPY --from=sqlplus_src /usr/bin/lddlibc4 /usr/bin/lddlibc4 || true

# Variables para que sqlplus encuentre librerías
ENV LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib:${LD_LIBRARY_PATH}
ENV PATH=/usr/bin:${PATH}

# Tomcat: asegurar permisos de despliegue
RUN mkdir -p /usr/local/tomcat/webapps && \
    chown -R root:root /usr/local/tomcat && \
    chmod -R 755 /usr/local/tomcat

# Copiamos el script de arranque
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Salud de Tomcat simple (responde 200 cuando está deployeado)
HEALTHCHECK --interval=30s --timeout=10s --retries=20 \
  CMD curl -fsS http://localhost:8080/ || exit 1

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/startup.sh"]