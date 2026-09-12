FROM ubuntu:latest

# Squidのインストール
RUN apt update 
RUN apt install -y squid

# Squidの設定ファイルをコンテナにコピー
COPY squid.conf /etc/squid/squid.conf

# Squidのポートを開放
EXPOSE 8080

# Squidをフォアグラウンドで起動
CMD ["/usr/sbin/squid", "-N", "-f", "/etc/squid/squid.conf"]
