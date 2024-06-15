FROM ubuntu:22.04
RUN apt-get update && apt-get install -y slapd ldap-utils
COPY slapd.conf /etc/ldap/slapd.conf
COPY bootstrap.sh /bootstrap.sh
RUN chmod +x /bootstrap.sh
CMD ["/bootstrap.sh"]
