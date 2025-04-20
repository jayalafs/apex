FROM tomcat:9.0.82-jdk17-temurin

# Definir variables como ARG (para build-time)
ARG ORDS_VERSION
ARG ORDS_HOME
ARG ORDS_CONFIG
ARG DB_HOST
ARG DB_PORT
ARG DB_SERVICE
ARG SYS_PASSWORD
ARG APEX_USER

# Exportar ARG como ENV si querés que estén disponibles en tiempo de ejecución
ENV ORDS_VERSION=${ORDS_VERSION}
ENV ORDS_HOME=${ORDS_HOME}
ENV ORDS_CONFIG=${ORDS_CONFIG}
ENV DB_HOST=${DB_HOST}
ENV DB_PORT=${DB_PORT}
ENV DB_SERVICE=${DB_SERVICE}
ENV SYS_PASSWORD=${SYS_PASSWORD}
ENV APEX_USER=${APEX_USER}

# Crear carpetas necesarias
RUN mkdir -p ${ORDS_HOME} ${ORDS_CONFIG}

# Copiar archivos
#COPY ords.war ${ORDS_HOME}/ords.war
#COPY entrypoint.sh /entrypoint.sh

# Permisos
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]