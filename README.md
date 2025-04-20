# Acerca de este repositorio
Este repositorio contiene scripts de shell diseñados para automatizar el proceso manual detallado en [Oracle 23c Free Docker, APEX & ORDS – todo en una guía simple](https://pretius.com/blog/oracle-apex-docker-ords/) para instalar las últimas versiones de:

- Oracle APEX 
- Servicios de datos REST de Oracle (ORDS)

Estos scripts están diseñados para usarse con la imagen oficial de Oracle 23c, disponible [en Oracle Container Registry](https://container-registry.oracle.com/).


# Instrucciones
Los pasos para usar el script se pueden encontrar en el blog [Single Step Oracle 23c DB + APEX Docker Container](https://mattmulvaney.hashnode.dev/single-step-oracle-23c-db-apex-docker-container) .

# Software adicional instalado

-Sudo
-Nano
- OpenJDK Java 17

# Contribuciones
Se recomiendan contribuciones a este repositorio.


# Instalacion manual
# Descargamos apex en su ultima version
curl -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip

docker create -it --name oracle-container01 -p 8521:1521 -p 8500:5500 -p 8023:8080 -p 9043:8443 -p 9922:22 -e ORACLE_PWD=E container-registry.oracle.com/database/free:latest
curl -o unattended_apex_install_23c.sh https://raw.githubusercontent.com/Pretius/pretius-23cfree-unattended-apex-installer/main/src/unattended_apex_install_23c.sh
curl -o 00_start_apex_ords_installer.sh https://raw.githubusercontent.com/Pretius/pretius-23cfree-unattended-apex-installer/main/src/00_start_apex_ords_installer.sh
docker cp unattended_apex_install_23c.sh oracle-container01:/home/oracle
docker cp 00_start_apex_ords_installer.sh oracle-container01:/opt/oracle/scripts/startup
docker start oracle-container01

 docker create -it --name 23cfree -p 8521:1521 -p 8500:5500 -p 8023:8080 -p 9043:8443 -p 9922:22 -e ORACLE_PWD=E container-registry.oracle.com/database/free:latest
 curl -o unattended_apex_install_23c.sh https://raw.githubusercontent.com/Pretius/pretius-23cfree-unattended-apex-installer/main/src/unattended_apex_install_23c.sh
 curl -o 00_start_apex_ords_installer.sh https://raw.githubusercontent.com/Pretius/pretius-23cfree-unattended-apex-installer/main/src/00_start_apex_ords_installer.sh
 docker cp unattended_apex_install_23c.sh 23cfree:/home/oracle
 docker cp 00_start_apex_ords_installer.sh 23cfree:/opt/oracle/scripts/startup
 docker start 23cfree



#Instalacion manual
docker pull container-registry.oracle.com/database/free:latest

docker run -d -it --name oracle-apex -p 1521:1521 -p 5500:5500 -p 8080:8080 -p 8443:8443 -e ORACLE_PWD=E container-registry.oracle.com/database/free:latest

docker exec oracle-apex-container -it  /bin/bash

curl -o apex-latest.zip https://download.oracle.com/otn_software/apex/apex-latest.zip



# Ingresamos al SQL
sqlplus / as sysdba

ALTER SESSION SET CONTAINER = FREEPDB1; 
@apexins.sql SYSAUX SYSAUX TEMP /i/

Admin123

@/home/oracle/apex/apxchpwd.sql

#Correcion de repositorio
RUN vi /etc/yum.repos.d/oracle-linux-ol8.repo

[ol8_developer]
name=Oracle Linux 8 Development Packages ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/developer/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8

[ol8_baseos_latest]
name=Oracle Linux 8 BaseOS Latest ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8

[ol8_appstream]
name=Oracle Linux 8 Application Stream ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/appstream/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8

# Corregir el repositorio YUM de Oracle Linux 8
RUN printf "[ol8_developer]\n\
name=Oracle Linux 8 Development Packages (\$basearch)\n\
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/developer/\$basearch/\n\
gpgcheck=1\n\
enabled=0\n\
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8\n\
\n\
[ol8_baseos_latest]\n\
name=Oracle Linux 8 BaseOS Latest (\$basearch)\n\
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/\$basearch/\n\
gpgcheck=1\n\
enabled=1\n\
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8\n\
\n\
[ol8_appstream]\n\
name=Oracle Linux 8 Application Stream (\$basearch)\n\
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/appstream/\$basearch/\n\
gpgcheck=1\n\
enabled=1\n\
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8\n" \
> /etc/yum.repos.d/oracle-linux-ol8.repo


# Instalacion de paquetes
RUN dnf update -y && \
    dnf install -y sudo nano java-17-openjdk zip unzip curl && \
    dnf clean all


Una vez instalado completamente podemos agregar el idioma español, luego de esto ya saldra la opcion de cambiar el idioma

cd /home/oracle/apex/builder/es
sqlplus / as sysdba

ALTER SESSION SET CONTAINER = FREEPDB1;

@f4000_es.sql
@f4100_es.sql
@f4150_es.sql
@f4300_es.sql
@f4350_es.sql
@f4400_es.sql
@f4470_es.sql
@f4500_es.sql
@f4550_es.sql
@f4600_es.sql
@f4650_es.sql
@f4700_es.sql
@f4750_es.sql
@f4800_es.sql
@f4850_es.sql
@load_es.sql
@rt_es.sql

