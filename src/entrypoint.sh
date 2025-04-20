#!/bin/bash

# Wait for Oracle Database to be ready
echo "Waiting for Oracle Database to be ready..."
until echo "exit" | sqlplus "sys/YourPassword123@//localhost:1521/XEPDB1 as sysdba"; do
  sleep 10
done

# Install APEX
echo "Installing APEX..."
sqlplus sys/YourPassword123@//localhost:1521/XEPDB1 as sysdba <<EOF
ALTER SESSION SET CONTAINER = XEPDB1;
@/home/oracle/apex/apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

# Set Accounts
echo "Setting APEX accounts..."
sqlplus sys/YourPassword123@//localhost:1521/XEPDB1 as sysdba <<EOF
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY pAwKWainteRA;
EXIT;
EOF

# Create ADMIN Account silently
echo "Creating ADMIN account..."
sqlplus sys/YourPassword123@//localhost:1521/XEPDB1 as sysdba <<EOF
ALTER SESSION SET CONTAINER = XEPDB1;
BEGIN
    APEX_UTIL.set_security_group_id( 10 );
    APEX_UTIL.create_user(
        p_user_name       => 'ADMIN',
        p_email_address   => 'jayala@solvet-it.com.py',
        p_web_password    => 'pAwKWainteRA',
        p_developer_privs => 'ADMIN' );
        
    APEX_UTIL.set_security_group_id( null );
    COMMIT;
END;
/
EOF

# Configure ORDS
echo "Configuring ORDS..."
export ORDS_HOME=/home/oracle/ords
export ORDS_CONFIG=/etc/ords/config

ords --config ${ORDS_CONFIG} install \
     --admin-user sys \
     --db-hostname localhost \
     --db-port 1521 \
     --db-servicename XEPDB1 \
     --feature-db-api true \
     --feature-rest-enabled-sql true \
     --feature-sdw true \
     --gateway-mode proxied \
     --gateway-user APEX_PUBLIC_USER \
     --password-stdin <<EOT
YourPassword123
YourPassword123
EOT

# Configure ORDS Standalone
ords --config ${ORDS_CONFIG} config set standalone.context.path /ords 
ords --config ${ORDS_CONFIG} config set standalone.doc.root ${ORDS_CONFIG}/global/doc_root 
ords --config ${ORDS_CONFIG} config set standalone.http.port 8080
ords --config ${ORDS_CONFIG} config set standalone.static.context.path /i 
ords --config ${ORDS_CONFIG} config set standalone.static.path /home/oracle/apex/images/ 
ords --config ${ORDS_CONFIG} config set jdbc.InitialLimit 15 
ords --config ${ORDS_CONFIG} config set jdbc.MaxLimit 25 
ords --config ${ORDS_CONFIG} config set jdbc.MinLimit 15  

# Start ORDS
echo "Starting ORDS..."
ords --config ${ORDS_CONFIG} serve