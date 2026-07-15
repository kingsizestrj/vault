.PHONY: build test all clean install run

BINARY := sshvault
# A git tag (e.g. v1.0.0) drives the version; with no tags at all, fall back to
# the baked-in default so `make build` reproduces the shipped binary's version.
VERSION := $(shell git describe --tags 2>/dev/null || echo "1.0.0")
LDFLAGS := -ldflags="-s -w -X main.version=$(VERSION)"

build:
	go build $(LDFLAGS) -o $(BINARY) .

test:
	go test ./internal/... -v

all: clean
	@mkdir -p dist
	GOOS=linux   GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-amd64        .
	GOOS=linux   GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-arm64        .
	GOOS=darwin  GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-darwin-amd64       .
	GOOS=darwin  GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-darwin-arm64       .
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-windows-amd64.exe  .
	@echo "built:"
	@ls -la dist/

run: build
	./$(BINARY)

clean:
	rm -rf $(BINARY) dist/
