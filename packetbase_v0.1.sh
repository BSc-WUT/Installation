#!/bin/bash

# Default values
ES_MEM_LIMIT=4294967296
ES_VERSION=7.10.2
DATABASE_HOST=es01
DATABASE_USER=elastic
ML_API=${NEXT_PUBLIC_ML_API:-localhost}
DB_API=${NEXT_PUBLIC_DB_API:-localhost}
DB=${DB:-es01}
DB_PORT=${DB_PORT:-9200}
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
        --elastic=*)
        IFS=':' read -ra DB_ARG <<< "${arg#*=}"
        DB=${DB_ARG[0]}
        DB_PORT=${DB_ARG[1]}
        shift
        ;;
    esac
done

echo -e "Welcome to \e[94m_PACKET_BASE\e[1m!"
echo -e "\e[30m\e[0m"
sleep 0.3

# User input
echo "Please provide elastic password which will be used for database authentication"
read -p "Enter Elastic Password: " ELASTIC_PASSWORD
sleep 0.3

read -p "Enter cluster name: " CLUSTER_NAME
sleep 0.3

echo "Please provide default username and password for packetbase."
read -p "Enter default username: " NEXT_PUBLIC_USERNAME
read -p "Enter default password: " NEXT_PUBLIC_PASSWORD
sleep 0.3
echo


# Get network interface for packet sniffer
IFS=$'\n' read -r -d '' -a interfaces < <( ip link show | grep -Po '^\d+: \K[^:]+')

if [ ${#interfaces[@]} -eq 0 ]; then
    echo "No network interfaces found."
    exit 1
fi

echo "Available network interfaces:"
for i in "${!interfaces[@]}"; do
    echo "$((i+1))) ${interfaces[i]}"
done

while true; do
    read -p "Please select an interface (1-${#interfaces[@]}): " choice

    # Validate input
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
        selected_interface=${interfaces[$((choice-1))]}
        INTERFACE=$selected_interface
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

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
ES_PORT=$DB_PORT
ES_MEM_LIMIT=$ES_MEM_LIMIT
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
DATABASE_PORT=$DB_PORT
DATABASE=$DB
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
INTERFACE=$INTERFACE
EOF

# Docker Cleanup
echo "Starting Docker cleanup"
echo "Removing tangling containers..."
docker image prune -f # Remove tangling containers
echo "Finished"

if [[ "$(docker ps -a -q 2> /dev/null)" != "" ]]; then
  echo "Removing all exited containers..."
  docker stop $(docker ps -a -q)
  docker rm $(docker ps -a -q) # Remove exited containers
  echo "Finished"
fi


check_and_update_image() {
  local image=$1
  echo "Checking for updates for $image..."

  # Pull the latest image digest from the registry
  local latest_digest=$(docker pull --quiet "$image" 2>/dev/null | tail -1)

  # Get the current image digest
  local current_digest=$(docker images --no-trunc --quiet "$image" 2>/dev/null)

  if [[ "$latest_digest" != "$current_digest" ]]; then
    echo "The image $image is outdated. Updating..."
    docker pull "$image"
    echo "Updated image: $image"
  else
    echo "The image $image is up-to-date."
  fi
}

images=(
  "packetbase/frontend:latest"
  "packetbase/ml-api:latest"
  "packetbase/db-api:latest"
  "packetbase/db:latest"
  "packetbase/sniffer:latest"
)

# Pull Docker images
echo "Pulling docker images..."
for image in "${images[@]}"; do
  if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    echo "Image: $image does not exist locally. Pulling..."
    docker pull "$image"
    echo "Pulled image: $image"
  else
    check_and_update_image "$image"
  fi
done
echo
sleep 0.3

# Set up netowrk
echo "Creating docker network..."
docker network create es-net
sleep 0.3
echo

# Run Docker images inside created network
echo "Running docker containers..."
docker run -d --network es-net --env-file ./.frontend_env \
    --name frontend \
    --hostname frontend \
     -p 3000:3000 \
     packetbase/frontend
docker run -d --network es-net --env-file ./.db_api_env \
    --name db_api \
    -p $NEXT_PUBLIC_DB_API_PORT:$NEXT_PUBLIC_DB_API_PORT \
     packetbase/db-api
docker run -d --network es-net --env-file ./.ml_api_env \
    --name ml_api \
    -p $NEXT_PUBLIC_ML_API_PORT:$NEXT_PUBLIC_ML_API_PORT \
    packetbase/ml-api
docker run -d --network es-net --env-file ./.db_env \
    --name es01 \
    --hostname es01 \
    -e discovery.type=single-node \
    --volume es-data-01:/usr/share/elasticsearch/data \
    --ulimit memlock=-1:-1 \
    --ulimit nofile=65536:65536 \
    --memory ${ES_MEM_LIMIT} \
    -p $DB_PORT:$DB_PORT \
    -p 9300:9300 \
    packetbase/db
sleep 5
docker run -d --network=host --env-file ./.sniffer_env \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    packetbase/sniffer
