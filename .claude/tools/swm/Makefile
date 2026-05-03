BIN := swm
PREFIX := $(HOME)/.local/bin

.PHONY: build install uninstall clean init

build:
	go build -o $(BIN) .

install: build
	mkdir -p $(PREFIX)
	cp $(BIN) $(PREFIX)/$(BIN)
	@echo "$(PREFIX)/$(BIN) にインストールしました"

uninstall:
	rm -f $(PREFIX)/$(BIN)
	@echo "アンインストールしました"

clean:
	rm -f $(BIN)

init: install
	$(BIN) init
	@echo ""
	@echo "以下を ~/.bashrc または ~/.zshrc に追加してください:"
	@echo '  eval "$$(swm env)"'
