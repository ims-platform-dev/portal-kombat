#!/usr/bin/env python3
"""
Fix matchLabels selector syntax in vpc-standard.yaml composition.

The composition incorrectly uses dot notation for label keys with dots/slashes:
  toFieldPath: spec.forProvider.routeTableIdSelector.matchLabels.portal-kombat.io/network-route-table-name

This is interpreted as nested maps: matchLabels.portal-kombat -> {"io/network-route-table-name": "value"}

This script converts to bracket notation:
  toFieldPath: spec.forProvider.routeTableIdSelector.matchLabels[portal-kombat.io/network-route-table-name]
"""

import re

def fix_matchlabels_bracket_notation(content):
    """
    Convert matchLabels selector syntax from dot notation to bracket notation.

    Patterns to fix:
    - matchLabels.portal-kombat.io/network-route-table-name
    - matchLabels.portal-kombat.io/network-subnet-name
    - matchLabels.portal-kombat.io/network-component
    """

    # Pattern 1: matchLabels.portal-kombat.io/network-route-table-name
    content = re.sub(
        r'matchLabels\.portal-kombat\.io/network-route-table-name',
        r'matchLabels[portal-kombat.io/network-route-table-name]',
        content
    )

    # Pattern 2: matchLabels.portal-kombat.io/network-subnet-name
    content = re.sub(
        r'matchLabels\.portal-kombat\.io/network-subnet-name',
        r'matchLabels[portal-kombat.io/network-subnet-name]',
        content
    )

    # Pattern 3: matchLabels.portal-kombat.io/network-component
    content = re.sub(
        r'matchLabels\.portal-kombat\.io/network-component',
        r'matchLabels[portal-kombat.io/network-component]',
        content
    )

    # Pattern 4: matchLabels.portal-kombat.io/network-claim
    content = re.sub(
        r'matchLabels\.portal-kombat\.io/network-claim',
        r'matchLabels[portal-kombat.io/network-claim]',
        content
    )

    return content

def main():
    file_path = 'infra-definitions/compositions/network/vpc-standard.yaml'

    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()

    # Count occurrences before fix
    dot_notation_count = len(re.findall(r'matchLabels\.portal-kombat\.io/', content))

    # Fix the syntax
    fixed_content = fix_matchlabels_bracket_notation(content)

    # Count occurrences after fix (should be 0)
    remaining_count = len(re.findall(r'matchLabels\.portal-kombat\.io/', fixed_content))

    # Write back
    with open(file_path, 'w') as f:
        f.write(fixed_content)

    print(f"✅ Fixed matchLabels bracket notation in {file_path}")
    print(f"   Converted {dot_notation_count} occurrences from dot notation to bracket notation")
    print(f"   Remaining dot notation issues: {remaining_count}")

if __name__ == '__main__':
    main()
