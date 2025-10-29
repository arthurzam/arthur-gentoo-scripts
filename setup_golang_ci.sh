#!/bin/bash

source /lib/gentoo/functions.sh || :

die() {
	eerror "$@"
	exit 1
}

read -p "enter repo remote path: " repo_path
read -p "run every # hours: " hours
read -p "tag-filter (optional): " tag_filter

repo_name=${repo_path##*/}
repo_name=${repo_name%.git}

if [[ -d /tmp/${repo_name} ]]; then
	ewarn "clone already exists"
	cd /tmp/${repo_name}
elif [[ ${repo_path} == github.com/*/* ]]; then
	einfo "forking into /tmp/${repo_name}"
	cd /tmp
	gh repo fork --org gentoo-golang-dist --clone "${repo_path#github.com/}" || die "failed forking"
	cd "${repo_name}" || die "failed cd"
else
	einfo "cloning into /tmp/${repo_name}"
	cd /tmp
	git clone "git@github.com:gentoo-golang-dist/${repo_name}.git" || die "failed cloning"
	cd "${repo_name}" || die "failed cd"
fi

if [[ ${repo_path} == github.com/*/* ]]; then
	unset repo_path
fi

einfo "creating orphan branch"
git checkout --orphan golang-dist || die "failed creating orphan branch"
git reset --hard || die "failed reset"
mkdir -p .github/workflows || die "failed creating dir"

einfo "creating workflow"
cat > .github/workflows/mirror.yml <<-EOF || die "failed creating workflow"
  name: Sync with upstream
  on:
    push:
    schedule:
      - cron: "$((RANDOM % 60)) */${hours} * * *"
    workflow_dispatch:

  jobs:
    sync-mirror:
      runs-on: ubuntu-latest
      permissions:
        contents: write
      steps:
        - name: Update mirror
          uses: projg2/golang-dist-mirror-action@v1
          with:
            token: \${{ secrets.PUSH_TOKEN }}
            ${tag_filter:+tag-filter: ${tag_filter}}
            ${repo_path:+upstream-repo: ${repo_path}}
EOF
git add .github/workflows/mirror.yml || die "failed adding workflow"

einfo "committing"
git commit -m "add mirror workflow" --signoff --gpg-sign || die "failed committing"

ewarn "repo tags are:"
git --no-pager tag --list --column=auto
echo
read -p "enter tags to delete: " tags
git push origin --delete ${tags} || die "failed deleting tags"

einfo "pushing new branch"
git push -u origin golang-dist || die "failed pushing"

einfo "setting default branch to 'golang-dist'"
gh repo edit "gentoo-golang-dist/${repo_name}" --default-branch golang-dist || die "failed setting default branch"
