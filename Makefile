# Installation
INSTALL := install

# Files
SRC := tito-dev.sh
APP := tito
DIR := /usr/local/bin

# -----------------------------

# Nothing to be done
default: $(SRC)

.PHONY: test install

install: $(SRC)
	$(INSTALL) $(SRC) $(DIR)/$(APP)

test: $(SRC)
	bash $(SRC) < test/jobs.txt
