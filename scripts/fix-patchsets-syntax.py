#!/usr/bin/env python3
"""
Fix patchSets syntax in vpc-standard.yaml composition.

The composition incorrectly uses:
  resources:
    - name: resource1
      patchSets:
        - provider-config
        - region

This script converts to the correct syntax:
  resources:
    - name: resource1
      patches:
        - type: PatchSet
          patchSetName: provider-config
        - type: PatchSet
          patchSetName: region
"""

import re
import sys

def fix_patchsets_syntax(content):
    """
    Convert resource-level patchSets to proper patches with PatchSet type.

    Transforms:
      patchSets:
        - provider-config
        - region
        - standard-tags

    Into:
      patches:
        - type: PatchSet
          patchSetName: provider-config
        - type: PatchSet
          patchSetName: region
        - type: PatchSet
          patchSetName: standard-tags
    """
    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check if this is a resource-level patchSets (not the top-level one at line 25)
        # Resource-level patchSets have more indentation (12 spaces)
        if re.match(r'^\s{12}patchSets:\s*$', line):
            indent = ' ' * 12

            # Collect the patchSet names (including hyphens in names like "provider-config")
            patchset_names = []
            i += 1
            while i < len(lines) and re.match(r'^\s{14}- ', lines[i]):
                match = re.match(r'^\s{14}- ([\w-]+)', lines[i])
                if match:
                    patchset_names.append(match.group(1))
                i += 1

            # Check if there's already a patches: section after patchSets
            if i < len(lines) and re.match(r'^\s{12}patches:\s*$', lines[i]):
                # There's already a patches section, prepend PatchSet references
                result.append(f"{indent}patches:")
                for name in patchset_names:
                    result.append(f"{indent}  - type: PatchSet")
                    result.append(f"{indent}    patchSetName: {name}")
                # Skip the existing "patches:" line
                i += 1
                # Continue with existing patches
                continue
            else:
                # No patches section yet, check if next is base:
                if i < len(lines) and re.match(r'^\s{12}base:\s*$', lines[i]):
                    # Insert patches before base
                    result.append(f"{indent}patches:")
                    for name in patchset_names:
                        result.append(f"{indent}  - type: PatchSet")
                        result.append(f"{indent}    patchSetName: {name}")
                    # Continue to process base
                    continue
                else:
                    # Unexpected structure, keep original
                    result.append(line)
                    i += 1
                    continue
        else:
            result.append(line)
            i += 1

    return '\n'.join(result)

def main():
    file_path = 'infra-definitions/compositions/network/vpc-standard.yaml'

    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()

    # Fix the syntax
    fixed_content = fix_patchsets_syntax(content)

    # Write back
    with open(file_path, 'w') as f:
        f.write(fixed_content)

    print(f"✅ Fixed patchSets syntax in {file_path}")
    print("   Converted resource-level 'patchSets:' to 'patches:' with 'type: PatchSet'")

if __name__ == '__main__':
    main()
