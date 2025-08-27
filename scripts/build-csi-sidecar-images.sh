#!/bin/bash

# Ensure correct number of arguments
if [ "$#" -ne 3 ]; then
    echo "Illegal number of arguments. Registry name, list of repo_branch_tag, and create_tag flag are required." >&2
    exit 1
fi

registry_name="$1"
list_of_repo_branch_tag="$2"
create_tag="$3"

# Split input into array
IFS=' ' read -r -a items <<<"$list_of_repo_branch_tag"

for repo_branch_tag in "${items[@]}"; do
    repo=$(echo "$repo_branch_tag" | cut -d ":" -f 1)
    branch=$(echo "$repo_branch_tag" | cut -d ":" -f 2)
    tag=$(echo "$repo_branch_tag" | cut -d ":" -f 3)

    echo "Processing $repo:$branch:$tag"

    # Check if tag exists on remote
    if gh api -H "Accept: application/vnd.github.v3+json" \
        "/repos/longhorn/${repo}/git/refs/tags/${tag}" >/dev/null 2>&1; then
        echo "Tag $tag already exists on remote"
    else
        if [ "$create_tag" == "true" ]; then
            echo "Creating tag $tag on branch $branch"

            # Get the commit SHA of the branch
            sha=$(gh api -H "Accept: application/vnd.github.v3+json" \
                "/repos/longhorn/${repo}/git/ref/heads/${branch}" | jq -r '.object.sha')

            if [ -z "$sha" ]; then
                echo "Failed to get commit SHA for branch $branch" >&2
                exit 1
            fi

            # Create tag object
            gh api -X POST -H "Accept: application/vnd.github.v3+json" \
                /repos/longhorn/${repo}/git/tags \
                -f tag="$tag" -f message="Release $tag" -f object="$sha" -f type="commit" >/dev/null || {
                    echo "Failed to create tag object $tag" >&2
                    exit 1
                }

            # Create reference for tag
            gh api -X POST -H "Accept: application/vnd.github.v3+json" \
                /repos/longhorn/${repo}/git/refs \
                -f ref="refs/tags/$tag" -f sha="$sha" || {
                    echo "Failed to create tag reference $tag" >&2
                    exit 1
                }

            echo "Tag $tag created successfully on remote"
        else
            echo "Warning: Tag $tag does not exist on remote. Skipping creation."
        fi
    fi

    # Remove existing repo folder if exists
    rm -rf "$repo"

    # Clone repo locally for build
    gh repo clone "longhorn/${repo}" -- -b "$branch" --depth 1 || {
        echo "Failed to clone repository: $repo" >&2
        exit 1
    }

    pushd "$repo" >/dev/null || exit 1

    # Special handling for csi-snapshotter
    if [ "$repo" == "csi-snapshotter" ]; then
        sed -i.bkp 's/CMDS=snapshot-controller csi-snapshotter/CMDS=csi-snapshotter/g' Makefile
    fi

    # Set environment for build
    export REGISTRY_NAME="$registry_name"
    export PULL_BASE_REF="$tag"
    export CSI_PROW_WORK="$(pwd)/csi-prow-work"

    mkdir -p "${CSI_PROW_WORK}" || {
        echo "Failed to create directory ${CSI_PROW_WORK}" >&2
        exit 1
    }

    # Execute build
    bash release-tools/cloudbuild.sh || {
        echo "Failed to execute release-tools/cloudbuild.sh" >&2
        exit 1
    }

    popd >/dev/null
done
