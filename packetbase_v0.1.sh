#!/bin/bash

# Default values
ES_MEM_LIMIT=4294967296
ENCRYPTION_KEY=c34d38b3a14956121ff2170e5030b471551370178f43e5626eec58b04a30fae2
ES_VERSION=7.10.2
DATABASE_HOST=es01
DATABASE_USER=root
DATABASE_PASSWORD=root
ML_API=${NEXT_PUBLIC_ML_API:-localhost}
DB_API=${NEXT_PUBLIC_DB_API:-localhost}
ML_API_PORT=${NEXT_PUBLIC_ML_API_PORT:-8080}
DB_API_PORT=${NEXT_PUBLIC_DB_API_PORT:-8000}

# Parsing arguments
for arg in "$@"
do
    case $arg in
        --ml-api=*)
        IFS=':' read -ra ML_API_ARG <<< "${arg#*=}"
        ML_API=${ML_API_ARG[0]}
        ML_API_PORT=${ML_API_ARG[1]}
        shift
        ;;
        --db-api=*)
        IFS=':' read -ra DB_API_ARG <<< "${arg#*=}"
        DB_API=${DB_API_ARG[0]}
        DB_API_PORT=${DB_API_ARG[1]}
        shift
        ;;
    esac
done

# User input
read -p "Enter Elastic Password: " ELASTIC_PASSWORD
read -p "Enter cluster name: " CLUSTER_NAME
read -p "Enter Elastic Port: " ES_PORT
read -p "Enter default username: " NEXT_PUBLIC_USERNAME
read -p "Enter default password: " NEXT_PUBLIC_PASSWORD

# Setting variables from arguments
if [ ! -z "$ML_API" ]; then
    NEXT_PUBLIC_ML_API=$ML_API
    NEXT_PUBLIC_ML_API_PORT=$ML_API_PORT
fi

if [ ! -z "$DB_API" ]; then
    NEXT_PUBLIC_DB_API=$DB_API
    NEXT_PUBLIC_DB_API_PORT=$DB_API_PORT
fi

# Create .db_env file
cat > .db_env << EOF
ELASTIC_PASSWORD=$ELASTIC_PASSWORD
CLUSTER_NAME=$CLUSTER_NAME
ES_VERSION=$ES_VERSION
ES_PORT=$ES_PORT
ES_MEM_LIMIT=$ES_MEM_LIMIT
ENCRYPTION_KEY=$ENCRYPTION_KEY
EOF

# Create .frontend_env file
cat > .frontend_env << EOF
NEXT_PUBLIC_USERNAME=$NEXT_PUBLIC_USERNAME
NEXT_PUBLIC_PASSWORD=$NEXT_PUBLIC_PASSWORD
NEXT_PUBLIC_DB_API=$NEXT_PUBLIC_DB_API
NEXT_PUBLIC_DB_API_PORT=$NEXT_PUBLIC_DB_API_PORT
NEXT_PUBLIC_ML_API=$NEXT_PUBLIC_ML_API
NEXT_PUBLIC_ML_API_PORT=$NEXT_PUBLIC_ML_API_PORT
EOF

# Create .ml_api_env file
echo "API_PORT=$ML_API_PORT" > .ml_api_env

# Create .db_api_env file
cat > .db_api_env << EOF
DATABASE_HOST=$DATABASE_HOST
DATABASE_PORT=$ES_PORT
DATABASE_USER=$DATABASE_USER
DATABASE_PASSWORD=$DATABASE_PASSWORD
API_PORT=$DB_API_PORT
EOF

# Create .sniffer_env file
cat > .sniffer_env << EOF
ML_API=http://${NEXT_PUBLIC_ML_API}
ML_API_PORT=$NEXT_PUBLIC_ML_API_PORT
DB_API=http://${NEXT_PUBLIC_DB_API}
DB_API_PORT=$NEXT_PUBLIC_DB_API_PORT
EOF

# Pull Docker images
docker pull packetbase/frontend:latest
docker pull packetbase/db-api:latest
docker pull packetbase/ml-api:latest
docker pull packetbase/db:latest
docker pull packetbase/sniffer:latest

# Set up netowrk
docker network create es-net

# Run Docker images inside created network
docker run -d --network es-net packetbase/frontend --env-file ./frontend_env
docker run -d --network es-net packetbase/db-api --env-file ./db_api_env
docker run -d --network es-net packetbase/ml-api --env-file ./ml_api_env
docker run -d --network es-net packetbase/db --env-file ./db_env
docker run -d --network es-net packetbase/sniffer --env-file ./sniffer_env
