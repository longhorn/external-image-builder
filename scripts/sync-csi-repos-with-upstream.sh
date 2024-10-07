#!/bin/bash

source_target_repos=(
    "external-snapshotter:csi-snapshotter"
    "external-resizer:csi-resizer"
    "external-provisioner:csi-provisioner"
    "external-attacher:csi-attacher"
    "node-driver-registrar:csi-node-driver-registrar"
    "livenessprobe:livenessprobe"
)

for source_target_repo in "${source_target_repos[@]}"; do
    source_repo=$(echo "$source_target_repo" | cut -d ":" -f 1)
    target_repo=$(echo "$source_target_repo" | cut -d ":" -f 2)

    echo "Syncing $target_repo"

    SOURCE_REPO_PATH="https://github.com/kubernetes-csi/${source_repo}.git"
    TARGET_REPO_PATH="https://github.com/longhorn/${target_repo}.git"

    git clone ${TARGET_REPO_PATH}
    pushd ${target_repo}

    # Sync branches
    git remote add src_remote ${SOURCE_REPO_PATH}
    git fetch src_remote --quiet
    git push origin "refs/remotes/src_remote/*:refs/heads/*" --force

    # Sync tags
    git fetch src_remote --tags --quiet
    git push origin --tags --force
done