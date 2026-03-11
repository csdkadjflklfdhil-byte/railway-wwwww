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

    COUNTRY_CODE=$(curl -s ipinfo.io/country || echo "UN") && \

    COUNTRY_NAME=$(curl -s ipinfo.io/json | sed -n 's/.*"country_name": "\(.*\)".*/\1/p' || echo "Unknown") && \
    FLAG=$(echo $COUNTRY_CODE | tr 'A-Z' 'a-z' | sed 's/./\&#1274\0;/g' | sed 's/a/64/g;s/b/65/g;s/c/66/g;s/d/67/g;s/e/68/g;s/f/69/g;s/g/70/g;s/h/71/g;s/i/72/g;s/j/73/g;s/k/74/g;s/l/75/g;s/m/76/g;s/n/77/g;s/o/78/g;s/p/79/g;s/q/80/g;s/r/81/g;s/s/82/g;s/t/83/g;s/u/84/g;s/v/85/g;s/w/86/g;s/x/87/g;s/y/88/g;s/z/89/g' | sed 's/ //g') && \
    COUNTRY=$(printf "$COUNTRY_NAME $FLAG") && \

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
    if [ ! -z "$TOKEN_BOT" ] && [ ! -z "$OWNER_ID" ]; then \
        SSH_CREATE=$(TZ="Africa/Cairo" date +"%Y-%m-%d ~ %I:%M%p") && \
        USER_NETMOD=$(printf '%s' "$USER" | sed 's/@/\&#37;40/g') && \
        PASS_NETMOD=$(printf '%s' "$PASS" | sed 's/@/\&#37;40/g') && \
        NETMOD="${USER_NETMOD}:${PASS_NETMOD}" && \
        MSG=$(printf "<blockquote><b>🚀 New SSH Server Deployed!</b></blockquote>\n\n\
<blockquote><b>========== SSH Account ==========</b></blockquote>\n\
📢 <b>Channel:</b> D_S_D_C1.T.ME\n\
🌍 <b>Country:</b> ${COUNTRY}\n\
🌐 <b>IP:</b> <code>${IP}</code>\n\
🔌 <b>Port:</b> <code>${PROXY_PORT}</code>\n\
👤 <b>User:</b> <code>${USER}</code>\n\
🔑 <b>Pass:</b> <code>${PASS}</code>\n\
🎮 <b>Support: UDPGW/Game.Call</b>\n\
<blockquote><b>========== Net Mod ==========</b></blockquote>\n\
<code>ssh://${NETMOD}@${IP}:${PROXY_PORT}/#${COUNTRY} ~ ${SSH_CREATE}</code>\n\
<blockquote><b>========== HTTP Custom ==========</b></blockquote>\n\
<code>${IP}:${PROXY_PORT}@${USER}:${PASS}</code>") && \
        curl -s -X POST "https://api.telegram.org/bot$TOKEN_BOT/sendMessage" \
            -d "chat_id=$OWNER_ID" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=$MSG"; \
    fi && \
    echo -e "$SERVER_MESSAGE" > /etc/motd && \
    tail -f /dev/null
