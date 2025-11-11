#!/bin/bash

# Vercel Deployment Script
# Handles Git operations, Flutter build, and Vercel deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi
}

# Function to check if Flutter is installed
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if Vercel CLI is installed
check_vercel() {
    if ! command -v vercel &> /dev/null; then
        print_error "Vercel CLI is not installed or not in PATH"
        print_error "Install with: npm i -g vercel"
        exit 1
    fi
}

# Function to generate commit message based on changes
generate_commit_message() {
    local modified_files=$(git diff --cached --name-only)
    local num_files=$(echo "$modified_files" | wc -l)
    
    if echo "$modified_files" | grep -q "lib/"; then
        echo "feat: update app functionality and UI"
    elif echo "$modified_files" | grep -q "pubspec.yaml"; then
        echo "deps: update dependencies"
    elif echo "$modified_files" | grep -q "web/"; then
        echo "web: update web configuration"
    elif echo "$modified_files" | grep -q "assets/"; then
        echo "assets: update app assets"
    elif echo "$modified_files" | grep -q "README.md\|\.md"; then
        echo "docs: update documentation"
    elif [ "$num_files" -eq 1 ]; then
        echo "update: $(basename $(echo "$modified_files" | head -1))"
    else
        echo "update: multiple files ($num_files files changed)"
    fi
}

# Function to handle Git operations
handle_git() {
    print_status "Checking Git status..."
    
    # Add all changes
    git add .
    
    # Check if there are any changes to commit
    if git diff --cached --quiet; then
        print_warning "No changes to commit"
        return 1
    fi
    
    # Show status
    print_status "Git status:"
    git status --short
    
    # Generate and show commit message
    local commit_msg=$(generate_commit_message)
    print_status "Generated commit message: '$commit_msg'"
    
    # Commit changes
    if git commit -m "$commit_msg"; then
        print_success "Changes committed successfully"
    else
        print_error "Failed to commit changes"
        exit 1
    fi
    
    # Push to remote
    print_status "Pushing to remote repository..."
    if git push; then
        print_success "Changes pushed successfully"
    else
        print_error "Failed to push changes"
        print_error "You may need to pull first: git pull"
        exit 1
    fi
    
    return 0
}

# Function to build Flutter app
build_flutter() {
    print_status "Building Flutter web app..."
    
    # Clean previous build
    if [ -d "build/web" ]; then
        print_status "Cleaning previous build..."
        rm -rf build/web
    fi
    
    # Build the app
    if flutter build web --release; then
        print_success "Flutter build completed successfully"
    else
        print_error "Flutter build failed"
        exit 1
    fi
    
    # Verify build output exists
    if [ ! -d "build/web" ]; then
        print_error "Build directory not found"
        exit 1
    fi
    
    print_status "Build output created in build/web"
}

# Function to deploy to Vercel
deploy_vercel() {
    print_status "Deploying to Vercel..."
    
    # Save current directory
    local original_dir=$(pwd)
    
    # Copy .vercel configuration if it exists in root
    if [ -d ".vercel" ] && [ -f ".vercel/project.json" ]; then
        print_status "Copying Vercel configuration to build directory..."
        cp -r .vercel build/web/
        print_success "Vercel configuration copied"
    fi
    
    # Navigate to build directory
    if ! cd build/web; then
        print_error "Failed to navigate to build/web directory"
        exit 1
    fi
    
    # Check if .vercel directory exists
    if [ ! -d ".vercel" ]; then
        print_warning "No .vercel configuration found"
        print_warning "You may need to run 'vercel link' first"
    fi
    
    # Deploy to production
    if vercel --prod; then
        print_success "Deployment completed successfully"
    else
        print_error "Vercel deployment failed"
        cd "$original_dir"
        exit 1
    fi
    
    # Return to original directory
    cd "$original_dir"
    print_status "Returned to project root"
}

# Function to show deployment summary
show_summary() {
    print_success "=== Deployment Summary ==="
    print_success "✓ Git changes committed and pushed"
    print_success "✓ Flutter web app built"
    print_success "✓ Deployed to Vercel"
    print_success "=========================="
}

# Main execution
main() {
    print_status "Starting deployment..."
    
    # Pre-flight checks
    check_git_repo
    check_flutter
    check_vercel
    
    # Handle Git operations
    if handle_git; then
        print_success "Git operations completed"
    else
        print_warning "No Git changes to process, proceeding with build and deployment..."
    fi
    
    # Build Flutter app
    build_flutter
    
    # Deploy to Vercel
    deploy_vercel
    
    # Show summary
    show_summary
    
    print_success "Deployment process completed successfully!"
}

# Trap to handle script interruption
trap 'print_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"