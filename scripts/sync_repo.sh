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

SOURCE_REPO_NAME=$(basename $SOURCE_REPO)

echo "Reading sync metadata..."

LAST_SYNCED=$(jq -r \
  --arg repo "$SOURCE_REPO_NAME" \
  '.[$repo] // empty' \
  $GITHUB_WORKSPACE/sync-state/last-synced.json)

if [ -z "$LAST_SYNCED" ]; then
    echo "No previous sync found"
    echo "Performing initial full sync"

    COMMITS=$(git log source/main --reverse --pretty=format:"%H")
else
    echo "Last synced commit: $LAST_SYNCED"
    echo "Performing incremental sync"

    COMMITS=$(git log ${LAST_SYNCED}..source/main --reverse --pretty=format:"%H")
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

    git cherry-pick --no-commit $COMMIT
    
    COMMIT_MESSAGE=$(git log -1 --format=%B $COMMIT)
    
    git commit \
      --author="${GIT_USER_NAME} <${GIT_USER_EMAIL}>" \
      -m "$COMMIT_MESSAGE"
    
    echo "Cherry-pick completed"
done

LAST_COMMIT=$(echo "$COMMITS" | tail -n 1)

echo "Updating sync metadata..."

echo "$LAST_COMMIT" > .sync_last_commit

git add .sync_last_commit

git commit -m "update sync metadata"

echo "Pushing changes..."

git push origin main

echo "========================================"
echo "Repo sync completed successfully"
echo "========================================"
