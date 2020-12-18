FROM arm32v7/alpine:3.11

WORKDIR /redis-commander

# optional build arg to let the hardening process remove all package manager (apk, npm, yarn) too to not allow
# installation of packages anymore, default: do not remove "apk" to allow others to use this as a base image
# for own images
ARG REMOVE_APK=0

ENV SERVICE_USER=redis
ENV HOME=/redis-commander
ENV NODE_ENV=production

# only single copy command for most parts as other files are ignored via .dockerignore
# to create less layers
COPY . .

# for Openshift compatibility set project config dir itself group root and make it group writeable
RUN  apk update 
RUN apk upgrade 
RUN apk add --no-cache ca-certificates dumb-init sed jq nodejs npm yarn 
RUN apk add --no-cache --virtual .patch-dep patch 
RUN update-ca-certificates 
RUN echo -e "\n---- Create runtime user and fix file access rights ----------" 
RUN adduser ${SERVICE_USER} -h ${HOME} -G root -S -u 1000 
RUN chown -R root.root ${HOME} 
RUN chown -R ${SERVICE_USER} ${HOME}/config 
RUN chmod g+w ${HOME}/config 
RUN chmod ug+r,o-rwx ${HOME}/config/*.json 
RUN echo -e "\n---- Check config file syntax --------------------------------" 
RUN for i in ${HOME}/config/*.json; do echo "checking config file $i"; cat $i | jq empty; ret=$?; if [ $ret -ne 0 ]; then exit $ret; fi; done 
RUN echo -e "\n---- Installing app ------------------------------------------" 
RUN npm install --production -s 
RUN patch -p0 < docker/redis-dump.diff 
RUN echo -e "\n---- Cleanup and hardening -----------------------------------" 
RUN apk del .patch-dep 
RUN ${HOME}/docker/harden.sh 
RUN rm -rf /tmp/* /root/.??* /root/cache /var/cache/apk/*

USER 1000

HEALTHCHECK --interval=1m --timeout=2s CMD ["/redis-commander/bin/healthcheck.js"]

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/redis-commander/docker/entrypoint.sh"]

EXPOSE 8081

