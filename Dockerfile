FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# -------------------------
# Install required packages + Golang
# -------------------------
RUN apt update && apt install -y \
    openssh-server \
    stunnel4 \
    sudo \
    curl \
    nano \
    net-tools \
    iproute2 \
    openssl \
    git \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# -------------------------
# Configure SSH
# -------------------------
RUN mkdir /var/run/sshd

ARG USER
ARG PASS
ARG PORT
ARG SERVER_MESSAGE
ARG TOKEN_BOT
ARG OWNER_ID

ENV USER=$USER
ENV PASS=$PASS
ENV PORT=$PORT
ENV SERVER_MESSAGE=$SERVER_MESSAGE
ENV TOKEN_BOT=$TOKEN_BOT
ENV OWNER_ID=$OWNER_ID

RUN useradd -m -s /bin/bash $USER && \
    echo "$USER:$PASS" | chpasswd && \
    adduser $USER sudo

RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# -------------------------
# Build UDP Gateway (Go version)
# -------------------------
RUN git clone https://github.com/mukswilly/udpgw.git /opt/udpgw && \
    cd /opt/udpgw/cmd && \
    go build -o /usr/local/bin/udpgw-server

# -------------------------
# Configure stunnel
# -------------------------
RUN openssl req -new -x509 -days 365 -nodes \
    -out /etc/stunnel/stunnel.pem \
    -keyout /etc/stunnel/stunnel.pem \
    -subj "/C=US/ST=Railway/L=Railway/O=Railway/CN=localhost"

RUN chmod 600 /etc/stunnel/stunnel.pem

RUN cat <<EOF > /etc/stunnel/stunnel.conf
foreground = yes
[ssh]
accept = 0.0.0.0:$PORT
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
EOF

EXPOSE $PORT

# -------------------------
# Configure SSH Banner
# -------------------------
RUN BANNER_FILE="/etc/mybanner" && \
    SSH_CONFIG="/etc/ssh/sshd_config" && \
    echo "$SERVER_MESSAGE" > "$BANNER_FILE" && \
    sed -i "s|#Banner.*|Banner $BANNER_FILE|" $SSH_CONFIG

# -------------------------
# Start Services
# -------------------------
CMD /usr/sbin/sshd && \
    stunnel /etc/stunnel/stunnel.conf > /dev/null 2>&1 & \
    echo -e "\033[1;33m# Run ====> Configuring UDP Gateway (Port 7300) \033[0m" && \
    # توليد المفتاح وطباعته في الـ Logs
    GEN_INFO=$(udpgw-server -port 7300 generate) && \
    echo -e "\033[1;32m$GEN_INFO\033[0m" && \
    # تشغيل السيرفر في الخلفية
    udpgw-server run & \
    sleep 5 && \
    PROXY_DOMAIN=${RAILWAY_TCP_PROXY_DOMAIN:-$(hostname -I | awk '{print $1}')} && \
    PROXY_PORT=${RAILWAY_TCP_PROXY_PORT:-$PORT} && \
    COUNTRY=$(curl -s ipinfo.io/country || echo "Unknown") && \
    IP=$(getent hosts ${RAILWAY_TCP_PROXY_DOMAIN} | awk '{print $1}' | head -n 1) && \
    \
    printf "========== SSH Account ==========\n" && \
    printf "CHANNEL URL: D_S_D_C1.T.ME\n" && \
    printf "VPS Country: %s\n" "$COUNTRY" && \
    printf "IP Address: %s\n" "$IP" && \
    printf "Port: %s\n" "$PROXY_PORT" && \
    printf "User: %s\n" "$USER" && \
    printf "Pass: %s\n" "$PASS" && \
    printf "Support: UDPGW/Game.Call\n" && \
    printf "========== HTTP Custom ==========\n" && \
    printf "%s:%s@%s:%s\n" "$IP" "$PROXY_PORT" "$USER" "$PASS" && \
    \
    if [ ! -z "$TOKEN_BOT" ] && [ ! -z "$OWNER_ID" ]; then \
            MSG="<blockquote><b>🚀 New SSH Server Deployed!</b></blockquote>%0A%0A" && \
            MSG="${MSG}<blockquote><b>========== SSH Account ==========</b></blockquote>%0A" && \
            MSG="${MSG}📢 <b>Channel:</b> D_S_D_C1.T.ME%0A" && \
            MSG="${MSG}🌍 <b>Country:</b> ${COUNTRY}%0A" && \
            MSG="${MSG}🌐 <b>IP:</b> <code>${IP}</code>%0A" && \
            MSG="${MSG}🔌 <b>Port:</b> <code>${PROXY_PORT}</code>%0A" && \
            MSG="${MSG}👤 <b>User:</b> <code>${USER}</code>%0A" && \
            MSG="${MSG}🔑 <b>Pass:</b> <code>${PASS}</code>%0A" && \
            MSG="${MSG}🎮 <b>Support: UDPGW/Game.Call</b>%0A" && \
            MSG="${MSG}<blockquote><b>========== HTTP Custom ==========</b></blockquote>%0A" && \
            MSG="${MSG}<code>${IP}:${PROXY_PORT}@${USER}:${PASS}</code>"; \
            \
            curl -s -X POST "https://api.telegram.org/bot$TOKEN_BOT/sendMessage" \
                -d "chat_id=$OWNER_ID" \
                -d "parse_mode=HTML" \
                -d "text=$MSG" > /dev/null; \
        fi && \
        echo -e "$SERVER_MESSAGE" > /etc/motd && \
        tail -f /dev/null
