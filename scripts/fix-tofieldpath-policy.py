#!/usr/bin/env python3
"""
Remove invalid policy.toFieldPath: Optional declarations from vpc-standard.yaml.

The composition incorrectly uses:
  policy:
    toFieldPath: Optional

This is invalid because 'Optional' is only valid for fromFieldPath policy, not toFieldPath.
The correct usage for toFieldPath is:
  policy:
    toFieldPath: MergeObjects  # or MergeObjectsAppendArrays

This script removes all lines containing 'toFieldPath: Optional' and their parent 'policy:' line.
"""

import re
import sys

def fix_tofieldpath_policy(content):
    """
    Remove invalid policy.toFieldPath: Optional declarations.

    When we find:
        policy:
          toFieldPath: Optional

    We need to remove BOTH lines (the 'policy:' line and the 'toFieldPath: Optional' line).
    """
    lines = content.split('\n')
    result = []
    i = 0
    removed_count = 0

    while i < len(lines):
        line = lines[i]

        # Check if next line is the invalid toFieldPath: Optional
        if i + 1 < len(lines):
            next_line = lines[i + 1]

            # If current line is 'policy:' and next line is 'toFieldPath: Optional'
            if re.search(r'^\s+policy:\s*$', line) and re.search(r'^\s+toFieldPath:\s+Optional\s*$', next_line):
                # Skip both lines
                i += 2
                removed_count += 1
                continue

        # Keep the line
        result.append(line)
        i += 1

    return '\n'.join(result), removed_count

def main():
    file_path = 'infra-definitions/compositions/network/vpc-standard.yaml'

    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()

    # Fix the syntax
    fixed_content, removed_count = fix_tofieldpath_policy(content)

    # Write back
    with open(file_path, 'w') as f:
        f.write(fixed_content)

    print(f"✅ Fixed toFieldPath policy in {file_path}")
    print(f"   Removed {removed_count} invalid 'policy.toFieldPath: Optional' declarations")

if __name__ == '__main__':
    main()
