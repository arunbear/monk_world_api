# Get version from MonkWorld::API
VERSION := $(shell perl -Ilib -MMonkWorld::API -E 'say $$MonkWorld::API::VERSION')
# Docker image configuration (DOCKER_USER must be set in environment)
DOCKER_USER ?= $(error Please set DOCKER_USER environment variable with your Docker Hub username)
DOCKER_IMAGE ?= ${DOCKER_USER}/monkworld-api-deps

.PHONY: build-deps push-deps help

# Build the dependencies image with exact version
build-deps:
	docker build \
		--build-arg APP_VERSION=$(VERSION) \
		-t $(DOCKER_IMAGE):$(VERSION) \
		-f Dockerfile.deps .

# Build and push the exact version to the container registry
push-deps: build-deps
	@echo "Pushing $(DOCKER_IMAGE):$(VERSION)"
	docker push $(DOCKER_IMAGE):$(VERSION)

# Show this help
help:
	@echo "Available targets:"
	@echo "  build-deps   Build the dependencies image with exact version"
	@echo "  push-deps    Push the exact version to the container registry"
	@echo "  help         Show this help message"

.DEFAULT_GOAL := help
