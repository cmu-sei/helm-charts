#!/usr/bin/env python3
"""Check that parent Helm chart values.yaml files contain the full content of
their child chart values.yaml files (indented under the subchart key).

Usage:
    python check-values-sync.py                          # check all parent/child pairs
    python check-values-sync.py charts/alloy             # check only specified charts
    python check-values-sync.py charts/alloy charts/player
    python check-values-sync.py --base-ref origin/main   # check only charts whose
                                                         # values.yaml changed vs the ref
"""

import argparse
import difflib
import os
import re
import subprocess
import sys

CHARTS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "charts")

EXCLUDED_CHARTS = {"osticket", "webmail", "identity"}


def changed_top_charts(base_ref: str) -> list[str]:
    """Return absolute paths of top-level chart dirs whose values.yaml changed.

    Uses a triple-dot diff (`base_ref...HEAD`), so the comparison is against
    the merge-base of `base_ref` and HEAD — i.e., changes introduced on this
    branch since it forked from `base_ref`, not changes that landed on the
    base afterward. This matches what PR review tools show.

    A subchart values.yaml change pulls in its top-level parent (both share
    the same charts/<top> prefix). EXCLUDED_CHARTS are filtered out for
    consistency with the no-args sweep path.
    """
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base_ref}...HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    charts_root = os.path.abspath(CHARTS_DIR)
    tops: set[str] = set()
    pattern = re.compile(r"^charts/([^/]+)/.*values\.yaml$")
    for line in result.stdout.splitlines():
        m = pattern.match(line)
        if m and m.group(1) not in EXCLUDED_CHARTS:
            tops.add(os.path.join(charts_root, m.group(1)))
    return sorted(tops)


def find_parent_charts(chart_paths: list[str] | None = None) -> list[str]:
    """Return absolute paths of parent charts that have subcharts."""
    charts_root = os.path.abspath(CHARTS_DIR)

    if chart_paths:
        dirs = [os.path.abspath(p) for p in chart_paths]
    else:
        dirs = [
            os.path.join(charts_root, d)
            for d in sorted(os.listdir(charts_root))
            if os.path.isdir(os.path.join(charts_root, d))
            and d not in EXCLUDED_CHARTS
        ]

    parents = []
    for d in dirs:
        subcharts_dir = os.path.join(d, "charts")
        if os.path.isdir(subcharts_dir):
            subdirs = [
                s
                for s in os.listdir(subcharts_dir)
                if os.path.isdir(os.path.join(subcharts_dir, s))
            ]
            if subdirs:
                parents.append(d)
    return parents


def get_child_dirs(parent_path: str) -> list[str]:
    """Return sorted list of child chart directory paths (excluding .tgz files)."""
    subcharts_dir = os.path.join(parent_path, "charts")
    return sorted(
        os.path.join(subcharts_dir, d)
        for d in os.listdir(subcharts_dir)
        if os.path.isdir(os.path.join(subcharts_dir, d))
    )


def indent(text: str, spaces: int = 2) -> str:
    """Indent every line of text by the given number of spaces.
    Empty lines remain empty (no trailing whitespace)."""
    prefix = " " * spaces
    lines = text.split("\n")
    result = []
    for line in lines:
        if line.strip() == "":
            result.append("")
        else:
            result.append(prefix + line)
    return "\n".join(result)


def extract_parent_block(parent_content: str, subchart_key: str) -> str | None:
    """Extract the raw text block for a subchart key from the parent values.yaml.

    Finds the top-level key line (e.g., 'alloy-api:') and captures all following
    lines that are indented (or blank) until the next top-level key or EOF.
    Returns the block with indentation removed (de-indented by 2 spaces).
    """
    lines = parent_content.split("\n")
    key_pattern = re.compile(rf"^{re.escape(subchart_key)}:\s*$")

    start = None
    for i, line in enumerate(lines):
        if key_pattern.match(line):
            start = i + 1
            break

    if start is None:
        return None

    # Collect all lines until next top-level key (non-indented, non-blank, non-comment at col 0)
    end = len(lines)
    for i in range(start, len(lines)):
        # A top-level key is a non-blank line that starts at column 0 and isn't just a comment
        if lines[i] and not lines[i][0].isspace() and not lines[i].startswith("#"):
            # Check if this looks like a YAML key (word followed by colon)
            if re.match(r"^[a-zA-Z_][a-zA-Z0-9_-]*:", lines[i]):
                end = i
                break

    block_lines = lines[start:end]

    # Remove trailing empty lines
    while block_lines and block_lines[-1].strip() == "":
        block_lines.pop()

    # De-indent by 2 spaces
    result = []
    for line in block_lines:
        if line == "" or line.strip() == "":
            result.append("")
        elif line.startswith("  "):
            result.append(line[2:])
        else:
            # Line isn't indented as expected - include as-is
            result.append(line)
    return "\n".join(result)


def check_chart(parent_path: str) -> list[str]:
    """Check all child charts of a parent. Returns list of error messages."""
    parent_values_path = os.path.join(parent_path, "values.yaml")
    if not os.path.isfile(parent_values_path):
        return [f"{parent_path}: no values.yaml found"]

    with open(parent_values_path) as f:
        parent_content = f.read()

    errors = []
    child_dirs = get_child_dirs(parent_path)

    for child_dir in child_dirs:
        child_name = os.path.basename(child_dir)
        child_values_path = os.path.join(child_dir, "values.yaml")

        if not os.path.isfile(child_values_path):
            continue

        with open(child_values_path) as f:
            child_content = f.read()

        # Remove trailing newline for consistent comparison
        child_stripped = child_content.rstrip("\n")

        # Extract the corresponding block from parent
        parent_block = extract_parent_block(parent_content, child_name)

        if parent_block is None:
            errors.append(
                f"{os.path.basename(parent_path)}: missing key '{child_name}:' "
                f"in parent values.yaml"
            )
            continue

        parent_block = parent_block.rstrip("\n")

        if child_stripped != parent_block:
            # Generate a unified diff
            child_lines = child_stripped.splitlines(keepends=True)
            parent_lines = parent_block.splitlines(keepends=True)
            diff = difflib.unified_diff(
                child_lines,
                parent_lines,
                fromfile=f"{child_name}/values.yaml",
                tofile=f"{os.path.basename(parent_path)}/values.yaml [{child_name}:] (parent)",
                lineterm="",
            )
            diff_text = "\n".join(diff)
            errors.append(
                f"{os.path.basename(parent_path)}/{child_name}: "
                f"parent block does not match child values.yaml\n{diff_text}"
            )

    return errors


def main():
    parser = argparse.ArgumentParser(
        description="Check parent/child Helm chart values.yaml sync.",
    )
    parser.add_argument(
        "--base-ref",
        help="Git ref to diff against. When set, only charts with values.yaml "
        "changes between the ref and HEAD are checked.",
    )
    parser.add_argument(
        "chart_paths",
        nargs="*",
        help="Specific chart paths to check. Overrides --base-ref.",
    )
    args = parser.parse_args()

    if args.chart_paths:
        chart_paths = args.chart_paths
    elif args.base_ref:
        chart_paths = changed_top_charts(args.base_ref)
        if not chart_paths:
            print(f"No chart values.yaml changes detected against {args.base_ref}.")
            sys.exit(0)
    else:
        chart_paths = None

    parents = find_parent_charts(chart_paths)

    if not parents:
        print("No parent charts with subcharts found.")
        sys.exit(0)

    all_errors = []
    for parent in parents:
        parent_name = os.path.basename(parent)
        child_dirs = get_child_dirs(parent)
        child_names = [os.path.basename(d) for d in child_dirs]
        print(f"Checking {parent_name} ({', '.join(child_names)})")
        errors = check_chart(parent)
        all_errors.extend(errors)

    print()
    if all_errors:
        print(f"FAILED: {len(all_errors)} sync error(s) found:\n")
        for err in all_errors:
            print(f"  {err}\n")
        print(
            "Parent values.yaml must contain the child values.yaml content "
            "indented under the subchart key."
        )
        sys.exit(1)
    else:
        print("SUCCESS: All parent/child values are in sync.")
        sys.exit(0)


if __name__ == "__main__":
    main()
