#!/bin/bash

set -e

SOURCE_REPO=$1
TARGET_REPO=$2

echo "========================================"
echo "Starting repo sync"
echo "Source Repo: $SOURCE_REPO"
echo "Target Repo: $TARGET_REPO"
echo "========================================"

WORKDIR=$(mktemp -d)

echo "Created temp workdir: $WORKDIR"

cd $WORKDIR

echo "Cloning target repo..."

git clone \
  https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git \
  target

cd target

echo "Adding source remote..."

git remote add source \
  https://x-access-token:${GITHUB_TOKEN}@github.com/${SOURCE_REPO}.git

echo "Fetching origin..."
git fetch origin

echo "Fetching source..."
git fetch source

echo "Finding new commits..."

COMMITS=$(git log origin/main..source/main --reverse --pretty=format:"%H")

if [ -z "$COMMITS" ]; then
    echo "No new commits found."
    exit 0
fi

echo "Commits to replay:"
echo "$COMMITS"

echo "Configuring git identity..."

git config user.name "${GIT_USER_NAME}"
git config user.email "${GIT_USER_EMAIL}"

for COMMIT in $COMMITS
do
    echo "----------------------------------------"
    echo "Cherry-picking commit: $COMMIT"

    git cherry-pick --reset-author $COMMIT

    echo "Cherry-pick completed"
done

echo "Pushing changes..."

git push origin main

echo "========================================"
echo "Repo sync completed successfully"
echo "========================================"
