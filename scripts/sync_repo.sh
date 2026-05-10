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

echo "========================================"
echo "Checking target repo existence..."
echo "========================================"

TARGET_REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/repos/${TARGET_REPO})

if [ "$TARGET_REPO_CHECK" = "404" ]; then

    echo "Target repo does not exist"
    echo "Creating target repo..."

    TARGET_REPO_NAME=$(basename $TARGET_REPO)

    curl -s -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/user/repos \
      -d "{
        \"name\":\"${TARGET_REPO_NAME}\",
        \"private\":false
      }"

    echo ""
    echo "Waiting for repo creation..."

    sleep 5

else

    echo "Target repo already exists"

fi

echo "Cloning target repo..."

git clone \
  https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_REPO}.git \
  target

cd target

echo "Adding source remote..."

git remote add source \
  https://x-access-token:${GITHUB_TOKEN}@github.com/${SOURCE_REPO}.git

echo "Fetching origin..."

git fetch origin || true

echo "Fetching source..."

git fetch source

SOURCE_REPO_NAME=$(basename $SOURCE_REPO)
TARGET_REPO_NAME=$(basename $TARGET_REPO)

echo "========================================"
echo "Updating repo mappings..."
echo "========================================"

MAPPINGS_FILE="$GITHUB_WORKSPACE/sync-state/mappings.json"

SOURCE_EXISTS=$(jq -r \
  --arg repo "$SOURCE_REPO_NAME" \
  'has($repo)' \
  $MAPPINGS_FILE)

if [ "$SOURCE_EXISTS" = "true" ]; then

    echo "Source repo mapping exists"

    TARGET_EXISTS=$(jq -r \
      --arg repo "$SOURCE_REPO_NAME" \
      --arg target "$TARGET_REPO_NAME" \
      '.[$repo] | index($target)' \
      $MAPPINGS_FILE)

    if [ "$TARGET_EXISTS" = "null" ]; then

        echo "Adding new target mapping"

        TMP_FILE=$(mktemp)

        jq \
          --arg repo "$SOURCE_REPO_NAME" \
          --arg target "$TARGET_REPO_NAME" \
          '.[$repo] += [$target]' \
          $MAPPINGS_FILE \
          > $TMP_FILE

        mv $TMP_FILE $MAPPINGS_FILE

    else

        echo "Target mapping already exists"

    fi

else

    echo "Creating new source repo mapping"

    TMP_FILE=$(mktemp)

    jq \
      --arg repo "$SOURCE_REPO_NAME" \
      --arg target "$TARGET_REPO_NAME" \
      '. + {($repo): [$target]}' \
      $MAPPINGS_FILE \
      > $TMP_FILE

    mv $TMP_FILE $MAPPINGS_FILE

fi

echo "========================================"
echo "Finding new commits..."
echo "========================================"

LAST_SYNCED=$(jq -r \
  --arg repo "$SOURCE_REPO_NAME" \
  --arg target "$TARGET_REPO_NAME" \
  '.[$repo][$target] // empty' \
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

if [ -z "$COMMITS" ]; then

    echo "No new commits to sync"
    exit 0

fi

echo "========================================"
echo "Commits to replay:"
echo "========================================"

echo "$COMMITS"

echo "========================================"
echo "Configuring git identity..."
echo "========================================"

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

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

echo "========================================"
echo "Updating centralized sync metadata..."
echo "========================================"

TMP_FILE=$(mktemp)

jq \
  --arg repo "$SOURCE_REPO_NAME" \
  --arg target "$TARGET_REPO_NAME" \
  --arg commit "$LAST_COMMIT" \
  '.[$repo][$target]=$commit' \
  $GITHUB_WORKSPACE/sync-state/last-synced.json \
  > $TMP_FILE

mv $TMP_FILE \
  $GITHUB_WORKSPACE/sync-state/last-synced.json

echo "========================================"
echo "Pushing target repo changes..."
echo "========================================"

git push origin main

echo "========================================"
echo "Repo sync completed successfully"
echo "========================================"
