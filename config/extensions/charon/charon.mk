ifndef CHARON_MK
CHARON_MK := 1

PYTHON ?= python3
CHARON := $(dir $(lastword $(MAKEFILE_LIST)))charon.py
PORT_ROOT := $(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))

CHECKS ?=
VARIANT ?=
FORCE ?=
ARGS ?=

FERRY := $(PYTHON) $(CHARON) --root $(PORT_ROOT) \
	$(if $(VARIANT),--variant $(VARIANT)) $(if $(FORCE),--force)
GATES := $(foreach check,$(CHECKS),--check $(check))

.DEFAULT_GOAL := help
.PHONY: help build package deploy run test integrate clean setup provenance device

help:
	@$(FERRY) help

build:
	@$(FERRY) build $(ARGS)

package:
	@$(FERRY) package $(ARGS)

deploy:
	@$(FERRY) deploy $(ARGS)

run:
	@$(FERRY) run $(ARGS)

test:
	@$(FERRY) test $(ARGS)

integrate:
	@$(FERRY) integrate $(GATES) $(ARGS)

clean:
	@$(FERRY) clean $(ARGS)

setup:
	@$(FERRY) setup $(ARGS)

device:
	@$(FERRY) device $(ARGS)

provenance:
	@$(FERRY) provenance

endif
