#!/usr/bin/env bash
set -euo pipefail

# install.sh - Deploy skills to target directories
#
# Usage: ./install.sh [--force] TARGET_DIR [TARGET_DIR2 ...]
#
# Copies each skill in skills/ to TARGET_DIR/<skill>. Only skill directories
# owned by this project are ever written. Ownership is tracked in
# TARGET_DIR/.agent-config-manifest:
#   - a skill listed in the manifest is updated from skills/
#   - a pre-existing skill directory NOT in the manifest is left untouched and
#     the deploy aborts, unless --force is given to adopt it
# This script never deletes anything. Stale files inside managed skills, and
# managed skills no longer in skills/, are printed as rm commands to review
# and run manually. Anything else in TARGET_DIR is never touched.

MANIFEST_NAME=".agent-config-manifest"
FORCE=0

if [ "${1:-}" = "--force" ]; then
    FORCE=1
    shift
fi

if [ $# -eq 0 ]; then
    echo "Error: No target directory specified"
    echo "Usage: $0 [--force] TARGET_DIR [TARGET_DIR2 ...]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"

if [ ! -d "$SKILLS_SOURCE" ]; then
    echo "Error: Skills source directory '$SKILLS_SOURCE' not found"
    exit 1
fi

# Skill names are used to build paths that get deleted, so keep them simple
valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

SKILLS=()
for dir in "$SKILLS_SOURCE"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if ! valid_name "$name"; then
        echo "Error: Invalid skill directory name '$name'"
        exit 1
    fi
    SKILLS+=("$name")
done

if [ ${#SKILLS[@]} -eq 0 ]; then
    echo "Error: No skills found in '$SKILLS_SOURCE'"
    exit 1
fi

in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

copy_skill() {
    local src="$1" dest="$2"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "$src/" "$dest/"
    else
        mkdir -p "$dest"
        cp -R "$src/." "$dest/"
    fi
}

list_tree() {
    (cd "$1" && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort)
}

# Print paths under dest that don't exist under src, skipping children of
# paths already reported (rm -r on the parent covers them)
stale_paths() {
    local src="$1" dest="$2" path last=""
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -n "$last" ] && [[ "$path" == "$last"/* ]]; then
            continue
        fi
        last="$path"
        printf '%s\n' "$path"
    done < <(LC_ALL=C comm -13 <(list_tree "$src") <(list_tree "$dest"))
}

CLEANUP=()

# Deploy to each target directory
for TARGET_DIR in "$@"; do
    if [ -z "$TARGET_DIR" ]; then
        echo "Error: Empty target directory"
        exit 1
    fi
    mkdir -p "$TARGET_DIR"
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

    if [ "$TARGET_DIR" = "/" ] || [ "$TARGET_DIR" = "$HOME" ] || [ "$TARGET_DIR" = "$SKILLS_SOURCE" ]; then
        echo "Error: Refusing to deploy to '$TARGET_DIR'"
        exit 1
    fi

    echo "Deploying to: $TARGET_DIR"
    MANIFEST="$TARGET_DIR/$MANIFEST_NAME"

    MANAGED=()
    if [ -f "$MANIFEST" ]; then
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            if valid_name "$name"; then
                MANAGED+=("$name")
            else
                echo "  ! ignoring invalid manifest entry '$name'"
            fi
        done < "$MANIFEST"
    fi

    # Never clobber a skill this project doesn't own
    CONFLICTS=()
    for name in "${SKILLS[@]}"; do
        if [ -e "$TARGET_DIR/$name" ] && ! in_list "$name" ${MANAGED[@]+"${MANAGED[@]}"}; then
            CONFLICTS+=("$name")
        fi
    done
    if [ ${#CONFLICTS[@]} -gt 0 ] && [ "$FORCE" -ne 1 ]; then
        echo "Error: These skills already exist in $TARGET_DIR and are not managed by this project:"
        printf '  - %s\n' "${CONFLICTS[@]}"
        echo "Remove or rename them, or re-run with --force (make deploy FORCE=1) to take ownership."
        exit 1
    fi

    for name in "${SKILLS[@]}"; do
        echo "  + $name"
        copy_skill "$SKILLS_SOURCE/$name" "$TARGET_DIR/$name"
        while IFS= read -r path; do
            CLEANUP+=("$(printf 'rm -r -- %q' "$TARGET_DIR/$name/$path")")
        done < <(stale_paths "$SKILLS_SOURCE/$name" "$TARGET_DIR/$name")
    done

    # Skills previously deployed but no longer shipped stay in the manifest
    # until they are removed, so the cleanup reminder repeats on every deploy
    NEW_MANIFEST=("${SKILLS[@]}")
    for name in ${MANAGED[@]+"${MANAGED[@]}"}; do
        if ! in_list "$name" "${SKILLS[@]}" && [ -e "$TARGET_DIR/$name" ]; then
            CLEANUP+=("$(printf 'rm -r -- %q' "$TARGET_DIR/$name")")
            NEW_MANIFEST+=("$name")
        fi
    done

    printf '%s\n' "${NEW_MANIFEST[@]}" > "$MANIFEST"

    echo "✓ Deployed to $TARGET_DIR"
    echo ""
done

echo "✓ Deployment complete!"

if [ ${#CLEANUP[@]} -gt 0 ]; then
    echo ""
    echo "The following managed paths are no longer in this project."
    echo "Nothing was deleted. Review and run these commands to clean up:"
    echo ""
    printf '  %s\n' "${CLEANUP[@]}"
fi
