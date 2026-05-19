# source image - alpine hardened (dev means it has "apk" package manager)
FROM dhi.io/alpine-base:3.23-dev

# set labels
LABEL build_version='2026.05.18'
LABEL maintainer='blomstertj'

# set environment variables
ENV COMPACT_OUTPUT='false'
ENV SKIP_IPME_CHECK='false'

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
# this user is special to the hardened alpine image
# and has a UID of 65532, which is the same as the "nobody" user in many Linux distributions
USER nonroot

# create startup command
ENTRYPOINT [ "/bin/bash" ]
CMD [ "/proton-natpmp-keepalive.sh" ]
