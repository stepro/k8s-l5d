FROM nginx:1.11-alpine

RUN apk add --no-cache bash curl gettext

RUN curl -fSL https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl

COPY start.sh /
RUN chmod +x /start.sh

ENTRYPOINT ["bash", "/start.sh"]
