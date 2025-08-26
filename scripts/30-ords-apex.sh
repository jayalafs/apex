#!/bin/bash
# Ejecutado automáticamente por la imagen de Oracle Database Free
# cuando la base ya está en marcha (hook: /opt/oracle/scripts/startup).
set -euo pipefail

log(){ printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }

# ===== Vars =====
ORACLE_PWD="${ORACLE_PWD:?Debe definirse ORACLE_PWD}"
DB_SERVICE="${DB_SERVICE:-FREEPDB1}"
APEX_VERSION="${APEX_VERSION:-24.1}"
APEX_ADMIN_PWD="${APEX_ADMIN_PWD:-}"
APEX_ADMIN_EMAIL="${APEX_ADMIN_EMAIL:-}"

ORDS_PWD="${ORDS_PWD:-Oracle123}"
ORDS_GATEWAY_USER="${ORDS_GATEWAY_USER:-ORDS_PUBLIC_USER}"
CLEAN_ORDS_CONFIG="${CLEAN_ORDS_CONFIG:-true}"

CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
ORDS_HOME="${ORDS_HOME:-/opt/ords}"
ORDS_CONFIG="${ORDS_CONFIG:-/opt/ords/config}"

SQL="sql -S"   # SQLcl

# Derivar esquema de APEX (24.1 -> APEX_240100)
APEX_SCHEMA="APEX_$(echo "${APEX_VERSION}" | awk -F. '{m=$1+0; n=($2=="")?0:$2; printf("%02d%02d00", m, n)}')"

log "Hook startup: ORDS + APEX + Tomcat"
log "DB_SERVICE=${DB_SERVICE} | APEX_VERSION=${APEX_VERSION} -> SCHEMA=${APEX_SCHEMA}"

# ===== Confirmar PDB en READ WRITE =====
log "Verificando que PDB ${DB_SERVICE} esté READ WRITE…"
until ${SQL} "sys/${ORACLE_PWD}@//localhost:1521/${DB_SERVICE} as sysdba" <<SQLQ | grep -q "READ WRITE"
SET HEADING OFF FEEDBACK OFF
SELECT open_mode FROM v\$pdbs WHERE name = UPPER('${DB_SERVICE}');
EXIT;
SQLQ
do
  log "PDB aún no READ WRITE, reintento en 10s…"
  sleep 10
done
log "PDB en READ WRITE."

# ===== Instalar APEX si no existe =====
APEX_HOME="/opt/oracle/apex"
apex_instalado="$(${SQL} "sys/${ORACLE_PWD}@//localhost:1521/${DB_SERVICE} as sysdba" <<SQLQ | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_users WHERE username = UPPER('${APEX_SCHEMA}');
EXIT;
SQLQ
)"
if [ "${apex_instalado}" != "1" ]; then
  log "APEX ${APEX_VERSION} no detectado. Ejecutando apexins.sql…"
  ${SQL} "sys/${ORACLE_PWD}@//localhost:1521/${DB_SERVICE} as sysdba" <<SQLQ
@${APEX_HOME}/apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
SQLQ
else
  log "APEX ya instalado (${APEX_SCHEMA})."
fi

# ===== (Opcional) setear password de ADMIN con apxchpwd.sql =====
if [ -n "${APEX_ADMIN_PWD}" ] && [ -f "${APEX_HOME}/apxchpwd.sql" ]; then
  log "Intentando setear password de ADMIN via apxchpwd.sql (no-interactivo)…"
  set +e
  # Entradas típicas: <Enter para ADMIN>, <Enter email vacío>, password, confirmación
  printf '\n\n%s\n%s\n' "${APEX_ADMIN_PWD}" "${APEX_ADMIN_PWD}" | \
    ${SQL} "sys/${ORACLE_PWD}@//localhost:1521/${DB_SERVICE} as sysdba" @"${APEX_HOME}/apxchpwd.sql"
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    log "[WARN] apxchpwd.sql no-interactivo no completado (rc=$rc). Puedes correrlo manualmente más tarde."
  else
    log "ADMIN configurado correctamente por apxchpwd.sql."
  fi
else
  log "[INFO] APEX_ADMIN_PWD vacío o apxchpwd.sql no encontrado: puedes fijarlo luego manualmente."
fi

# ===== Desbloquear usuarios gateway =====
log "Desbloqueando ${ORDS_GATEWAY_USER} y APEX_PUBLIC_USER…"
${SQL} "sys/${ORACLE_PWD}@//localhost:1521/${DB_SERVICE} as sysdba" <<SQLQ || true
SET HEADING OFF FEEDBACK OFF
BEGIN
  EXECUTE IMMEDIATE 'ALTER USER ${ORDS_GATEWAY_USER} IDENTIFIED BY "${ORDS_PWD}" ACCOUNT UNLOCK';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  EXECUTE IMMEDIATE 'ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${ORDS_PWD}" ACCOUNT UNLOCK';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
EXIT;
SQLQ

# ===== ORDS: instalar / reconfigurar (proxied) =====
log "Instalando/actualizando ORDS (proxied)…"
if [ "${CLEAN_ORDS_CONFIG}" = "true" ]; then
  rm -rf "${ORDS_CONFIG:?}/"* || true
fi
mkdir -p "${ORDS_CONFIG}"

${ORDS_HOME}/bin/ords --config "${ORDS_CONFIG}" install \
  --admin-user sys \
  --db-hostname localhost \
  --db-port 1521 \
  --db-servicename "${DB_SERVICE}" \
  --gateway-mode proxied \
  --gateway-user "${ORDS_GATEWAY_USER}" \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --password-stdin <<EOF
${ORDS_PWD}
${ORDS_PWD}
EOF

# Mapear /apex si no existe
if [ ! -f "${ORDS_CONFIG}/databases/${DB_SERVICE}/mappings/apex.json" ]; then
  log "Asignando mapping /apex -> ${DB_SERVICE}"
  ${ORDS_HOME}/bin/ords --config "${ORDS_CONFIG}" map-url \
    --pdb "${DB_SERVICE}" \
    --url-path apex
fi

# ===== Desplegar ORDS + imágenes de APEX en Tomcat =====
log "Desplegando ords.war en Tomcat y copiando /i…"
cp "${ORDS_HOME}/ords.war" "${CATALINA_HOME}/webapps/ords.war"
mkdir -p "${CATALINA_HOME}/webapps/i"
if [ -d "${APEX_HOME}/images" ]; then
  cp -r "${APEX_HOME}/images/"* "${CATALINA_HOME}/webapps/i/"
else
  log "[WARN] No se encontraron imágenes APEX en ${APEX_HOME}/images"
fi

# ===== Arrancar Tomcat (background, DB queda como proceso 1) =====
log "Arrancando Tomcat…"
"${CATALINA_HOME}/bin/catalina.sh" start || true

log "ORDS listo en:  http://localhost:8080/ords"
log "APEX en:        http://localhost:8080/ords/apex"