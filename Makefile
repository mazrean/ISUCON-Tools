include .make.env

SHELL=/bin/bash
CONTEST:=isucon10-local
TEAM:=mazrean
MEMBER_GITHUB:=mazrean

GIT_CONTEST:=$(CONTEST)
GIT_REPO:="git@github.com:$(TEAM)/$(CONTEST).git"

APP_PORT:=8080

MYSQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

SLACKCAT:=slackcat --tee --channel
SLACKRAW:=slackcat --channel

CONTEST_CHAN:=$(CONTEST)

FGPROF:=go tool pprof -png -output fgprof.png http://localhost:6060/debug/fgprof
PPROF:=go tool pprof -png -output pprof.png http://localhost:6060/debug/pprof/profile
DUMP:=curl -s "http://localhost:6060/debug/pprof/goroutine?debug=1"
DSTAT:=dstat -tlnr --top-cpu --top-mem --top-io --top-bio

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

.PHONY: dev
dev: build
	cd $(BUILD_DIR); \
	./$(BIN_NAME)

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

.PHONY: commit
pull:
	cd $(PROJECT_ROOT); \
	git pull origin main

.PHONY: before
before:
	# backup logs
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	@if [ -f $(NGX_LOG) ]; then \
		sudo mv -f $(NGX_LOG) ~/logs/$(when)/ ; \
	fi
	@if [ -f $(MYSQL_LOG) ]; then \
		sudo mv -f $(MYSQL_LOG) ~/logs/$(when)/ ; \
	fi
	# backup configs
	mkdir -p ~/config/$(when)
	sudo mv -f $(NGX_CFG) ~/config/$(when)/ ; \
	sudo mv -f $(MYSQL_CFG) ~/config/$(when)/ ; \
	# set configs
	cd $(PROJECT_ROOT); \
	sudo cp nginx.conf $(NGX_CFG);\
	sudo cp sql.conf $(MYSQL_CFG)
	# restart
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

.PHONY: fgprof
fgprof:
	$(FGPROF)
	$(SLACKRAW) $(FGPROF_CHAN) -n fgprof.png ./fgprof.png

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

.make.env:
	wget https://raw.githubusercontent.com/mazrean/ISUCON-Tools/main/.make.env.template -O .make.env

.PHONY: setup
setup: .make.env apt-setup git-setup config-setup repository-setup ssh-setup tools-setup

.PHONY: set
set: .make.env apt-setup git-setup repository-backup repository-clone ssh-setup tools-setup

.PHONY: apt-setup
apt-setup:
	sudo apt update
	sudo apt install -y git openssh-server
	sudo apt upgrade git openssh-server

.PHONY: git-setup
git-setup:
	git config --global user.email $(GIT_MAIL)
	git config --global user.name $(GIT_NAME)
	ssh-keygen -t ed25519 -C $(GIT_MAIL)
	cat ~/.ssh/id_ed25519.pub
	# 公開鍵をgithubに登録するのを待機
	read hoge

.PHONY: repository-setup
repository-setup:
	cd $(PROJECT_ROOT);\
	git init;\
	git commit --allow-empty -m "initial commit";\
	git remote add origin $(GIT_REPO);\
	git branch -M main;\
	git add .;\
	git commit -m "init";\
	git push origin main

.PHONY: repository-backup
repository-backup:
	-mkdir ~/project-backup
	mv $(PROJECT_ROOT) ~/project-backup/
	cp -rn ~/project-backup/ $(PROJECT_ROOT)

.PHONY: repository-clone
repository-clone:
	git clone $(GIT_REPO) $(PROJECT_ROOT)

.PHONY: ssh-setup
ssh-setup:
	members="$(MEMBER_GITHUB)";\
	for member in $$members; do\
		curl https://github.com/$$member.keys >> ~/.ssh/authorized_keys;\
	done

.PHONY: config-setup
config-setup:
	cd $(PROJECT_ROOT);\
	cp $(NGX_CFG) ./nginx.conf;\
	cp $(MYSQL_CFG) ./sql.conf

.PHONY: tools-setup
tools-setup:
	# apt tools
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat unzip graphviz gv htop
	# kataribe
	wget https://github.com/matsuu/kataribe/releases/download/v0.4.1/kataribe-v0.4.1_linux_amd64.zip -O kataribe.zip
	unzip -o kataribe.zip
	sudo mv kataribe /usr/local/bin/
	sudo chmod +x /usr/local/bin/kataribe
	rm kataribe.zip
	kataribe -generate
	# myprofiler
	wget https://github.com/KLab/myprofiler/releases/download/0.2/myprofiler.linux_amd64.tar.gz
	tar -xf myprofiler.linux_amd64.tar.gz
	rm myprofiler.linux_amd64.tar.gz
	sudo mv myprofiler /usr/local/bin/
	sudo chmod +x /usr/local/bin/myprofiler
	# netdata
	bash <(curl -Ss https://my-netdata.io/kickstart.sh)
	sudo systemctl start netdata
	# slackcat
	wget https://github.com/bcicen/slackcat/releases/download/1.7.2/slackcat-1.7.2-linux-amd64 -O slackcat
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
	slackcat --configure
