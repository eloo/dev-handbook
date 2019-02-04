# Golang Makefile
# Please do not alter this alter this directly
GOLANG_MK_VERSION := 28

GO_ENVS := GO111MODULE=on

GO ?= $(GO_ENVS) go

GOFILES := $(shell find . -name "*.go" -type f ! -path "./vendor/*")
GOFMT ?= gofmt -s

GOFLAGS := -i -v
EXTRA_GOFLAGS ?=
EXTRA_RELEASE_GOFLAGS ?= -gcflags "all=-trimpath=$(GOPATH)"

MKDIR_P = mkdir -p

# Defaults for directory
# Can be modified by setting it before loading this file
ifndef DIST_DIR
	DIST_DIR := dist
endif
ifndef BUILD_DIR
	BUILD_DIR := bin
endif
# Defaults for build release artifacts
# Can be modified by setting it before loading this file
ifndef GOLANG_RELEASE_OS
  GOLANG_RELEASE_OS=linux windows darwin
endif
ifndef GOLANG_RELEASE_ARCH
  GOLANG_RELEASE_ARCH=386 amd64 arm arm64
endif
ifndef GOLANG_RELEASE_OSARCH
  GOLANG_RELEASE_OSARCH=!darwin/arm !darwin/arm64
endif

LDFLAGS := -X "main.SemVer=${VERSION}" -X "main.GitCommit=$(shell git describe --tags --always | sed 's/-/+/' | sed 's/^v//')" -X "main.Tags=$(TAGS)"

RELEASE_LD_FLAGS := -s -w

PACKAGES ?= $(shell $(GO) list ./... | grep -v /vendor/)

.PHONY: golang-directories
golang-directories: ## Creates necessary directories for golang.mk
	$(MKDIR_P) $(BUILD_DIR)

.PHONY: golang-tools
golang-tools: ## Install/Update used golang tools
	$(GO) get -u github.com/kisielk/errcheck
	$(GO) get -u github.com/golang/lint/golint
	$(GO) get -u github.com/client9/misspell/cmd/misspell
	$(GO) get -u github.com/wadey/gocovmerge
	$(GO) get -u github.com/mitchellh/gox
	cd $GOPATH && curl -L https://git.io/vp6lP | sh && cd -

.PHONY: golang-clean
golang-clean: ## Cleanup go files
	$(GO) clean -i ./...
	rm -rf $(EXECUTABLE) $(DIST_DIR) $(BUILD_DIR)

.PHONY: golang-tidy
golang-tidy: ## Run go mod tidy
	$(GO) mod tidy

.PHONY: golang-update-deps
golang-update-deps: ## Update dependencies using go mod
	$(GO) get -u

.PHONY: golang-fmt
golang-fmt: ## Format go code
	$(GOFMT) -w $(GOFILES)

.PHONY: golang-vet
golang-vet: ## Vet the go files
	$(GO) vet $(PACKAGES)

.PHONY: golang-errcheck
golang-errcheck: ## Run errcheck
	@hash errcheck > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/kisielk/errcheck; \
	fi
	$(GO_ENVS) errcheck $(PACKAGES)

.PHONY: golang-lint
golang-lint: ## Lint go files using gometalinter
	@hash gometalinter > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		echo "You maybe should run 'make golang-tools'"; \
	fi
	$(GO_ENVS) gometalinter ./...

.PHONY: golang-misspell-check
golang-misspell-check: ## Run misspell
	@hash misspell > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/client9/misspell/cmd/misspell; \
	fi
	misspell -error -i unknwon $(GOFILES)

.PHONY: golang-misspell
golang-misspell: ## Run misspell without breaking the build
	@hash misspell > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/client9/misspell/cmd/misspell; \
	fi
	misspell -w -i unknwon $(GOFILES)

.PHONY: golang-fmt-check
golang-fmt-check: ## Format go and fail if not formatted
	# get all go files and run go fmt on them
	@diff=$$($(GOFMT) -d $(GOFILES)); \
	if [ -n "$$diff" ]; then \
		echo "Please run 'make golang-fmt' and commit the result:"; \
		echo "$${diff}"; \
		exit 1; \
	fi;

.PHONY: golang-test
golang-test: golang-fmt ## Test go files
	$(GO) test $(PACKAGES)

.PHONY: golang-coverage
golang-coverage: golang-directories ## Runs tests with coverage
	$(GO) test -covermode=count -coverprofile $(BUILD_DIR)/coverage.out $(PACKAGES)

.PHONY: golang-coverage-report
golang-coverage-report: golang-coverage ## Creates an html report for the code coverage
	@hash gocovmerge > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/wadey/gocovmerge; \
	fi
	gocovmerge $(shell find . -type f -name "coverage.out") > $(BUILD_DIR)/coverage.all
	$(GO) tool cover -html=$(BUILD_DIR)/coverage.all -o $(BUILD_DIR)/coverage.html

.PHONY: golang-install
golang-install: $(wildcard *.go) ## Run go install
	$(GO) install -v -tags '$(TAGS)' -ldflags '-s -w $(LDFLAGS)'

.PHONY: golang-build
golang-build: golang-test ## Build the binary
	$(GO) build $(GOFLAGS) $(EXTRA_GOFLAGS) -tags '$(TAGS)' -ldflags '-s -w $(LDFLAGS) -X main.SemVer=${VERSION}-snapshot' -o "$(BUILD_DIR)/$(EXECUTABLE)"

.PHONY: golang-name
golang-release-name: ## Print predicated binary release name
	@echo "$(EXECUTABLE)-$(VERSION)"

.PHONY: golang-release
golang-release: golang-release-build golang-release-checksums ## Trigger release-build and release-check

.PHONY: golang-release-build
golang-release-build: golang-test ## Build release binaries
	@hash gox > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		$(GO) get -u github.com/mitchellh/gox; \
	fi
	$(GO_ENVS) gox -os "${GOLANG_RELEASE_OS}" -arch="${GOLANG_RELEASE_ARCH}" -osarch="${GOLANG_RELEASE_OSARCH}" $(EXTRA_GOFLAGS) $(EXTRA_RELEASE_GOFLAGS) -ldflags '$(RELEASE_LD_FLAGS) $(LDFLAGS)' -output "$(DIST_DIR)/$(EXECUTABLE)-$(VERSION)_{{.OS}}_{{.Arch}}"

.PHONY: golang-release-checksums
golang-release-checksums: ## Create sha256 sums
	@hash sha256sum > /dev/null 2>&1; if [ $$? -ne 0 ]; then \
		echo "Warning: sha256sum not found"; \
	else \
		cd $(DIST_DIR); $(foreach file,$(filter-out $(wildcard $(DIST_DIR)/*.sha256), $(wildcard $(DIST_DIR)/*)),sha256sum $(notdir $(file)) > $(notdir $(file)).sha256;) \
	fi

.PHONY: golang-download-makefile
golang-download-makefile:
	wget https://raw.githubusercontent.com/eloo/dev-handbook/master/make/golang.mk -O /tmp/golang.mk 2>/dev/null

.PHONY: golang-update-makefile
golang-update-makefile: golang-download-makefile ## Update the golang.mk
	@if [ $(shell cat /tmp/golang.mk | grep GOLANG_MK_VERSION -m1 | cut -d" " -f3) -gt $(GOLANG_MK_VERSION) ] ; then \
         cp /tmp/golang.mk golang.mk;\
		 echo "golang.mk updated";\
	else \
		echo "golang.mk is up-to-date"; \
    fi
	@rm /tmp/golang.mk || true

golang-todo: ## Display TODO and FIXME items in the source code.
	@! ag --ignore golang.mk --ignore-dir vendor --ignore-dir runtime TODO
	@! ag --ignore golang.mk --ignore-dir vendor --ignore-dir runtime XXX
	@! ag --ignore golang.mk --ignore-dir vendor --ignore-dir runtime FIXME
	@! ag --ignore golang.mk --ignore-dir vendor --ignore-dir runtime "FIX ME"
