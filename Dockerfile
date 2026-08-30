# source image - alpine hardened (dev means it has "apk" package manager)
FROM dhi.io/alpine-base:3.23-dev

# set labels
LABEL build_version='2026.05.19'
LABEL maintainer='blomstertj'

# set environment variables
ENV COMPACT_OUTPUT='false'
ENV SKIP_IPME_CHECK='false'
ENV NATPMP_GATEWAY='10.2.0.1'
ENV NATPMP_PUBLIC_PORT='1'
ENV NATPMP_PRIVATE_PORT='0'
ENV NATPMP_LIFETIME='60'
ENV NATPMP_REFRESH_INTERVAL='45'
ENV NATPMP_MAPPING_NAME='default'
ENV TZ='UTC'

# install bash, curl, and libnatpmp
RUN echo "**** install packages ****" && \
    apk add --no-cache bash curl libnatpmp tzdata

RUN echo "**** set timezone ****" && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone

# clean up container /tmp, /var/log, and /var/cache/apk
RUN echo "**** cleanup ****" && \
    rm -rf /tmp/* && \
    rm -rf /var/log/* && \
    rm -rf /var/cache/apk/*

# copy bash script to container / dir
COPY proton-natpmp-keepalive.sh /

# copy entrypoint script to container / dir
RUN echo "**** set ownership and permissions ****" && \
    chown nonroot:nonroot /proton-natpmp-keepalive.sh && \
    chmod +x /proton-natpmp-keepalive.sh

# set the container user to nonroot
# this user is special to the hardened alpine image
# and has a UID of 65532, which is the same as the "nobody" user in many Linux distributions
USER nonroot

# create startup command
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/proton-natpmp-keepalive.sh" ]
