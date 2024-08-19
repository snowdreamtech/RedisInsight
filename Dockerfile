FROM snowdreamtech/node:20.15.1 AS builder

LABEL maintainer="snowdream <sn0wdr1am@qq.com>"

ENV REDISINSIGHT_VERSION=2.54

RUN mkdir /workspace

WORKDIR /workspace

RUN apk update && apk add --no-cache --virtual .gyp \
    python3 \
    make \
    g++ \
    && wget -c https://github.com/RedisInsight/RedisInsight/archive/refs/tags/${REDISINSIGHT_VERSION}.tar.gz \ 
    && tar zxvf ${REDISINSIGHT_VERSION}.tar.gz \ 
    && mv RedisInsight-${REDISINSIGHT_VERSION} redisinsight \ 
    && cd redisinsight \ 
    && yarn --ignore-scripts install --frozen-lockfile \
    && yarn --cwd redisinsight/api install \
    && yarn build:ui \
    && yarn build:statics \
    && yarn build:api \
    && yarn --cwd ./redisinsight/api install --production \
    && cp redisinsight/api/.yarnclean.prod redisinsight/api/.yarnclean \
    && yarn --cwd ./redisinsight/api autoclean --force
    


FROM snowdreamtech/node:20.15.1 

LABEL maintainer="snowdream <sn0wdr1am@qq.com>"

# runtime args and environment variables
ARG NODE_ENV=production
ARG RI_SEGMENT_WRITE_KEY
ENV RI_SEGMENT_WRITE_KEY=${RI_SEGMENT_WRITE_KEY}
ENV NODE_ENV=${NODE_ENV}
ENV RI_SERVE_STATICS=true
ENV RI_BUILD_TYPE='DOCKER_ON_PREMISE'
ENV RI_APP_FOLDER_ABSOLUTE_PATH='/data'

# this resolves CVE-2023-5363
# TODO: remove this line once we update to base image that doesn't have this vulnerability
RUN apk update && apk upgrade --no-cache libcrypto3 libssl3

# set workdir
WORKDIR /workspace

# copy artifacts built in previous stage to this one
COPY --from=builder --chown=node:node /workspace/redisinsight/api/dist ./redisinsight/api/dist
COPY --from=builder --chown=node:node /workspace/redisinsight/api/node_modules ./redisinsight/api/node_modules
COPY --from=builder --chown=node:node /workspace/redisinsight/ui/dist ./redisinsight/ui/dist

# folder to store local database, plugins, logs and all other files
RUN mkdir -p /data && chown -R node:node /data

# copy the docker entry point script and make it executable
COPY --chown=node:node ./docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# since RI is hard-code to port 5540, expose it from the container
EXPOSE 5540

# don't run the node process as root
USER node

# serve the application 🚀
ENTRYPOINT ["./docker-entrypoint.sh", "node", "redisinsight/api/dist/src/main"]