# source image - alpine hardened (dev means it has "apk" package manager)
FROM dhi.io/alpine-base:3.23-dev

LABEL build_version="2026.05.10"
LABEL maintainer="blomstertj"

# install bash, curl, and libnatpmp
RUN echo "**** install packages ****" && \
    apk add --no-cache bash curl libnatpmp

# clean up container /tmp dir
RUN echo "**** cleanup ****" && \
    rm -rf /tmp/*

# copy bash script to container / dir
COPY proton-natpmp-keepalive.sh /

# copy entrypoint script to container / dir
RUN echo "**** set ownership and permissions ****" && \
    chown nonroot:nonroot /proton-natpmp-keepalive.sh && \
    chmod +x /proton-natpmp-keepalive.sh

# set the container user to nonroot
USER nonroot
# create startup command
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/proton-natpmp-keepalive.sh" ]
