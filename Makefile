# Get version from MonkWorld::API
VERSION := $(shell perl -Ilib -MMonkWorld::API -E 'say $$MonkWorld::API::VERSION')

# Docker image configuration (DOCKER_USER must be set in environment)
DOCKER_USER ?= $(error Please set DOCKER_USER environment variable with your Docker Hub username)
DOCKER_IMAGE ?= ${DOCKER_USER}/monkworld-api-deps

RELEASE_BRANCH := release

.PHONY: build-deps push-deps help release

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

# Create a new release
release:
	@echo "Preparing release v$(VERSION)"
	@# Ensure we're on master
	@if [ "$$(git rev-parse --abbrev-ref HEAD)" != "master" ]; then \
		echo "Error: Must be on master branch to release"; \
		exit 1; \
	fi
	@# Check for uncommitted changes
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Working directory is not clean"; \
		git status; \
		exit 1; \
	fi
	@# Check if release branch exists
	@if ! git show-ref --verify --quiet refs/heads/$(RELEASE_BRANCH); then \
		echo "Creating new $(RELEASE_BRANCH) branch..."; \
		git checkout -b $(RELEASE_BRANCH); \
	else \
		echo "Updating $(RELEASE_BRANCH) branch..."; \
		git checkout $(RELEASE_BRANCH); \
		git merge --ff-only master; \
	fi
	@# Create and push tag
	@echo "Creating tag v$(VERSION)..."
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	@echo "Pushing to origin..."
	git push origin $(RELEASE_BRANCH)
	git push --tags
	@echo "Switching back to master branch..."
	git checkout master
	@echo "Release v$(VERSION) completed!"

# Show this help
help:
	@echo "Available targets:"
	@echo "  build-deps   Build the dependencies image with exact version"
	@echo "  push-deps    Push the exact version to the container registry"
	@echo "  release      Create a new release (merge master to release, tag, and push - assumes local is up to date)"
	@echo "  help         Show this help message"

.DEFAULT_GOAL := help
