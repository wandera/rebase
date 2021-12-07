#!/bin/bash

set -e

PR_NUMBER=$(jq -r ".pull_request.number" "$GITHUB_EVENT_PATH")
if [[ "$PR_NUMBER" == "null" ]]; then
  PR_NUMBER=$(jq -r ".issue.number" "$GITHUB_EVENT_PATH")
fi
if [[ "$PR_NUMBER" == "null" ]]; then
  echo "Failed to determine PR Number."
  exit 1
fi
echo "Collecting information about PR #$PR_NUMBER of $GITHUB_REPOSITORY..."

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi

URI=https://api.github.com
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

catch() {
  if [ "$1" != "0" ]; then
    echo "Sending error message to PR."
    RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
    MESSAGE="Automatic Rebase/Autosquash action failed - details are [here]($RUN_URL)."
    curl -s -H "${AUTH_HEADER}" -X POST -d "{\"body\": \"$MESSAGE\"}" \
      "$URI/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments"
  fi
}

trap 'catch $?' EXIT

pr_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" \
  "${URI}/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")

BASE_REPO=$(echo "$pr_resp" | jq -r .base.repo.full_name)
BASE_BRANCH=$(echo "$pr_resp" | jq -r .base.ref)

USER_LOGIN=$(jq -r ".comment.user.login" "$GITHUB_EVENT_PATH")

COMMAND=$(jq -r ".comment.body" "$GITHUB_EVENT_PATH")
echo "GitHub command is '$COMMAND'"

user_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" \
  "${URI}/users/${USER_LOGIN}")

USER_NAME=$(echo "$user_resp" | jq -r ".name")
if [[ "$USER_NAME" == "null" ]]; then
  USER_NAME=$USER_LOGIN
fi
USER_NAME="${USER_NAME} (Rebase PR Action)"

USER_EMAIL=$(echo "$user_resp" | jq -r ".email")
if [[ "$USER_EMAIL" == "null" ]]; then
  USER_EMAIL="$USER_LOGIN@users.noreply.github.com"
fi

if [[ "$(echo "$pr_resp" | jq -r .rebaseable)" != "true" ]]; then
  echo "GitHub doesn't think that the PR is rebaseable!"
  echo "API response: $pr_resp"
  exit 1
fi

if [[ -z "$BASE_BRANCH" ]]; then
  echo "Cannot get base branch information for PR #$PR_NUMBER!"
  echo "API response: $pr_resp"
  exit 1
fi

HEAD_REPO=$(echo "$pr_resp" | jq -r .head.repo.full_name)
HEAD_BRANCH=$(echo "$pr_resp" | jq -r .head.ref)

echo "Base branch for PR #$PR_NUMBER is $BASE_BRANCH"

USER_TOKEN=${USER_LOGIN//-/_}_TOKEN
UNTRIMMED_COMMITTER_TOKEN=${!USER_TOKEN:-$GITHUB_TOKEN}
COMMITTER_TOKEN="$(echo -e "${UNTRIMMED_COMMITTER_TOKEN}" | tr -d '[:space:]')"

git remote set-url origin https://x-access-token:$COMMITTER_TOKEN@github.com/$GITHUB_REPOSITORY.git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

git remote add fork https://x-access-token:$COMMITTER_TOKEN@github.com/$HEAD_REPO.git

set -o xtrace

# make sure branches are up-to-date
git fetch origin $BASE_BRANCH
git fetch fork $HEAD_BRANCH

if [[ $COMMAND == "/rebase+" ]]; then
  # do the rebase + autosquash
  git checkout -b $HEAD_BRANCH fork/$HEAD_BRANCH
  GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash --empty=drop origin/$BASE_BRANCH
elif [[ $COMMAND == "/autosquash" ]]; then
  # do the autosquash
  git checkout -b $HEAD_BRANCH fork/$HEAD_BRANCH
  ANCESTOR=$(git merge-base origin/$BASE_BRANCH fork/$HEAD_BRANCH)
  GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash --empty=drop $ANCESTOR
else
  # do the rebase
  git checkout -b $HEAD_BRANCH fork/$HEAD_BRANCH
  git rebase --empty=drop origin/$BASE_BRANCH
fi
# push back
git push --force-with-lease fork $HEAD_BRANCH
