#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Illegal number of arguments. Registry name and list of repo_branch_tag are required." >/dev/stderr
    exit 1
fi

registry_name="$1"
list_of_repo_branch_tag="$2"

IFS=' ' read -r -a items <<<"$list_of_repo_branch_tag"

for repo_branch_tag in "${items[@]}"; do
    repo=$(echo "$repo_branch_tag" | cut -d ":" -f 1)
    branch=$(echo "$repo_branch_tag" | cut -d ":" -f 2)
    tag=$(echo "$repo_branch_tag" | cut -d ":" -f 3)

    echo "Building $repo:$branch:$tag"

    # Clone the repository and checkout the specified branch
    git clone --branch "$branch" "https://github.com/longhorn/${repo}.git" || {
        echo "Failed to clone repository: $repo" >&2
        exit 1
    }

    pushd "$repo" >/dev/null || {
        echo "Failed to enter directory: $repo" >&2
        exit 1
    }

    # Check if the tag already exists
    if git rev-parse "$tag" >/dev/null 2>&1; then
        echo "Tag $tag already exists"
    else
        git tag "$tag"
        git push origin "$tag"
    fi

    if [ "$repo" == "csi-snapshotter" ]; then
        # Only build csi-snapshotter
        sed -i '' 's/CMDS=snapshot-controller csi-snapshotter snapshot-validation-webhook/CMDS=csi-snapshotter/g' Makefile
    fi

    # Run the release build
    export REGISTRY_NAME="$registry_name"
    export PULL_BASE_REF="$tag"
    bash release-tools/cloudbuild.sh

    popd >/dev/null
done