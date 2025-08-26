# Base: Tomcat + JDK
FROM tomcat:10.1-jdk17-temurin

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SQLCL_HOME=/opt/sqlcl

# Dependencias mínimas
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates bash \
    && rm -rf /var/lib/apt/lists/*

# ---- Instalar SQLcl (cliente Oracle en Java) ----
# Nota: SQLcl entiende casi todos los scripts de SQL*Plus
RUN mkdir -p ${SQLCL_HOME} \
 && curl -L -o /tmp/sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip" \
 && unzip -q /tmp/sqlcl.zip -d ${SQLCL_HOME} \
 && rm -f /tmp/sqlcl.zip

ENV PATH=${SQLCL_HOME}/sqlcl/bin:${PATH}

# Copiamos el script y lo normalizamos (quita CRLF/BOM) y damos permisos
COPY startup.sh /usr/local/bin/startup.sh
RUN set -eux; \
    # quitar CRLF
    sed -i 's/\r$//' /usr/local/bin/startup.sh; \
    # quitar BOM si lo hubiera
    sed -i '1s/^\xEF\xBB\xBF//' /usr/local/bin/startup.sh; \
    chmod +x /usr/local/bin/startup.sh

# Salud básica de Tomcat
HEALTHCHECK --interval=30s --timeout=10s --retries=20 \
  CMD curl -fsS http://localhost:8080/ || exit 1

EXPOSE 8080
# Invocar con bash explícitamente evita problemas de shebang/CRLF
ENTRYPOINT ["/bin/bash","/usr/local/bin/startup.sh"]