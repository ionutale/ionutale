#!/usr/bin/env bash
# Computes the last-30-days stats and writes stats.json for the profile
# badges (raw.githubusercontent.com/ionutale/ionutale/main/stats.json).
#
# Requires: gh (authenticated) and jq. Includes private-repo activity when
# the token can see it — the workflow only runs with a personal STATS_TOKEN
# so public-only numbers never overwrite the real ones.
#
# Usage: bash scripts/profile-stats.sh [output.json]

set -euo pipefail

USER="${STATS_USER:-ionutale}"
DAYS="${STATS_DAYS:-30}"
CAP="${STATS_COMMIT_CAP:-300}"
OUTPUT="${1:-stats.json}"

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

group() { # 1234567 -> 1,234,567
  local rest="$1" out=""
  while [ "${#rest}" -gt 3 ]; do
    out=",${rest: -3}$out"
    rest="${rest:0:${#rest}-3}"
  done
  printf "%s%s" "$rest" "$out"
}

cat > "$OUTPUT" <<EOF
{
  "updated": "$TO",
  "days": $DAYS,
  "commits": $COMMITS,
  "commits_display": "$(group "$COMMITS")",
  "lines_added": $ADDITIONS,
  "lines_added_display": "+$(group "$ADDITIONS")",
  "lines_removed": $DELETIONS,
  "lines_removed_display": "-$(group "$DELETIONS")",
  "pull_requests": $PRS,
  "pull_requests_display": "$(group "$PRS")",
  "projects": $PROJECTS,
  "projects_display": "$(group "$PROJECTS")"
}
EOF

echo "wrote $OUTPUT — $(group "$COMMITS") commits, +$(group "$ADDITIONS")/-$(group "$DELETIONS") lines, $(group "$PRS") PRs, $(group "$PROJECTS") projects"
