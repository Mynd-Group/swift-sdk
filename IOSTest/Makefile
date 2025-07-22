# iOS App Build Commands
# Usage: make <target>

# Project configuration
PROJECT_NAME = IOSTest
SCHEME = IOSTest
DESTINATION = 'platform=iOS Simulator,name=iPhone 16'

# Default target
.PHONY: help
help:
	@echo "Available commands:"
	@echo "  build          - Build the iOS app"
	@echo "  clean          - Clean build artifacts"
	@echo "  deep-clean     - Clean build artifacts + caches"
	@echo "  resolve        - Resolve package dependencies"
	@echo "  list           - List project targets and schemes"
	@echo "  rebuild        - Clean then build"
	@echo "  reset          - Deep clean then resolve and build"

# Build the app
.PHONY: build
build:
	@echo "Building iOS app..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		build

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	xcodebuild clean -project $(PROJECT_NAME).xcodeproj

# Deep clean - remove caches and derived data
.PHONY: deep-clean
deep-clean: clean
	@echo "Removing Xcode and Swift PM caches..."
	rm -rf ~/Library/Developer/Xcode/DerivedData
	rm -rf ~/Library/Caches/org.swift.swiftpm
	rm -rf .build

# Resolve package dependencies
.PHONY: resolve
resolve:
	@echo "Resolving package dependencies..."
	xcodebuild -resolvePackageDependencies -project $(PROJECT_NAME).xcodeproj

# List project information
.PHONY: list
list:
	@echo "Project information:"
	xcodebuild -project $(PROJECT_NAME).xcodeproj -list

# Rebuild (clean + build)
.PHONY: rebuild
rebuild: clean build

# Reset (deep clean + resolve + build)
.PHONY: reset
reset: deep-clean resolve build

# Quick test build (without verbose output)
.PHONY: test-build
test-build:
	@echo "Quick test build..."
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-destination $(DESTINATION) \
		build 2>&1 | grep -E "(error|warning|BUILD)" || echo "Build completed"