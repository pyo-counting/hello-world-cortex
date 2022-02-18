#!/bin/bash

cat > /init.cql <<EOF
CREATE KEYSPACE IF NOT EXISTS cortex WITH replication = {'class':'SimpleStrategy', 'replication_factor' : 1};
EOF

until cqlsh -f /init.cql; do
        echo "cqlsh: Cassandra is unavailable to initialize - will retry later"
        sleep 5s
done &

exec /docker-entrypoint.sh "$@"
