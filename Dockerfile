FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# -------------------------
# Install required packages
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
    python3 \
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
    echo -e "\033[1;33m# Status ====> Configuring UDP Gateway (Port 7300) \033[0m" && \
    # Generate key and print to logs
    GEN_INFO=$(udpgw-server -port 7300 generate) && \
    echo -e "\033[1;32m$GEN_INFO\033[0m" && \
    # Run server in background
    udpgw-server run & \
    sleep 5 && \
    PROXY_DOMAIN=${RAILWAY_TCP_PROXY_DOMAIN:-$(hostname -I | awk '{print $1}')} && \
    PROXY_PORT=${RAILWAY_TCP_PROXY_PORT:-$PORT} && \
    # Get Location and Network Data
    COUNTRY_DATA=$(curl -s "http://ip-api.com/json/") && \
    COUNTRY_CODE=$(echo "$COUNTRY_DATA" | sed -n 's/.*"countryCode":"\([^"]*\)".*/\1/p') && \
    COUNTRY_NAME=$(echo "$COUNTRY_DATA" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p') && \
    COUNTRY_FLAG=$(python3 -c "import sys; print(''.join(chr(127397 + ord(c)) for c in '$COUNTRY_CODE'))") && \
    COUNTRY="${COUNTRY_NAME} ${COUNTRY_FLAG}" && \
    IP=$(getent hosts ${RAILWAY_TCP_PROXY_DOMAIN} | awk '{print $1}' | head -n 1) && \
    # Prepare Variables for Terminal and Telegram
    SSH_CREATE=$(TZ="Africa/Cairo" date +"%Y-%m-%d ~ %I:%M%p") && \
    # Fix: Use %%40 instead of &#37;40 for proper printf interpretation
    USER_NETMOD=$(printf '%s' "$USER" | sed 's/@/%%40/g') && \
    PASS_NETMOD=$(printf '%s' "$PASS" | sed 's/@/%%40/g') && \
    NETMOD="${USER_NETMOD}:${PASS_NETMOD}" && \
    \
    # Print to Terminal (Sync with Telegram Message)
    printf "\n🚀 New SSH Server Deployed!\n" && \
    printf "========== SSH Account ==========\n" && \
    printf "📢 Channel: D_S_D_C1.T.ME\n" && \
    printf "🌍 Country: %s\n" "$COUNTRY" && \
    printf "🌐 IP: %s\n" "$IP" && \
    printf "🔌 Port: %s\n" "$PROXY_PORT" && \
    printf "👤 User: %s\n" "$USER" && \
    printf "🔑 Pass: %s\n" "$PASS" && \
    printf "🎮 Support: UDPGW/Game.Call\n" && \
    printf "========== Net Mod ==========\n" && \
    printf "ssh://%s@%s:%s/#%s %s ~ %s\n" "$NETMOD" "$IP" "$PROXY_PORT" "$COUNTRY_CODE" "$COUNTRY_FLAG" "$SSH_CREATE" && \
    printf "========== HTTP Custom ==========\n" && \
    printf "%s:%s@%s:%s\n\n" "$IP" "$PROXY_PORT" "$USER" "$PASS" && \
    \
    # Send to Telegram and filter output
    if [ ! -z "$TOKEN_BOT" ] && [ ! -z "$OWNER_ID" ]; then \
        # Use %40 for Telegram URL
        USER_TELE=$(printf '%s' "$USER" | sed 's/@/%40/g') && \
        PASS_TELE=$(printf '%s' "$PASS" | sed 's/@/%40/g') && \
        NETMOD_TELE="${USER_TELE}:${PASS_TELE}" && \
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
<code>ssh://${NETMOD_TELE}@${IP}:${PROXY_PORT}/#${COUNTRY_CODE} ${COUNTRY_FLAG} ~ ${SSH_CREATE}</code>\n\
<blockquote><b>========== HTTP Custom ==========</b></blockquote>\n\
<code>${IP}:${PROXY_PORT}@${USER}:${PASS}</code>") && \
        RESP=$(curl -s -X POST "https://api.telegram.org/bot$TOKEN_BOT/sendMessage" \
            -d "chat_id=$OWNER_ID" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=$MSG") && \
        # Print cleaned response attributes
        echo "Attributes" && \
        echo "Raw Data" && \
        echo "Name Value" && \
        echo "ok $(echo $RESP | sed -n 's/.*"ok":\([^,}]*\).*/\1/p')" && \
        echo "result.message_id $(echo $RESP | sed -n 's/.*"message_id":\([^,}]*\).*/\1/p')" && \
        echo "result.date $(echo $RESP | sed -n 's/.*"date":\([^,}]*\).*/\1/p')" && \
        echo "result.text $(printf "🚀 New SSH Server Deployed! ... (Message Sent)")"; \
    fi && \
    echo -e "$SERVER_MESSAGE" > /etc/motd && \
    tail -f /dev/null
