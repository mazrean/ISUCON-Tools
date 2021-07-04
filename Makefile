
export GO111MODULE=on

SHELL=/bin/bash
CONTEST:=isucon10
TEAM:=NEMEX
MEMBER_GITHUB:=mazrean ntaso2051 Fogrexon

GIT_MAIL:="~"#誰かのgitのメールアドレス
GIT_NAME:="~"#誰かのgitの名前
GIT_CONTEST:=$(CONTEST)
GIT_REPO:="git@github.com:$(TEAM)/$(CONTEST).git"

APP_PORT:=8080

DB_HOST:=127.0.0.1#DBのIPアドレス。サーバー分けたときとかに書き換える。
DB_PORT:=3306#DBのポート番号。3306でなければ書き換える。
DB_USER:=~#DBのユーザー名を入れる
DB_PASS:=~#DBのパスワードを入れる
DB_NAME:=~#DBのデータベースの名前を入れる。 

CTL_NAME:=~#systemdのサービス名。

MYSQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

NGX_LOG:=~
MYSQL_LOG:=~
GOR_LOG:=/tmp/replay.log

KATARU_CFG:=./kataribe.toml
NGX_CFG:=~#nginxの設定ファイル
MYSQL_CFG:=~#mysqlの設定ファイル

SLACKCAT:=slackcat --tee --channel
SLACKRAW:=slackcat --channel

CONTEST_CHAN:=$(CONTEST)
PPROF_CHAN:=pprof
KTARU_CHAN:=kataribe
SLOW_CHAN:=query-log
LOG_CHAN:=log
OTHER_CHAN:=other

PPROF:=go tool pprof -png -output pprof.png http://localhost:6060/debug/pprof/profile
DUMP:=curl -s "http://localhost:6060/debug/pprof/goroutine?debug=1"
DSTAT:=dstat -tlnr --top-cpu --top-mem --top-io --top-bio

PROJECT_ROOT:=~#gitリポジトリのディレクトリ
BUILD_DIR:=~#build対象のファイルがある場所
BIN_NAME:=~#build後のファイルの名前

CA:=-o /dev/null -s -w "%{http_code}\n"

all: build

.PHONY: clean
clean:
	cd $(BUILD_DIR); \
	rm -rf torb

deps:
	cd $(BUILD_DIR); \
	go mod download

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl restart $(CTL_NAME).service

.PHONY: test
test:
	curl localhost $(CA)
	sudo ./gor --input-file $(GOR_LOG) --output-http="http://localhost:$(APP_PORT)"

# ここから元から作ってるやつ
.PHONY: dev
dev: build 
	cd $(BUILD_DIR); \
	./$(BIN_NAME)

.PHONY: bench-rc
bench-rec: commit before slow-on dev rec

.PHONY: bench-dev
bench-dev: pull before slow-on dev

.PHONY: bench
bench: pull before slow-on build restart log

.PHONY: log
log: 
	sudo journalctl -u $(CTL_NAME) -n10 -f | $(SLACKCAT) $(LOG_CHAN)

.PHONY: maji
maji: pull before slow-off build restart

.PHONY: anal
anal: slow kataru

.PHONY: rec
rec:
	@if [ -f $(GOR_LOG) ]; then \
		sudo mv -f $(GOR_LOG) ~/logs/$(when)/ ; \
	fi
	sudo ./gor --input-raw :80 --output-file=$(GOR_LOG) --output-http="http://localhost:$(APP_PORT)"

.PHONY: commit
pull:
	cd $(PROJECT_ROOT); \
	git pull origin master

.PHONY: before
before:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	@if [ -f $(NGX_LOG) ]; then \
		sudo mv -f $(NGX_LOG) ~/logs/$(when)/ ; \
	fi
	@if [ -f $(MYSQL_LOG) ]; then \
		sudo mv -f $(MYSQL_LOG) ~/logs/$(when)/ ; \
	fi
	mkdir -p ~/config/$(when)
	sudo mv -f $(NGX_CFG) ~/config/$(when)/ ; \
	sudo cp nginx.conf $(NGX_CFG)
	sudo mv -f $(MYSQL_CFG) ~/config/$(when)/ ; \
	sudo cp sql.conf $(MYSQL_CFG)
	sudo systemctl restart nginx
	sudo systemctl restart mysql

.PHONY: slow
slow: 
	sudo pt-query-digest $(MYSQL_LOG) | $(SLACKCAT) $(SLOW_CHAN) 

.PHONY: kataru
kataru:
	sudo cat $(NGX_LOG) | kataribe -f ./kataribe.toml | $(SLACKCAT) $(KTARU_CHAN)

.PHONY: pprof
pprof:
	$(PPROF)
	$(SLACKRAW) $(PPROF_CHAN) -n pprof.png ./pprof.png

.PHONY: dump
dump:
	$(DUMP) | $(SLACKCAT) $(OTHER_CHAN)

.PHONY: stat
stat:
	$(DSTAT)

.PHONY: slow-on
slow-on:
	# sudo mysql -e "set global slow_query_log_file = '$(MYSQL_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;"
	sudo $(MYSQL_CMD) -e "set global slow_query_log_file = '$(MYSQL_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	# sudo mysql -e "set global slow_query_log = OFF;"
	sudo $(MYSQL_CMD) -e "set global slow_query_log = OFF;"

.PHONY: setup
setup:
	sudo apt update
	sudo apt install -y git openssh-server
	sudo apt upgrade git openssh-server
	git config --global user.email $(GIT_MAIL)
	git config --global user.name $(GIT_NAME)
	ssh-keygen -t ed25519 -C $(GIT_MAIL)
	cat ~/.ssh/id_ed25519.pub
	read hoge
	git init
	git commit --allow-empty -m "initial commit"
	git remote add origin $(GIT_REPO)
	git add .
	git commit -m "init"
	git push origin master
	# members="$(MEMBER_GITHUB)";\
	for member in $$members; do\
	 curl https://github.com/$$member.keys >> ~/.ssh/authorized_keys;\
	done
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat  unzip snapd graphviz gv htop
	wget https://github.com/matsuu/kataribe/releases/download/v0.4.1/kataribe-v0.4.1_linux_amd64.zip -O kataribe.zip
	unzip -o kataribe.zip
	sudo mv kataribe /usr/local/bin/
	sudo chmod +x /usr/local/bin/kataribe
	rm kataribe.zip
	kataribe -generate
	wget https://github.com/KLab/myprofiler/releases/download/0.2/myprofiler.linux_amd64.tar.gz
	tar -xf myprofiler.linux_amd64.tar.gz
	rm myprofiler.linux_amd64.tar.gz
	sudo mv myprofiler /usr/local/bin/
	sudo chmod +x /usr/local/bin/myprofiler
	wget https://github.com/buger/goreplay/releases/download/v1.1.0/gor_1.1.0_x64.tar.gz
	tar -xf gor_1.1.0_x64.tar.gz
	sudo mv gor /usr/local/bin/
	rm gor_1.1.0_x64.tar.gz
	wget https://github.com/bcicen/slackcat/releases/download/v1.5/slackcat-1.5-linux-amd64 -O slackcat
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
	slackcat --configure

.PHONY: set
set:
	sudo apt update
	sudo apt install -y git openssh-server
	sudo apt upgrade git openssh-server
	git config --global user.email $(GIT_MAIL)
	git config --global user.name $(GIT_NAME)
	ssh-keygen -t ed25519 -C $(GIT_MAIL)
	cat ~/.ssh/id_ed25519.pub
	read hoge
	mkdir ~/hogehoge
	mv $(PROJECT_ROOT) ~/hogehoge/
	mkdir $(PROJECT_ROOT)
	cd $(PROJECT_ROOT)
	git init
	git remote add origin $(GIT_REPO)
	git pull origin master
	# members="$(MEMBER_GITHUB)";\
	for member in $$members; do\
	 curl https://github.com/$$member.keys >> ~/.ssh/authorized_keys;\
	done
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat  unzip snapd graphviz gv htop
	wget https://github.com/matsuu/kataribe/releases/download/v0.4.1/kataribe-v0.4.1_linux_amd64.zip -O kataribe.zip
	unzip -o kataribe.zip
	sudo mv kataribe /usr/local/bin/
	sudo chmod +x /usr/local/bin/kataribe
	rm kataribe.zip
	kataribe -generate
	wget https://github.com/KLab/myprofiler/releases/download/0.2/myprofiler.linux_amd64.tar.gz
	tar -xf myprofiler.linux_amd64.tar.gz
	rm myprofiler.linux_amd64.tar.gz
	sudo mv myprofiler /usr/local/bin/
	sudo chmod +x /usr/local/bin/myprofiler
	wget https://github.com/buger/goreplay/releases/download/v1.1.0/gor_1.1.0_x64.tar.gz
	tar -xf gor_1.1.0_x64.tar.gz
	sudo mv gor /usr/local/bin/
	rm gor_1.1.0_x64.tar.gz
	wget https://github.com/bcicen/slackcat/releases/download/v1.5/slackcat-1.5-linux-amd64 -O slackcat
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
	slackcat --configure