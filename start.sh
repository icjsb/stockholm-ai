#!/usr/bin/env bash
set -ex

docker --version

REMOTE=https://github.com/Stockholm-AI/stockholm-ai
BRANCH=master

SOURCE_VOLUME=stockholm-ai-source-$BRANCH
DESTINATION_VOLUME=stockholm-ai-destination-$BRANCH

SYNCER_NAME=stockholm-ai-syncer-$BRANCH
SYNCER_IMAGE=indiehosters/git:latest

SERVER_NAME=stockholm-ai-server-$BRANCH
SERVER_IMAGE=jekyll/jekyll:builder

API_NAME=stockholm-ai-api
API_IMAGE=python:alpine

PROXY_NAME=stockholm-ai-proxy
PROXY_IMAGE=nginx:alpine

NETWORK=stockholm-ai-network

function cleanup {
    docker rm -f $SYNCER_NAME || true
    docker rm -f $PROXY_NAME || true
    docker rm -f $MAILING_LIST_PROXY_NAME || true
    docker rm -f $SERVER_NAME || true
    docker volume rm $SOURCE_VOLUME || true
    docker volume rm $DESTINATION_VOLUME || true
    docker network rm $NETWORK || true
} && cleanup && trap cleanup EXIT

docker volume create --name $SOURCE_VOLUME
docker volume create --name $DESTINATION_VOLUME

docker network create --driver bridge $NETWORK

docker run \
    --detach \
    --restart unless-stopped \
    --volume $SOURCE_VOLUME:/source \
    --name $SYNCER_NAME $SYNCER_IMAGE \
    /bin/sh -c "git clone $REMOTE /source && cd /source && git checkout $BRANCH && while true; do git pull && sleep 1; done"

docker run \
    --detach \
    --restart unless-stopped \
    --publish 80:80 \
    --volume $DESTINATION_VOLUME:/usr/share/nginx/html \
    --name $PROXY_NAME \
    $PROXY_IMAGE

docker run \
    --detach \
    --restart unless-stopped \
    --publish 8000:8000 \
    --network $NETWORK \
    --volume `pwd`/_api/api.py:/api.py \
    --name $API_NAME \
    $API_IMAGE \
    /bin/sh -c "pip install requests Flask && python -m http.server"


docker run \
    --detach \
    --restart unless-stopped \
    --network $NETWORK \
    --volume $SOURCE_VOLUME:/source \
    --volume $DESTINATION_VOLUME:/destination \
    --volume `pwd`/nginx_conf:/etc/nginx:ro \
    --name $SERVER_NAME \
    --user root \
    $SERVER_IMAGE \
    /bin/sh -c "[[ -f /source/_config.yml ]] && jekyll build --watch --source /source --config /source/_config.yml --destination /destination"


sleep infinity
