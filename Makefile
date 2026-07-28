# dir-walk development Makefile
# Parallelism is opt-in at runtime:
#   Fiber::ExecutionContext.default.resize(System.cpu_count)

CRYSTAL     ?= crystal
SRC_DIR     := src
SPEC_DIR    := spec
AMEBABIN    := ./bin/ameba

.PHONY: all spec format lint check clean docs

all: spec

# Run specs
spec:
	$(CRYSTAL) spec

# Run a single spec file
spec_file: F ?= spec/
spec_file:
	$(CRYSTAL) spec $(F)

# Format source code
format:
	$(CRYSTAL) tool format $(SRC_DIR) $(SPEC_DIR)

# Check formatting (CI gate)
format_check:
	$(CRYSTAL) tool format --check $(SRC_DIR) $(SPEC_DIR)

# Lint with ameba
lint:
	$(AMEBABIN) $(SRC_DIR) $(SPEC_DIR)

# Full quality gate
check: format_check lint spec

# Install dependencies
install:
	shards install
	$(CRYSTAL) build -o $(AMEBABIN) lib/ameba/src/cli.cr --no-debug

# Clean artifacts
clean:
	rm -rf .crystal-cache temp docs ~/.cache/crystal/crystal-run-*.tmp

# Generate API docs
docs:
	$(CRYSTAL) docs -o docs $(SRC_DIR)/dir-walk.cr

# Help
help:
	@echo "Targets:"
	@echo "  spec           Run all specs"
	@echo "  spec_file F=N  Run spec file or line"
	@echo "  format         Auto-format source"
	@echo "  format_check   Check formatting"
	@echo "  lint           Run ameba linter"
	@echo "  check          Run all quality gates"
	@echo "  install        Install dependencies"
	@echo "  clean          Remove artifacts"
	@echo "  docs           Generate API docs"
	@echo ""
	@echo "Flags: CRYSTAL  Crystal compiler path"
