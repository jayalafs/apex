# Tomcat + JDK
FROM tomcat:10.1-jdk17-temurin

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SQLCL_HOME=/opt/sqlcl

# Utilidades necesarias
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates bash \
    && rm -rf /var/lib/apt/lists/*

# ---- Instalar SQLcl (cliente Oracle en Java) ----
RUN mkdir -p ${SQLCL_HOME} \
 && curl -L -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" \
 && unzip -q /tmp/sqlcl.zip -d ${SQLCL_HOME} \
 && rm -f /tmp/sqlcl.zip

ENV PATH=${SQLCL_HOME}/sqlcl/bin:${PATH}

# Copiamos el entrypoint y normalizamos EOL/BOM
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN set -eux; \
    sed -i 's/\r$//' /usr/local/bin/entrypoint.sh; \
    sed -i '1s/^\xEF\xBB\xBF//' /usr/local/bin/entrypoint.sh; \
    chmod +x /usr/local/bin/entrypoint.sh

# Salud básica
HEALTHCHECK --interval=30s --timeout=10s --retries=30 \
  CMD curl -fsS http://localhost:8080/ || exit 1

EXPOSE 8080
ENTRYPOINT ["/bin/bash","/usr/local/bin/entrypoint.sh"]