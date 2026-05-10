# source image
FROM alpine:latest

LABEL build_version="2026.05.09"
LABEL maintainer="blomstertj"

# install bash, curl, and libnatpmp
RUN echo "**** install packages ****" && \
    apk add --no-cache bash curl libnatpmp

# clean up container /tmp dir
RUN echo "**** cleanup ****" && \
    rm -rf /tmp/*

# copy bash script to container / dir
COPY alpine-nat-pmp/proton-natpmp-keepalive.sh /

# create startup command
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/proton-natpmp-keepalive.sh" ]
