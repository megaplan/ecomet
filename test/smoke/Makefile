INCLUDE_DIR = include
INCLUDES = $(INCLUDE_DIR:%=-I%)
SRC_DIR = src
EBIN_DIR := ebin
HTML_DOC_DIR = doc/html
ERLC_OPTS = +debug_info -DTEST
ERLC := erlc $(ERLC_OPTS)
VSN=0.3
APP_NAME=smoke_test
LICENSE=MIT

all: $(EBIN_DIR)
	$(ERLC) -W $(INCLUDES) -o $(EBIN_DIR) $(SRC_DIR)/*.erl
	cp $(SRC_DIR)/smoke_test.app.src $(EBIN_DIR)/smoke_test.app

clean:
	@rm -rvf $(EBIN_DIR)/* $(HTML_DOC_DIR)

tags: ctags etags

ctags:
	cd $(SRC_DIR) ; ctags -R . ../include 

etags:
	cd $(SRC_DIR) ; etags -R . ../include 

$(EBIN_DIR) :
	( test -d $(EBIN_DIR) || mkdir -p $(EBIN_DIR) )

dia:
	dialyzer \
		$(INCLUDES) \
		--src \
		-r $(SRC_DIR)

doc:
	erl -noshell -run edoc_run application "'$(APP_NAME)'" \
		'"."' \
		'[{dir,"$(HTML_DOC_DIR)"},{new, true},{hidden, true},{private, true},{def,[{vsn,"$(VSN)"}, {license, "(License: $(LICENSE))"}]}]'

.PHONY: clean tags ctags etags dia doc
