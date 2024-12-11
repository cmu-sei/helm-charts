FROM ubuntu:noble

COPY INSTALL.ubuntu2404.sh /usr/local/bin/install-misp.sh
COPY Zscaler.pem /tmp/trust-store.pem
#COPY script.sh /usr/local/bin/install-misp.sh
RUN chmod 755 /usr/local/bin/install-misp.sh

CMD ["/bin/bash", "/usr/local/bin/install-misp.sh"]
