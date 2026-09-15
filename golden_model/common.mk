# Shared build logic for every golden_model/<module>/Makefile. A per-module Makefile only
# declares MODULE_NAME, MAIN (optional) and SRC (the module's own sources plus the Common/*
# files it needs), then does `include ../common.mk`. Callers (run_SIM.sh, run_NISTTest.sh) keep
# overriding MODULE_NAME/MAIN/TARGET_DIR/TARGET_NAME on the `make` command line exactly as
# before -- this file only removes the duplicated flags/target-building boilerplate.

CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -pedantic
LDFLAGS = -lcryptopp

TARGET_DIR ?= ../executables
TARGET_NAME ?= goldenModel_$(MODULE_NAME)
TARGET = $(TARGET_DIR)/$(TARGET_NAME)

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p $(TARGET_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)
