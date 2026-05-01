#!/usr/bin/env python3
"""
Bracket balance checker for Dart/Flutter files.
Strips string literals and comments, then verifies bracket balance.
"""

import sys

def strip_strings_and_comments(content):
    """
    Remove string literals and comments from Dart code.
    Handles:
    - Single and double quoted strings (with escape sequences)
    - Raw strings (prefixed with r): r'string' or r"string"
    - Triple-quoted strings
    - Line comments (//)
    - Block comments (/* */)
    """
    result = []
    i = 0
    
    while i < len(content):
        # Check for raw string prefix
        is_raw = False
        if content[i] == 'r' and i + 1 < len(content) and content[i+1] in '"\'':
            is_raw = True
            i += 1
        
        # Check for triple-quoted strings first
        if i + 2 < len(content):
            if content[i:i+3] == "'''":
                i += 3
                while i < len(content):
                    if i + 2 < len(content) and content[i:i+3] == "'''":
                        i += 3
                        break
                    i += 1
                continue
            elif content[i:i+3] == '"""':
                i += 3
                while i < len(content):
                    if i + 2 < len(content) and content[i:i+3] == '"""':
                        i += 3
                        break
                    i += 1
                continue
        
        # Check for single-quoted strings
        if content[i] == "'":
            i += 1
            while i < len(content):
                if content[i] == "'":
                    i += 1
                    break
                # In raw strings, backslash is literal
                if not is_raw and content[i] == '\\' and i + 1 < len(content):
                    i += 2
                else:
                    i += 1
            is_raw = False
            continue
        
        # Check for double-quoted strings
        if content[i] == '"':
            i += 1
            while i < len(content):
                if content[i] == '"':
                    i += 1
                    break
                if not is_raw and content[i] == '\\' and i + 1 < len(content):
                    i += 2
                else:
                    i += 1
            is_raw = False
            continue
        
        # Check for line comments
        if i + 1 < len(content) and content[i:i+2] == '//':
            while i < len(content) and content[i] != '\n':
                i += 1
            if i < len(content):
                result.append('\n')
                i += 1
            continue
        
        # Check for block comments
        if i + 1 < len(content) and content[i:i+2] == '/*':
            i += 2
            while i < len(content):
                if i + 1 < len(content) and content[i:i+2] == '*/':
                    i += 2
                    break
                if content[i] == '\n':
                    result.append('\n')
                i += 1
            continue
        
        result.append(content[i])
        i += 1
    
    return ''.join(result)

def check_bracket_balance(content):
    """
    Check if brackets are balanced in the given content.
    Returns (is_balanced, counts, errors)
    """
    stack = []
    pairs = {'(': ')', '[': ']', '{': '}'}
    brackets_found = {'(': 0, ')': 0, '[': 0, ']': 0, '{': 0, '}': 0}
    errors = []
    
    for i, char in enumerate(content):
        if char in pairs:
            stack.append((char, i))
            brackets_found[char] += 1
        elif char in pairs.values():
            brackets_found[char] += 1
            if not stack:
                errors.append(f"Line {content[:i].count(chr(10)) + 1}: Unexpected closing bracket '{char}'")
                continue
            
            opening, opening_pos = stack[-1]
            if pairs[opening] == char:
                stack.pop()
            else:
                errors.append(
                    f"Line {content[:i].count(chr(10)) + 1}: Mismatched bracket '{opening}' "
                    f"(opened at line {content[:opening_pos].count(chr(10)) + 1}) closed by '{char}'"
                )
                stack.pop()
    
    for bracket, pos in stack:
        errors.append(f"Line {content[:pos].count(chr(10)) + 1}: Unclosed bracket '{bracket}'")
    
    return len(errors) == 0, brackets_found, errors

def main():
    if len(sys.argv) != 2:
        print("Usage: python bracket_checker.py <file_path>")
        sys.exit(1)
    
    file_path = sys.argv[1]
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {file_path}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)
    
    print(f"Analyzing: {file_path}")
    print("=" * 70)
    
    cleaned = strip_strings_and_comments(content)
    is_balanced, brackets, errors = check_bracket_balance(cleaned)
    
    print("\nBracket Summary:")
    print(f"  Opening parentheses '(':  {brackets['(']}")
    print(f"  Closing parentheses ')':  {brackets[')']}")
    print(f"  Opening square brackets '[': {brackets['[']}")
    print(f"  Closing square brackets ']': {brackets[']']}")
    print(f"  Opening curly braces '{{':   {brackets['{']}")
    print(f"  Closing curly braces '}}':   {brackets['}']}")
    
    print("\n" + "=" * 70)
    if is_balanced:
        print("STATUS: All brackets are BALANCED")
    else:
        print("STATUS: Brackets are UNBALANCED")
        print("\nErrors found:")
        for error in errors:
            print(f"  - {error}")
    
    print("=" * 70)
    
    return 0 if is_balanced else 1

if __name__ == '__main__':
    sys.exit(main())
