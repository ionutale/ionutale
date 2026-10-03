#!/usr/bin/env bash
# Computes the last-30-days stats block for the profile README.
#
# Requires: gh (authenticated) and jq. Includes private-repo activity when
# the token can see it (a personal STATS_TOKEN secret); falls back to public
# activity with the default GITHUB_TOKEN.
#
# Usage: bash scripts/profile-stats.sh > /tmp/stats-block.md

set -euo pipefail

USER="${STATS_USER:-ionutale}"
DAYS="${STATS_DAYS:-30}"
CAP="${STATS_COMMIT_CAP:-300}"

if date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  FROM=$(date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ)
else
  FROM=$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)
fi
TO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

QUERY='query($login: String!, $from: DateTime!, $to: DateTime!) {
  user(login: $login) {
    contributionsCollection(from: $from, to: $to) {
      totalCommitContributions
      totalPullRequestContributions
      totalRepositoriesWithContributedCommits
      commitContributionsByRepository(maxRepositories: 100) {
        repository { nameWithOwner }
      }
    }
  }
}'

RESULT=$(gh api graphql -f query="$QUERY" -f login="$USER" -f from="$FROM" -f to="$TO")

COMMITS=$(echo "$RESULT" | jq '.data.user.contributionsCollection.totalCommitContributions')
PRS=$(echo "$RESULT" | jq '.data.user.contributionsCollection.totalPullRequestContributions')
PROJECTS=$(echo "$RESULT" | jq '.data.user.contributionsCollection.totalRepositoriesWithContributedCommits')

ADDITIONS=0
DELETIONS=0
COUNT=0
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  shas=$(gh api "repos/$repo/commits?author=$USER&since=$FROM&per_page=100" --paginate --jq '.[].sha' 2>/dev/null || true)
  for sha in $shas; do
    stats=$(gh api "repos/$repo/commits/$sha" --jq '"\(.stats.additions) \(.stats.deletions)"' 2>/dev/null || echo "0 0")
    additions=${stats% *}
    deletions=${stats#* }
    ADDITIONS=$((ADDITIONS + ${additions:-0}))
    DELETIONS=$((DELETIONS + ${deletions:-0}))
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$CAP" ]; then
      break 2
    fi
  done
done < <(echo "$RESULT" | jq -r '.data.user.contributionsCollection.commitContributionsByRepository[].repository.nameWithOwner')

format() {
  if printf "%'d" "$1" >/dev/null 2>&1; then
    printf "%'d" "$1"
  else
    printf "%d" "$1"
  fi
}

cat <<EOF
| Commits | Lines changed | Pull requests | Projects |
| :---: | :---: | :---: | :---: |
| **$(format "$COMMITS")** | **+$(format "$ADDITIONS")** / −$(format "$DELETIONS") | **$(format "$PRS")** | **$(format "$PROJECTS")** |

<sub>Commits, lines, pull requests, and distinct projects over the last ${DAYS} days — refreshed daily by [this workflow](../actions/workflows/profile-stats.yml).</sub>
EOF
