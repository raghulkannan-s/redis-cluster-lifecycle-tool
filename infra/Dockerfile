FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y openssh-server sudo python3 iproute2 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /root/.ssh && \
    chmod 700 /root/.ssh

COPY keys/id_rsa.pub /root/.ssh/authorized_keys

RUN chmod 600 /root/.ssh/authorized_keys && \
    chown root:root /root/.ssh/authorized_keys

RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]