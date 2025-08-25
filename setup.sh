#!/bin/bash

# Prompt the user for the IP address or domain assuming he doesn't know what a locahost is
read -p "Enter the IP address or domain that you will use for Fleetbase, if running on localhost (on the machine that is physically infront of you at the simplest case) then write the word localhost: " FLEETBASE_HOST

# Validate the input
if [[ -z "$FLEETBASE_HOST" ]]; then
  echo "Error: No IP address or domain provided. Exiting setup."
  exit 1
fi

# Clone the Fleetbase repository
git clone https://github.com/fleetbase/fleetbase.git
cd fleetbase || exit

# Create a docker-compose.override.yml file to override environment variables
cat <<EOL > docker-compose.override.yml
services:
  cache:
    image: redis:4-alpine

  database:
    image: mysql:8.0-oracle
    ports:
      - "3306:3306"
    volumes:
      - "./docker/database/:/docker-entrypoint-initdb.d/"
      - "./docker/database/mysql:/var/lib/mysql"
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: "yes"
      MYSQL_DATABASE: "fleetbase"

  socket:
    image: socketcluster/socketcluster:v17.4.0
    ports:
      - "38000:8000"
    environment:
      SOCKETCLUSTER_WORKERS: 10
      SOCKETCLUSTER_BROKERS: 10

  queue:
    build:
      context: .
      dockerfile: docker/Dockerfile
      target: events-dev
      args:
        ENVIRONMENT: development
    environment:
      DATABASE_URL: "mysql://root@database/fleetbase"
      QUEUE_CONNECTION: redis
      CACHE_DRIVER: redis
      CACHE_PATH: /fleetbase/api/storage/framework/cache
      CACHE_URL: tcp://cache
      REDIS_URL: tcp://cache

  console:
    build:
      context: .
      dockerfile: console/Dockerfile.server-build
      args:
        ENVIRONMENT: development
    ports:
      - "4200:4200"
    volumes:
      - console-build:/console

  application:
    build:
      context: .
      dockerfile: docker/Dockerfile
      target: app-dev
      args:
        ENVIRONMENT: development
        GITHUB_AUTH_KEY: ${GITHUB_AUTH_KEY}
    volumes:
      - console-build:/fleetbase/console
    environment:
      ENVIRONMENT: development
      CONSOLE_HOST: "http://$FLEETBASE_HOST:4200"
      APP_URL: http://$FLEETBASE_HOST:8000
      DATABASE_URL: "mysql://root@database/fleetbase"
      QUEUE_CONNECTION: redis
      CACHE_DRIVER: redis
      CACHE_PATH: /fleetbase/api/storage/framework/cache
      CACHE_URL: tcp://cache
      REDIS_URL: tcp://cache
      SESSION_DOMAIN: localhost
      BROADCAST_DRIVER: socketcluster
      MAIL_FROM_NAME: Fleetbase
      APP_NAME: Fleetbase
      LOG_CHANNEL: daily
      REGISTRY_HOST: https://registry.fleetbase.io
      REGISTRY_PREINSTALLED_EXTENSIONS: 'true'
      OSRM_HOST: https://router.project-osrm.org
    depends_on:
      - database
      - cache
      - queue

  httpd:
    build:
      context: .
      dockerfile: docker/httpd/Dockerfile
    ports:
      - "8000:80"
    depends_on:
      - application

volumes:
  console-build:
EOL

# setup console env
cd console
cd environments
cat <<EOL > .env.development
API_HOST=http://$FLEETBASE_HOST:8000
API_NAMESPACE=int/v1
SOCKETCLUSTER_PATH=/socketcluster/
SOCKETCLUSTER_HOST=$FLEETBASE_HOST
SOCKETCLUSTER_SECURE=false
SOCKETCLUSTER_PORT=38000
OSRM_HOST=https://router.project-osrm.org
EOL

cat <<EOL > .env.production
API_HOST=$FLEETBASE_HOST:8000
API_NAMESPACE=int/v1
API_SECURE=true
SOCKETCLUSTER_PATH=/socketcluster/
SOCKETCLUSTER_HOST=$FLEETBASE_HOST
SOCKETCLUSTER_SECURE=true
SOCKETCLUSTER_PORT=38000
OSRM_HOST=https://router.project-osrm.org
EOL

cd ..
cd ..

# Build and Start the services using docker-compose
docker compose up --build -d

echo "deploying back-end, this might take a while, be patient"

sleep 500

# Enter the application container
docker exec -ti fleetbase-application-1 bash -c "bash deploy.sh"

echo "Fleetbase setup is complete. Access the console at http://$FLEETBASE_HOST:4200 and make dua to Allah for me that i get married soon :)"
