FROM tomcat:9.0.82-jdk17-temurin

# Build-time args
ARG ORDS_VERSION
ARG ORDS_HOME=/opt/ords
ARG ORDS_CONFIG=/etc/ords/config
ARG DB_HOST
ARG DB_PORT
ARG DB_SERVICE
ARG SYS_PASSWORD
ARG APEX_USER

# Set env vars
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

# Exponer el puerto de Tomcat
EXPOSE 8080

# Tomcat inicia por defecto con esto
CMD ["catalina.sh", "run"]

#ENTRYPOINT ["/entrypoint.sh"]