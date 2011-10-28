R14_DIR = $(HOME)/util/erlang/dist/r14b3/bin

EXT_MOD = ../amqp_client
EXT_MOD_INCLUDES = $(EXT_MOD:%=%/include)
INCLUDE_DIR = include
INCLUDE_DIR += $(EXT_MOD_INCLUDES)

# for proper
INCLUDE_DIR += ..
INCLUDE_DIR += ../proper/include
PROPER_BIN = ../proper/ebin
PROPER_OPTS = -DPROPER

DUP_TEST = -DDUP_TEST
INCLUDES = $(INCLUDE_DIR:%=-I%)
SRC_DIR = src
EBIN_DIR := ebin
ERLC_OPTS = +debug_info -DTEST $(DUP_TEST) $(PROPER_OPTS) -pa $(PROPER_BIN)
ERLC := $(R14_DIR)/erlc $(ERLC_OPTS)

all: $(EBIN_DIR)
	$(ERLC) -W $(INCLUDES) -o $(EBIN_DIR) $(SRC_DIR)/*.erl
	cp $(SRC_DIR)/ecomet_server.app $(EBIN_DIR)
	
clean:
	@rm -rvf $(EBIN_DIR)/*

tags: etags ctags

ctags:
	cd $(SRC_DIR) ; ctags -R . ../include 

etags:
	cd $(SRC_DIR) ; etags -R . ../include 

$(EBIN_DIR) :
	( test -d $(EBIN_DIR) || mkdir -p $(EBIN_DIR) )

dia:
	PATH=$(R14_DIR):$(PATH) \
	dialyzer \
		$(INCLUDES) \
		--src \
		-r $(SRC_DIR)

.PHONY: tags ctags etags clean dia
